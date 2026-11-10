-- Course companion, stage 1: official sources, academic terms, registration
-- deadlines, and the registration guide.
-- Apply after 005_multi_institution.sql (needs public.institutions) and 006.
--
-- LOCAL ONLY until approved. Do not apply to hosted Supabase outside an
-- approved deployment window.
--
-- Reference data here is institution-scoped and read-only for clients:
-- signed-in students can read published rows for active institutions; only
-- the service role writes. Every deadline and guide statement points at an
-- official source with the date it was checked. Seed values were copied from
-- the Virginia Tech registrar pages on 2026-11-09; labels are verbatim.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.official_sources (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  kind text not null check (kind in (
    'academic_calendar', 'enrollment_dates', 'registration_policy', 'withdrawal_policy', 'refund_policy', 'other'
  )),
  title text not null,
  publisher text not null,
  url text not null,
  checked_on date not null,
  status text not null default 'staged' check (status in ('staged', 'published', 'retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, url)
);

create table if not exists public.academic_terms (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  -- Agora's stable key (e.g. 'spring-2027'). The institution's own term code
  -- is stored only when verified from an official source.
  term_key text not null,
  institution_term_code text,
  name text not null,
  classes_begin date not null,
  classes_end date not null,
  finals_end date,
  timezone text not null,
  source_id uuid not null references public.official_sources(id),
  status text not null default 'staged' check (status in ('staged', 'published', 'retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, term_key),
  unique (id, institution_id),
  check (classes_end >= classes_begin)
);

create table if not exists public.term_deadlines (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  term_id uuid not null,
  kind text not null check (kind in (
    'course_request', 'add_drop_begins', 'add_drop_closes', 'add_drop_reopens',
    'last_day_add', 'last_day_drop', 'withdraw_without_charges', 'grade_option_change',
    'resignation', 'w_grade_policy', 'classes_begin', 'classes_end', 'final_exams'
  )),
  audience text not null default 'all' check (audience in (
    'all', 'continuing', 'incoming', 'graduate'
  )),
  label text not null,               -- verbatim from the source
  starts_on date not null,
  ends_on date,                      -- for windows such as Course Request
  time_note text,                    -- verbatim time qualifier, if the source gives one
  detail text,                       -- verbatim supporting sentence, if any
  is_tentative boolean not null default false,
  source_id uuid not null references public.official_sources(id),
  status text not null default 'staged' check (status in ('staged', 'published', 'retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (term_id, institution_id) references public.academic_terms (id, institution_id) on delete cascade,
  unique (term_id, kind, audience),
  check (ends_on is null or ends_on >= starts_on)
);

create table if not exists public.registration_guide_topics (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  topic text not null check (topic in (
    'course_request', 'add_drop', 'drop', 'course_withdrawal', 'leaving_term', 'drop_vs_withdraw'
  )),
  sort_order integer not null default 0,
  title text not null,
  -- [{ "text": "...", "source_id": "<uuid>" }]: one cited statement per entry.
  points jsonb not null default '[]'::jsonb,
  -- drop_vs_withdraw only: [{ "aspect", "drop", "withdraw", "source_id" }]
  comparison jsonb,
  -- [{ "title": "...", "url": "..." }]: official pages for the student to act on.
  links jsonb not null default '[]'::jsonb,
  status text not null default 'staged' check (status in ('staged', 'published', 'retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, topic)
);

create index if not exists idx_term_deadlines_term on public.term_deadlines (term_id, starts_on);
create index if not exists idx_academic_terms_institution on public.academic_terms (institution_id, classes_begin);

do $$
declare t text;
begin
  foreach t in array array['official_sources', 'academic_terms', 'term_deadlines', 'registration_guide_topics'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_set_updated_at', t);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Row-level security: published rows of active institutions, signed-in only
-- ---------------------------------------------------------------------------

alter table public.official_sources enable row level security;
alter table public.academic_terms enable row level security;
alter table public.term_deadlines enable row level security;
alter table public.registration_guide_topics enable row level security;

drop policy if exists "published sources are readable" on public.official_sources;
create policy "published sources are readable" on public.official_sources
for select to authenticated using (
  status = 'published'
  and exists (select 1 from public.institutions i where i.id = official_sources.institution_id and i.is_active)
);

drop policy if exists "published terms are readable" on public.academic_terms;
create policy "published terms are readable" on public.academic_terms
for select to authenticated using (
  status = 'published'
  and exists (select 1 from public.institutions i where i.id = academic_terms.institution_id and i.is_active)
);

drop policy if exists "published deadlines are readable" on public.term_deadlines;
create policy "published deadlines are readable" on public.term_deadlines
for select to authenticated using (
  status = 'published'
  and exists (select 1 from public.institutions i where i.id = term_deadlines.institution_id and i.is_active)
);

drop policy if exists "published guide topics are readable" on public.registration_guide_topics;
create policy "published guide topics are readable" on public.registration_guide_topics
for select to authenticated using (
  status = 'published'
  and exists (select 1 from public.institutions i where i.id = registration_guide_topics.institution_id and i.is_active)
);

grant select on public.official_sources, public.academic_terms, public.term_deadlines,
  public.registration_guide_topics to authenticated;
grant select, insert, update, delete on public.official_sources, public.academic_terms,
  public.term_deadlines, public.registration_guide_topics to service_role;

-- ---------------------------------------------------------------------------
-- Virginia Tech seed (checked 2026-11-09)
-- ---------------------------------------------------------------------------

do $$
declare
  vt constant uuid := '00000000-0000-4000-a000-000000000001';
  s_dates constant uuid := '00000000-0000-4000-b000-000000000101';
  s_cal constant uuid := '00000000-0000-4000-b000-000000000102';
  s_enroll constant uuid := '00000000-0000-4000-b000-000000000103';
  s_wpolicy constant uuid := '00000000-0000-4000-b000-000000000104';
  s_refund constant uuid := '00000000-0000-4000-b000-000000000105';
  t_fall constant uuid := '00000000-0000-4000-b000-000000000201';
  t_spring constant uuid := '00000000-0000-4000-b000-000000000202';
  time_note constant text := 'Course Request and Add/Drop times begin at 7:00 a.m. Deadlines are 11:59 p.m. unless otherwise noted.';
begin
  insert into public.official_sources (id, institution_id, kind, title, publisher, url, checked_on, status) values
    (s_dates, vt, 'enrollment_dates', 'Enrollment Dates', 'Virginia Tech Office of the University Registrar',
      'https://registrar.vt.edu/dates-deadlines/Enrollment-Dates.html', '2026-11-09', 'published'),
    (s_cal, vt, 'academic_calendar', 'Academic Calendar: 2026-2027', 'Virginia Tech Office of the University Registrar',
      'https://registrar.vt.edu/dates-deadlines/academic-calendar/2026-2027.html', '2026-11-09', 'published'),
    (s_enroll, vt, 'registration_policy', 'Enrollment', 'Virginia Tech Office of the University Registrar',
      'https://registrar.vt.edu/Enrollment.html', '2026-11-09', 'published'),
    (s_wpolicy, vt, 'withdrawal_policy', 'How Do I... Withdraw from a Course? (W Policy)',
      'Virginia Tech University Studies (applies to University Studies majors)',
      'https://universitystudies.vt.edu/how-to/hdi-withdraw-course.html', '2026-11-09', 'published'),
    (s_refund, vt, 'refund_policy', 'Refund Policy', 'Virginia Tech Office of the University Bursar',
      'https://www.bursar.vt.edu/refunds1/refunds/refundpolicy.html', '2026-11-09', 'published')
  on conflict (id) do nothing;

  insert into public.academic_terms (id, institution_id, term_key, name, classes_begin, classes_end, finals_end, timezone, source_id, status) values
    (t_fall, vt, 'fall-2026', 'Fall 2026', '2026-08-24', '2026-12-09', '2026-12-16', 'America/New_York', s_cal, 'published'),
    (t_spring, vt, 'spring-2027', 'Spring 2027', '2027-01-19', '2027-05-05', '2027-05-12', 'America/New_York', s_cal, 'published')
  on conflict (id) do nothing;

  insert into public.term_deadlines
    (institution_id, term_id, kind, audience, label, starts_on, ends_on, time_note, detail, source_id, status)
  values
    -- Fall 2026: Enrollment Dates
    (vt, t_fall, 'course_request', 'continuing', 'Course Request', '2026-03-19', '2026-04-07', time_note, null, s_dates, 'published'),
    (vt, t_fall, 'course_request', 'graduate', 'Course Request', '2026-03-24', '2026-04-07', time_note, null, s_dates, 'published'),
    (vt, t_fall, 'add_drop_begins', 'continuing', 'Add/Drop Begins', '2026-04-24', null, time_note, null, s_dates, 'published'),
    (vt, t_fall, 'add_drop_begins', 'incoming', 'Add/Drop Begins', '2026-06-10', null, time_note, null, s_dates, 'published'),
    (vt, t_fall, 'add_drop_begins', 'graduate', 'Add/Drop Begins', '2026-04-24', null, time_note, null, s_dates, 'published'),
    (vt, t_fall, 'add_drop_closes', 'continuing', 'Add/Drop Closes', '2026-05-29', null, time_note, null, s_dates, 'published'),
    (vt, t_fall, 'add_drop_reopens', 'continuing', 'Add/Drop Reopens', '2026-08-03', null, time_note, null, s_dates, 'published'),
    (vt, t_fall, 'last_day_add', 'all', 'Last Day to Add Courses', '2026-08-28', null, time_note, null, s_dates, 'published'),
    (vt, t_fall, 'last_day_drop', 'all', 'Last Day to Drop Courses', '2026-10-06', null, time_note, null, s_dates, 'published'),
    (vt, t_fall, 'resignation', 'all', 'Resignation Deadline', '2026-10-26', null, time_note, null, s_dates, 'published'),
    -- Fall 2026: Academic Calendar
    (vt, t_fall, 'classes_begin', 'all', 'Classes Begin', '2026-08-24', null, null, null, s_cal, 'published'),
    (vt, t_fall, 'withdraw_without_charges', 'all',
      'Last day to withdraw to avoid tuition and fee charges. Students must complete a withdrawal form.',
      '2026-08-24', null, null, 'Note: You may not drop your final hours via the web.', s_cal, 'published'),
    (vt, t_fall, 'grade_option_change', 'all', 'Last day to change grade option from A-F to P/F by 5:00 p.m.',
      '2026-10-06', null, null, null, s_cal, 'published'),
    (vt, t_fall, 'w_grade_policy', 'all', 'Last day to apply for W grade policy', '2026-12-09', null, null, null, s_cal, 'published'),
    (vt, t_fall, 'classes_end', 'all', 'Classes End', '2026-12-09', null, null, null, s_cal, 'published'),
    (vt, t_fall, 'final_exams', 'all', 'Fall Semester final examinations', '2026-12-11', '2026-12-16', null,
      '(Inclement weather makeup is December 17)', s_cal, 'published'),
    -- Spring 2027: Enrollment Dates
    (vt, t_spring, 'course_request', 'all', 'Course Request', '2026-10-20', '2026-11-03', time_note, null, s_dates, 'published'),
    (vt, t_spring, 'add_drop_begins', 'all', 'Add/Drop Begins', '2026-12-07', null, time_note, null, s_dates, 'published'),
    (vt, t_spring, 'last_day_add', 'all', 'Last Day to Add Courses', '2027-01-25', null, time_note, null, s_dates, 'published'),
    (vt, t_spring, 'last_day_drop', 'all', 'Last Day to Drop Courses', '2027-03-01', null, time_note, null, s_dates, 'published'),
    (vt, t_spring, 'resignation', 'all', 'Resignation Deadline', '2027-03-30', null, time_note, null, s_dates, 'published'),
    -- Spring 2027: Academic Calendar
    (vt, t_spring, 'classes_begin', 'all', 'Classes Begin', '2027-01-19', null, null, null, s_cal, 'published'),
    (vt, t_spring, 'withdraw_without_charges', 'all',
      'Last day for students to withdraw from Spring Semester to avoid tuition and fee charges.',
      '2027-01-19', null, null, 'Note: You may not drop your final hours via the web.', s_cal, 'published'),
    (vt, t_spring, 'grade_option_change', 'all', 'Last day to change grade option from A-F to P/F by 5:00 p.m.',
      '2027-03-01', null, null, null, s_cal, 'published'),
    (vt, t_spring, 'w_grade_policy', 'all', 'Last day to apply for W grade policy', '2027-05-05', null, null, null, s_cal, 'published'),
    (vt, t_spring, 'classes_end', 'all', 'Classes End', '2027-05-05', null, null, null, s_cal, 'published'),
    (vt, t_spring, 'final_exams', 'all', 'Spring Semester final examinations', '2027-05-07', '2027-05-12', null, null, s_cal, 'published')
  on conflict (term_id, kind, audience) do nothing;

  insert into public.registration_guide_topics (institution_id, topic, sort_order, title, points, comparison, links, status) values
    (vt, 'course_request', 10, 'Course Request', jsonb_build_array(
      jsonb_build_object('text', 'Course Request is the first step in registration: you select the classes you''d like to take for the upcoming term.', 'source_id', s_enroll),
      jsonb_build_object('text', 'It isn''t first-come, first-served. You can update your cart until the Course Request deadline.', 'source_id', s_enroll),
      jsonb_build_object('text', 'Course Request and Add/Drop are done in HokieSPA, which you log in to with your PID and password.', 'source_id', s_enroll)
    ), null, jsonb_build_array(
      jsonb_build_object('title', 'Registration tutorials', 'url', 'https://www.undergraduate.provost.vt.edu/aai/advising-technology/advising-technology-for-students/hokiespa-for-students/course-registration.html')
    ), 'published'),
    (vt, 'add_drop', 20, 'Add/Drop', jsonb_build_array(
      jsonb_build_object('text', 'Add/Drop is the period when you can adjust your schedule by adding new courses or dropping ones you no longer want. It is first-come, first-served.', 'source_id', s_enroll),
      jsonb_build_object('text', 'Add/Drop times begin at 7:00 a.m., and deadlines are 11:59 p.m. unless otherwise noted.', 'source_id', s_dates),
      jsonb_build_object('text', 'The deadline to add or drop a course you are auditing is the deadline to add courses.', 'source_id', s_dates)
    ), null, '[]'::jsonb, 'published'),
    (vt, 'drop', 30, 'Dropping a course', jsonb_build_array(
      jsonb_build_object('text', 'A dropped course does not appear on your academic transcript.', 'source_id', s_enroll),
      jsonb_build_object('text', 'You can drop a single course in HokieSPA until the drop deadline.', 'source_id', s_enroll),
      jsonb_build_object('text', 'You can''t drop your last course online. All students must complete the Withdrawal/Resignation form to drop their last course.', 'source_id', s_enroll)
    ), null, '[]'::jsonb, 'published'),
    (vt, 'course_withdrawal', 40, 'Withdrawing from a course (W grade)', jsonb_build_array(
      jsonb_build_object('text', 'A course withdrawal is for leaving a single course after the last day to drop. The course stays on your transcript with a grade of W (WG for graduate students).', 'source_id', s_enroll),
      jsonb_build_object('text', 'Undergraduate students are allowed up to 3 W grades during their time at Virginia Tech.', 'source_id', s_enroll),
      jsonb_build_object('text', 'The process depends on your college. Consult your academic dean''s office before requesting a W.', 'source_id', s_enroll),
      jsonb_build_object('text', 'University Studies majors follow the University Studies W policy and form.', 'source_id', s_wpolicy)
    ), null, '[]'::jsonb, 'published'),
    (vt, 'leaving_term', 50, 'Leaving the term: withdrawal or resignation', jsonb_build_array(
      jsonb_build_object('text', 'Withdrawal cancels all of your enrollment for a term, up to and including the first day of classes. No notation appears on your transcript.', 'source_id', s_enroll),
      jsonb_build_object('text', 'Resignation cancels all of your enrollment after the first day of classes. "Student Resigned" appears on your transcript, but no courses for that term appear.', 'source_id', s_enroll),
      jsonb_build_object('text', 'To withdraw or resign from a current or future semester, complete the Withdrawal/Resignation Form.', 'source_id', s_enroll),
      jsonb_build_object('text', 'Withdrawals submitted through the first day of classes receive a full refund. Later changes follow the Bursar''s refund schedule.', 'source_id', s_enroll),
      jsonb_build_object('text', 'For undergraduates, the first and required contact for resignation is the academic dean of your college.', 'source_id', s_cal)
    ), null, jsonb_build_array(
      jsonb_build_object('title', 'Bursar refund schedule', 'url', 'https://www.bursar.vt.edu/refunds1/refunds/refundpolicy.html')
    ), 'published'),
    (vt, 'drop_vs_withdraw', 5, 'Dropping vs. withdrawing', '[]'::jsonb, jsonb_build_array(
      jsonb_build_object('aspect', 'Transcript', 'drop', 'Not shown', 'withdraw', 'Shows a W', 'source_id', s_enroll),
      jsonb_build_object('aspect', 'When', 'drop', 'Until the drop deadline', 'withdraw', 'After the drop deadline', 'source_id', s_enroll),
      jsonb_build_object('aspect', 'How', 'drop', 'In HokieSPA (except your last course)', 'withdraw', 'Through your academic dean''s office', 'source_id', s_enroll),
      jsonb_build_object('aspect', 'Limit', 'drop', 'None stated', 'withdraw', 'Up to 3 W grades (undergraduates)', 'source_id', s_enroll)
    ), '[]'::jsonb, 'published')
  on conflict (institution_id, topic) do nothing;
end $$;
