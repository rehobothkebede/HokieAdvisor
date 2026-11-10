-- Course companion, stage 3: student review of extracted facts, private
-- corrections, and optional reminders for confirmed dates.
-- Apply after 008_course_companion_syllabi.sql.
--
-- LOCAL ONLY until approved. Do not apply to hosted Supabase outside an
-- approved deployment window.
--
-- Rules enforced here, not only in the app:
-- - Students may change only a fact's review state; extracted content stays
--   exactly as read from the document.
-- - A fact whose excerpt wasn't found in the document can't be confirmed as-is
--   (only corrected or rejected), and a date from another term's syllabus can
--   never be confirmed.
-- - Corrections are a separate, private table and never alter the document's
--   facts. Nothing here is shared.
-- - Reminders can only point at the student's own confirmed facts, and a
--   per-student dedupe key prevents duplicates.

-- ---------------------------------------------------------------------------
-- Review state on extracted facts
-- ---------------------------------------------------------------------------

create table if not exists public.syllabus_fact_corrections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fact_id uuid not null,
  -- Only the fields the student corrected: date, start_time, end_time,
  -- location, weight_percent, text.
  corrected jsonb not null check (jsonb_typeof(corrected) = 'object'),
  note text check (note is null or char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (fact_id, user_id) references public.syllabus_facts (id, user_id) on delete cascade,
  unique (fact_id)
);

drop trigger if exists syllabus_fact_corrections_set_updated_at on public.syllabus_fact_corrections;
create trigger syllabus_fact_corrections_set_updated_at before update on public.syllabus_fact_corrections
for each row execute function public.set_updated_at();

create or replace function public.syllabus_facts_guard_review()
returns trigger
language plpgsql
as $$
begin
  if new.review_state = 'confirmed' and old.review_state is distinct from 'confirmed' then
    if 'other_term' = any (new.issues) then
      raise exception 'Dates from another term''s syllabus can''t be confirmed.' using errcode = 'check_violation';
    end if;
    if new.evidence = 'not_found' and not exists (
      select 1 from public.syllabus_fact_corrections c where c.fact_id = new.id
    ) then
      raise exception 'This detail wasn''t found in the document. Correct it or mark it not right.'
        using errcode = 'check_violation';
    end if;
  end if;
  new.reviewed_at = case when new.review_state = 'pending' then null else now() end;
  return new;
end;
$$;

drop trigger if exists syllabus_facts_guard_review on public.syllabus_facts;
create trigger syllabus_facts_guard_review before update of review_state on public.syllabus_facts
for each row execute function public.syllabus_facts_guard_review();

-- Corrections for another term's dates are refused too.
create or replace function public.syllabus_fact_corrections_guard()
returns trigger
language plpgsql
as $$
begin
  if new.corrected ? 'date' and exists (
    select 1 from public.syllabus_facts f where f.id = new.fact_id and 'other_term' = any (f.issues)
  ) then
    raise exception 'Dates from another term''s syllabus can''t be used.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists syllabus_fact_corrections_guard on public.syllabus_fact_corrections;
create trigger syllabus_fact_corrections_guard before insert or update on public.syllabus_fact_corrections
for each row execute function public.syllabus_fact_corrections_guard();

-- ---------------------------------------------------------------------------
-- Reminders for confirmed dates (scheduled on the student's device)
-- ---------------------------------------------------------------------------

create table if not exists public.course_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  course_id uuid not null,
  fact_id uuid not null,
  lead text not null check (lead in ('week_before', 'day_before', 'morning_of')),
  fires_at timestamptz not null,
  title text not null check (char_length(title) <= 200),
  body text not null check (char_length(body) <= 400),
  -- course + fact identity + effective date + lead: the same reminder twice
  -- is impossible, even across syllabus versions.
  dedupe_key text not null,
  -- needs_reconfirm: the date changed in a newer syllabus version.
  state text not null default 'active' check (state in ('active', 'needs_reconfirm')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_id, user_id) references public.enrolled_courses (id, user_id) on delete cascade,
  foreign key (fact_id, user_id) references public.syllabus_facts (id, user_id) on delete cascade,
  unique (user_id, dedupe_key)
);

create index if not exists idx_course_reminders_user on public.course_reminders (user_id, state);

drop trigger if exists course_reminders_set_updated_at on public.course_reminders;
create trigger course_reminders_set_updated_at before update on public.course_reminders
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row-level security and grants
-- ---------------------------------------------------------------------------

alter table public.syllabus_fact_corrections enable row level security;
alter table public.course_reminders enable row level security;

drop policy if exists "syllabus facts review state is updatable by owner" on public.syllabus_facts;
create policy "syllabus facts review state is updatable by owner" on public.syllabus_facts
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Column-level: review state only. Everything else stays as extracted.
grant update (review_state) on public.syllabus_facts to authenticated;

drop policy if exists "fact corrections are user owned" on public.syllabus_fact_corrections;
create policy "fact corrections are user owned" on public.syllabus_fact_corrections
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "course reminders are user owned" on public.course_reminders;
create policy "course reminders are user owned" on public.course_reminders
for all to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and exists (
    select 1 from public.syllabus_facts f
    where f.id = course_reminders.fact_id and f.user_id = auth.uid() and f.review_state = 'confirmed'
  )
);

grant select, insert, update, delete on public.syllabus_fact_corrections, public.course_reminders to authenticated;
grant select, insert, update, delete on public.syllabus_fact_corrections, public.course_reminders to service_role;
