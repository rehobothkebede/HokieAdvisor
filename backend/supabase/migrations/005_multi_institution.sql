-- Multi-institution foundation.
-- Apply after 004_user_owned_child_integrity.sql.
--
-- Adds an institutions table, scopes every catalog table by institution_id,
-- links profiles to an institution, and adds degree_audit_specs so audit rules
-- can live in data instead of edge-function code. Virginia Tech is seeded as
-- the first institution and every existing row is backfilled to it.
--
-- DO NOT apply to hosted Supabase outside an approved deployment window. Like
-- 001-004 this file has no explicit begin/commit: the Supabase CLI runs each
-- migration file in its own transaction. The file is safe to re-run.
--
-- Deploy-ordering hazards:
-- - Catalog primary keys now lead with institution_id. The current
--   supabase_catalog_sync.py upserts with on_conflict=code / subject,code /
--   key / program_key / code,concept, which will FAIL until the sync script
--   sends institution_id and uses the new conflict keys. Ship them together.
-- - The audit Edge Function queries pathways_courses without an institution
--   filter. That is correct only while VT is the sole institution; add the
--   filter before seeding a second institution.
-- - profiles.vt_pid / vt_email stay for one release so shipped iOS builds keep
--   working. A follow-up 006 drops them, removes the VT fallback in
--   handle_new_user(), renames pathways_courses to gen_ed_courses, and folds
--   coe_courses into catalog_courses.

-- ---------------------------------------------------------------------------
-- Institutions
-- ---------------------------------------------------------------------------

create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  short_name text,
  email_domains text[] not null default '{}',
  student_id_label text,
  student_id_pattern text,
  course_code_pattern text not null,
  course_level_divisor integer not null default 1000,
  default_catalog_year text,
  gen_ed jsonb,
  degree_audit_system jsonb,
  grading jsonb not null default '{}'::jsonb,
  branding jsonb not null default '{}'::jsonb,
  support_resources jsonb not null default '[]'::jsonb,
  prompt_context text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists institutions_set_updated_at on public.institutions;
create trigger institutions_set_updated_at before update on public.institutions
for each row execute function public.set_updated_at();

-- Fixed id so code and the iOS app can reference VT as the transitional default.
insert into public.institutions (
  id,
  slug,
  name,
  short_name,
  email_domains,
  student_id_label,
  student_id_pattern,
  course_code_pattern,
  course_level_divisor,
  default_catalog_year,
  gen_ed,
  degree_audit_system,
  grading,
  branding,
  support_resources,
  prompt_context
)
values (
  '00000000-0000-4000-a000-000000000001',
  'vt',
  'Virginia Tech',
  'VT',
  array['vt.edu'],
  'PID',
  '^[^@\s]{2,}$',
  '([A-Z]{2,4})\s*(\d{4}[A-Z]?)',
  1000,
  '2025-2026',
  '{
    "name": "Pathways",
    "areas": [
      {"code": "1f", "name": "Foundational Discourse"},
      {"code": "1a", "name": "Advanced Discourse"},
      {"code": "2", "name": "Humanities"},
      {"code": "3", "name": "Social Sciences"},
      {"code": "4", "name": "Natural Sciences"},
      {"code": "5f", "name": "Foundational Quantitative"},
      {"code": "5a", "name": "Advanced Quantitative"},
      {"code": "6a", "name": "Arts"},
      {"code": "6d", "name": "Design"},
      {"code": "7", "name": "Identity and Equity", "suspended": true}
    ]
  }'::jsonb,
  '{"name": "DARS", "vendor": "uachieve"}'::jsonb,
  '{
    "grade_points": {
      "A": 4.0, "A-": 3.7, "B+": 3.3, "B": 3.0, "B-": 2.7, "C+": 2.3,
      "C": 2.0, "C-": 1.7, "D+": 1.3, "D": 1.0, "D-": 0.7, "F": 0.0,
      "W": 0.0, "WF": 0.0
    },
    "non_credit_grades": ["F", "W", "WF", "I", "NG"],
    "awarded_credit_grades": ["P", "PASS", "CR", "CREDIT", "T", "TR", "TRANSFER"]
  }'::jsonb,
  '{"primary_hex": "#861F41", "secondary_hex": "#E5751F", "community_name": "Hokie"}'::jsonb,
  '[
    {
      "name": "Virginia Tech Student Success Center",
      "type": "Tutoring",
      "description": "Start with tutoring or academic coaching for {courses}.",
      "link": "https://studentsuccess.vt.edu/"
    },
    {
      "name": "CS Office Hours and Course Staff",
      "type": "Course support",
      "description": "Use the current course Canvas page, TA office hours, and instructor office hours for assignment-specific help.",
      "link": null
    }
  ]'::jsonb,
  'C or better means C, C+, B-, B, B+, A-, A, or A+. C- does not satisfy C-or-better requirements. '
    || 'Treat transfer/awarded credit grades such as T, TR, TRANSFER, P, CR, or CREDIT as satisfying exact mapped VT course codes.'
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Degree audit specs (engine-readable requirements; filled by the sync script)
-- ---------------------------------------------------------------------------

create table if not exists public.degree_audit_specs (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  program_key text not null,
  catalog_year text not null,
  major text not null default '',
  degree text not null default '',
  spec jsonb not null,
  spec_version integer not null default 1,
  is_published boolean not null default false,
  source text not null default 'local_json',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (institution_id, program_key, catalog_year)
);

drop trigger if exists degree_audit_specs_set_updated_at on public.degree_audit_specs;
create trigger degree_audit_specs_set_updated_at before update on public.degree_audit_specs
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Scope catalog tables by institution
-- ---------------------------------------------------------------------------

do $$
declare
  vt_id constant uuid := '00000000-0000-4000-a000-000000000001';
  r record;
  current_pk text;
  pk_has_institution boolean;
begin
  for r in
    select *
    from (values
      ('catalog_subjects', 'institution_id, code'),
      ('catalog_courses', 'institution_id, subject, code'),
      ('coe_courses', 'institution_id, subject, code'),
      ('catalog_programs', 'institution_id, key'),
      ('catalog_requirements', 'institution_id, program_key'),
      ('pathways_courses', 'institution_id, code, concept')
    ) as v(tbl, pk_cols)
  loop
    execute format(
      'alter table public.%I add column if not exists institution_id uuid references public.institutions(id) on delete cascade',
      r.tbl
    );
    execute format('update public.%I set institution_id = $1 where institution_id is null', r.tbl) using vt_id;
    execute format('alter table public.%I alter column institution_id set not null', r.tbl);

    select c.conname,
           exists (
             select 1
             from pg_attribute a
             where a.attrelid = c.conrelid
               and a.attnum = any (c.conkey)
               and a.attname = 'institution_id'
           )
      into current_pk, pk_has_institution
    from pg_constraint c
    where c.conrelid = format('public.%I', r.tbl)::regclass
      and c.contype = 'p';

    if current_pk is null or not pk_has_institution then
      if current_pk is not null then
        execute format('alter table public.%I drop constraint %I', r.tbl, current_pk);
      end if;
      execute format('alter table public.%I add constraint %I primary key (%s)', r.tbl, r.tbl || '_pkey', r.pk_cols);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Profiles and user-owned audit rows
-- ---------------------------------------------------------------------------

do $$
declare
  vt_id constant uuid := '00000000-0000-4000-a000-000000000001';
begin
  -- Backfill only when the column is first added, so a re-run never reassigns
  -- users who later picked a different institution.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'institution_id'
  ) then
    alter table public.profiles
      add column institution_id uuid references public.institutions(id) on delete set null;
    update public.profiles set institution_id = vt_id;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'degree_audits' and column_name = 'institution_id'
  ) then
    alter table public.degree_audits
      add column institution_id uuid references public.institutions(id) on delete set null;
    update public.degree_audits set institution_id = vt_id;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'dars_audits' and column_name = 'institution_id'
  ) then
    alter table public.dars_audits
      add column institution_id uuid references public.institutions(id) on delete set null;
    update public.dars_audits set institution_id = vt_id;
  end if;
end $$;

alter table public.profiles add column if not exists student_id text;
alter table public.profiles add column if not exists school_email text;
alter table public.degree_audits add column if not exists program_key text;

update public.profiles
set student_id = vt_pid
where student_id is null and vt_pid is not null;

update public.profiles
set school_email = vt_email
where school_email is null and vt_email is not null;

create index if not exists idx_profiles_institution_id on public.profiles (institution_id);

-- Keep the legacy vt_* columns and the new generic columns in step while
-- shipped iOS builds still read and write only vt_pid / vt_email.
create or replace function public.sync_profile_legacy_columns()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.student_id = coalesce(new.student_id, new.vt_pid);
    new.vt_pid = coalesce(new.vt_pid, new.student_id);
    new.school_email = coalesce(new.school_email, new.vt_email);
    new.vt_email = coalesce(new.vt_email, new.school_email);
    return new;
  end if;

  if new.vt_pid is distinct from old.vt_pid and new.student_id is not distinct from old.student_id then
    new.student_id = new.vt_pid;
  elsif new.student_id is distinct from old.student_id and new.vt_pid is not distinct from old.vt_pid then
    new.vt_pid = new.student_id;
  end if;

  if new.vt_email is distinct from old.vt_email and new.school_email is not distinct from old.school_email then
    new.school_email = new.vt_email;
  elsif new.school_email is distinct from old.school_email and new.vt_email is not distinct from old.vt_email then
    new.vt_email = new.school_email;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_sync_legacy_columns on public.profiles;
create trigger profiles_sync_legacy_columns before insert or update on public.profiles
for each row execute function public.sync_profile_legacy_columns();

-- ---------------------------------------------------------------------------
-- New-user bootstrap (replaces the 002 version)
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  vt_id constant uuid := '00000000-0000-4000-a000-000000000001';
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_institution_id uuid;
  v_student_id text := coalesce(nullif(meta ->> 'student_id', ''), nullif(meta ->> 'vt_pid', ''));
  v_school_email text := coalesce(nullif(meta ->> 'school_email', ''), nullif(meta ->> 'vt_email', ''), new.email);
  v_major text := nullif(meta ->> 'major', '');
begin
  begin
    v_institution_id := nullif(meta ->> 'institution_id', '')::uuid;
  exception when invalid_text_representation then
    v_institution_id := null;
  end;

  if v_institution_id is not null and not exists (
    select 1 from public.institutions where id = v_institution_id and is_active
  ) then
    v_institution_id := null;
  end if;

  if v_institution_id is null and nullif(meta ->> 'institution_slug', '') is not null then
    select id into v_institution_id
    from public.institutions
    where slug = lower(meta ->> 'institution_slug') and is_active;
  end if;

  -- Transitional: shipped builds send no institution and are VT-only. Remove in 006.
  v_institution_id := coalesce(v_institution_id, vt_id);

  if v_major is null and v_institution_id = vt_id then
    v_major := 'Computer Science';
  end if;

  insert into public.profiles (
    id,
    institution_id,
    student_id,
    school_email,
    vt_pid,
    vt_email,
    full_name,
    major,
    graduation_year,
    appearance_mode
  )
  values (
    new.id,
    v_institution_id,
    v_student_id,
    v_school_email,
    v_student_id,
    v_school_email,
    nullif(meta ->> 'full_name', ''),
    v_major,
    nullif(meta ->> 'graduation_year', ''),
    coalesce(nullif(meta ->> 'appearance_mode', ''), 'system')
  )
  on conflict (id) do update set
    institution_id = excluded.institution_id,
    student_id = excluded.student_id,
    school_email = excluded.school_email,
    vt_pid = excluded.vt_pid,
    vt_email = excluded.vt_email,
    full_name = excluded.full_name,
    major = excluded.major,
    graduation_year = excluded.graduation_year,
    appearance_mode = excluded.appearance_mode;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.institutions enable row level security;
alter table public.degree_audit_specs enable row level security;

drop policy if exists "active institutions are readable" on public.institutions;
create policy "active institutions are readable" on public.institutions
for select using (is_active);

drop policy if exists "published audit specs are readable" on public.degree_audit_specs;
create policy "published audit specs are readable" on public.degree_audit_specs
for select using (
  is_published
  and exists (
    select 1 from public.institutions i
    where i.id = degree_audit_specs.institution_id and i.is_active
  )
);

drop policy if exists "catalog subjects are readable" on public.catalog_subjects;
create policy "catalog subjects are readable" on public.catalog_subjects
for select using (
  exists (select 1 from public.institutions i where i.id = catalog_subjects.institution_id and i.is_active)
);

drop policy if exists "catalog courses are readable" on public.catalog_courses;
create policy "catalog courses are readable" on public.catalog_courses
for select using (
  exists (select 1 from public.institutions i where i.id = catalog_courses.institution_id and i.is_active)
);

drop policy if exists "coe courses are readable" on public.coe_courses;
create policy "coe courses are readable" on public.coe_courses
for select using (
  exists (select 1 from public.institutions i where i.id = coe_courses.institution_id and i.is_active)
);

drop policy if exists "catalog programs are readable" on public.catalog_programs;
create policy "catalog programs are readable" on public.catalog_programs
for select using (
  exists (select 1 from public.institutions i where i.id = catalog_programs.institution_id and i.is_active)
);

drop policy if exists "catalog requirements are readable" on public.catalog_requirements;
create policy "catalog requirements are readable" on public.catalog_requirements
for select using (
  exists (select 1 from public.institutions i where i.id = catalog_requirements.institution_id and i.is_active)
);

drop policy if exists "pathways courses are readable" on public.pathways_courses;
create policy "pathways courses are readable" on public.pathways_courses
for select using (
  exists (select 1 from public.institutions i where i.id = pathways_courses.institution_id and i.is_active)
);

drop policy if exists "profiles are user owned" on public.profiles;
create policy "profiles are user owned" on public.profiles
for all
using (auth.uid() = id)
with check (
  auth.uid() = id
  and (
    institution_id is null
    or exists (select 1 from public.institutions i where i.id = profiles.institution_id and i.is_active)
  )
);

-- ---------------------------------------------------------------------------
-- API grants (same pattern as 003)
-- ---------------------------------------------------------------------------

grant select on public.institutions, public.degree_audit_specs to anon, authenticated;
grant select, insert, update, delete on public.institutions, public.degree_audit_specs to service_role;
