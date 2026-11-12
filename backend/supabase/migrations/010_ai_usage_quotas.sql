-- MyAdvisor pilot: strict, atomic allowances for paid AI calls.
-- Additive; does not modify 006. Safe to re-run.
--
-- Two independent allowance kinds:
--   chat      advisor replies (chat and chat/stream)
--   document  transcript, DARS, and syllabus extractions (combined)
--
-- Each kind has three limits, all checked and consumed in one transaction:
--   per-user daily   resets at midnight America/New_York
--   shared daily     across every account, same calendar day
--   per-user burst   at most N reservations within a rolling window that
--                    starts at the first reservation after the last window
--
-- Limits are passed by the Edge Functions from validated server env vars and
-- re-validated here. The function is callable only by service_role.
--
-- A reservation is taken BEFORE the paid call and is never refunded, so a
-- provider failure or timeout after reservation still counts (the provider
-- may have billed it). Denied reservations do not increment anything, and
-- requests rejected before reserving (bad input, no session) cost nothing.
-- These are request counts, not dollar or token caps.
--
-- Concurrency: the three counter rows are locked in a fixed order (user
-- daily, user burst, shared daily), so parallel requests serialize on them
-- and cannot overshoot a limit or deadlock.
--
-- 006's chat_usage table and consume_chat_quota() are left in place but are
-- no longer called by the chat function after this migration.

create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('chat', 'document')),
  usage_date date not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, usage_date)
);

create table if not exists public.ai_usage_global_daily (
  kind text not null check (kind in ('chat', 'document')),
  usage_date date not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (kind, usage_date)
);

create table if not exists public.ai_usage_burst (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('chat', 'document')),
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, kind)
);

alter table public.ai_usage_daily enable row level security;
alter table public.ai_usage_global_daily enable row level security;
alter table public.ai_usage_burst enable row level security;

-- Students may read their own daily usage (e.g. "3 of 10 used today").
drop policy if exists "ai usage is readable by owner" on public.ai_usage_daily;
create policy "ai usage is readable by owner" on public.ai_usage_daily
for select using (auth.uid() = user_id);

-- Shared totals and burst windows are server-only: no policies, no grants.
revoke all on public.ai_usage_daily from public, anon, authenticated;
revoke all on public.ai_usage_global_daily from public, anon, authenticated;
revoke all on public.ai_usage_burst from public, anon, authenticated;
grant select on public.ai_usage_daily to authenticated;
grant select, insert, update, delete on public.ai_usage_daily to service_role;
grant select, insert, update, delete on public.ai_usage_global_daily to service_role;
grant select, insert, update, delete on public.ai_usage_burst to service_role;

-- reason: 'ok' | 'user_daily' | 'global_daily' | 'burst'
create or replace function public.reserve_ai_quota(
  p_user_id uuid,
  p_kind text,
  p_user_daily_limit integer,
  p_global_daily_limit integer,
  p_burst_limit integer,
  p_burst_window_seconds integer
)
returns table (
  allowed boolean,
  reason text,
  user_used integer,
  user_limit integer,
  global_used integer,
  global_limit integer,
  retry_after_seconds integer
)
language plpgsql
security definer
-- pg_temp last so a caller's temporary objects can't shadow these tables.
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_today date := (v_now at time zone 'America/New_York')::date;
  v_user integer;
  v_global integer;
  v_burst integer;
  v_window_start timestamptz;
  v_window interval;
  v_tomorrow timestamptz;
begin
  if p_user_id is null then
    raise exception 'reserve_ai_quota: user required' using errcode = '22023';
  end if;
  if p_kind is null or p_kind not in ('chat', 'document') then
    raise exception 'reserve_ai_quota: unknown kind' using errcode = '22023';
  end if;
  if p_user_daily_limit is null or p_user_daily_limit < 1 or p_user_daily_limit > 1000
     or p_global_daily_limit is null or p_global_daily_limit < 1 or p_global_daily_limit > 100000
     or p_burst_limit is null or p_burst_limit < 1 or p_burst_limit > 100
     or p_burst_window_seconds is null or p_burst_window_seconds < 1 or p_burst_window_seconds > 86400 then
    raise exception 'reserve_ai_quota: limit out of range' using errcode = '22023';
  end if;

  v_window := make_interval(secs => p_burst_window_seconds);
  v_tomorrow := ((v_today + 1)::timestamp at time zone 'America/New_York');

  -- Make sure all three rows exist, then lock them in a fixed order (this
  -- user's rows first, the shared row last) so concurrent reservations
  -- serialize instead of racing or deadlocking.
  insert into public.ai_usage_daily (user_id, kind, usage_date)
  values (p_user_id, p_kind, v_today) on conflict do nothing;
  insert into public.ai_usage_burst (user_id, kind, window_started_at)
  values (p_user_id, p_kind, v_now) on conflict do nothing;
  insert into public.ai_usage_global_daily (kind, usage_date)
  values (p_kind, v_today) on conflict do nothing;

  select d.request_count into v_user from public.ai_usage_daily d
  where d.user_id = p_user_id and d.kind = p_kind and d.usage_date = v_today
  for update;

  select b.request_count, b.window_started_at into v_burst, v_window_start from public.ai_usage_burst b
  where b.user_id = p_user_id and b.kind = p_kind
  for update;

  select g.request_count into v_global from public.ai_usage_global_daily g
  where g.kind = p_kind and g.usage_date = v_today
  for update;

  if v_window_start + v_window <= v_now then
    v_burst := 0;
    v_window_start := v_now;
  end if;

  if v_user >= p_user_daily_limit then
    return query select false, 'user_daily'::text, v_user, p_user_daily_limit, v_global, p_global_daily_limit,
      greatest(1, ceil(extract(epoch from (v_tomorrow - v_now)))::integer);
    return;
  end if;
  if v_burst >= p_burst_limit then
    return query select false, 'burst'::text, v_user, p_user_daily_limit, v_global, p_global_daily_limit,
      greatest(1, ceil(extract(epoch from (v_window_start + v_window - v_now)))::integer);
    return;
  end if;
  if v_global >= p_global_daily_limit then
    return query select false, 'global_daily'::text, v_user, p_user_daily_limit, v_global, p_global_daily_limit,
      greatest(1, ceil(extract(epoch from (v_tomorrow - v_now)))::integer);
    return;
  end if;

  update public.ai_usage_daily set request_count = v_user + 1, updated_at = v_now
  where user_id = p_user_id and kind = p_kind and usage_date = v_today;
  update public.ai_usage_burst set request_count = v_burst + 1, window_started_at = v_window_start
  where user_id = p_user_id and kind = p_kind;
  update public.ai_usage_global_daily set request_count = v_global + 1, updated_at = v_now
  where kind = p_kind and usage_date = v_today;

  return query select true, 'ok'::text, v_user + 1, p_user_daily_limit, v_global + 1, p_global_daily_limit, 0;
end;
$$;

revoke all on function public.reserve_ai_quota(uuid, text, integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.reserve_ai_quota(uuid, text, integer, integer, integer, integer)
  to service_role;
