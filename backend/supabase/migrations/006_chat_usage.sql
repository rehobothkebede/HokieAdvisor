-- Per-user daily chat quota for the chat Edge Function.
-- Independent of 005_multi_institution.sql; safe to re-run.
--
-- The chat function calls consume_chat_quota() with the service-role key
-- before every OpenAI request. Days roll over at midnight America/New_York.
-- Users can read their own usage but cannot write it or call the function.

create table if not exists public.chat_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date)
);

alter table public.chat_usage enable row level security;

drop policy if exists "chat usage is readable by owner" on public.chat_usage;
create policy "chat usage is readable by owner" on public.chat_usage
for select using (auth.uid() = user_id);

revoke all on public.chat_usage from anon, authenticated;
grant select on public.chat_usage to authenticated;
grant select, insert, update, delete on public.chat_usage to service_role;

-- Increments today's count only while it is below p_limit. When the user is
-- already at the limit the conditional update matches nothing, so the count
-- stays put and allowed comes back false.
create or replace function public.consume_chat_quota(p_user_id uuid, p_limit integer)
returns table (allowed boolean, used integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'America/New_York')::date;
  v_count integer;
begin
  insert into public.chat_usage as u (user_id, usage_date, request_count)
  values (p_user_id, v_today, 1)
  on conflict (user_id, usage_date) do update
    set request_count = u.request_count + 1,
        updated_at = now()
    where u.request_count < p_limit
  returning u.request_count into v_count;

  if v_count is null then
    return query select false, p_limit;
  else
    return query select true, v_count;
  end if;
end;
$$;

revoke all on function public.consume_chat_quota(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_chat_quota(uuid, integer) to service_role;
