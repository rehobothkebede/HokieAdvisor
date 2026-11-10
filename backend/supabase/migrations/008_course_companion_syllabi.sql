-- Course companion, stage 2: enrolled courses, private syllabus uploads, and
-- facts extracted from them.
-- Apply after 007_course_companion_registration.sql.
--
-- LOCAL ONLY until approved. Do not apply to hosted Supabase outside an
-- approved deployment window.
--
-- Privacy model:
-- - Everything here is private to its owner. There is no sharing in this
--   stage; nothing is readable by other students.
-- - Students read their own rows and may delete their own courses and
--   uploads (deletion cascades to extracted facts).
-- - Documents and extracted facts are written only by the `courses` edge
--   function with the service role, after it has verified ownership with the
--   student's own token. Students therefore cannot create rows that look
--   document-extracted; their corrections live in a separate table (009).
-- - Files live in the private `syllabi` bucket under `{user_id}/...`.

-- ---------------------------------------------------------------------------
-- Enrolled courses (one row per course section per term, per student)
-- ---------------------------------------------------------------------------

create table if not exists public.enrolled_courses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  institution_id uuid not null,
  term_id uuid not null,
  subject text not null check (subject ~ '^[A-Z]{2,5}$'),
  number text not null check (number ~ '^[0-9]{3,4}[A-Z]?$'),
  title text not null default '' check (char_length(title) <= 200),
  -- The institution's section identifier (Virginia Tech: CRN). Never used on
  -- its own: a section is identified by institution + term + section_code.
  section_code text not null check (section_code ~ '^[A-Za-z0-9-]{1,20}$'),
  instructor_name text not null check (char_length(btrim(instructor_name)) between 1 and 120),
  origin text not null default 'manual' check (origin in ('manual', 'transcript')),
  -- "Syllabus not available yet": remind the student on this date.
  syllabus_remind_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (term_id, institution_id) references public.academic_terms (id, institution_id),
  unique (user_id, term_id, subject, number, section_code),
  unique (id, user_id)
);

create index if not exists idx_enrolled_courses_user_term on public.enrolled_courses (user_id, term_id);

-- Section identity is fixed once created, so extracted dates stay tied to the
-- exact section and term. Students delete and re-add to change it.
create or replace function public.enrolled_courses_lock_identity()
returns trigger
language plpgsql
as $$
begin
  if new.user_id is distinct from old.user_id
     or new.institution_id is distinct from old.institution_id
     or new.term_id is distinct from old.term_id
     or new.subject is distinct from old.subject
     or new.number is distinct from old.number
     or new.section_code is distinct from old.section_code
     or new.instructor_name is distinct from old.instructor_name then
    raise exception 'A course''s term, section, and instructor can''t be changed. Remove the course and add it again.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists enrolled_courses_lock_identity on public.enrolled_courses;
create trigger enrolled_courses_lock_identity before update on public.enrolled_courses
for each row execute function public.enrolled_courses_lock_identity();

drop trigger if exists enrolled_courses_set_updated_at on public.enrolled_courses;
create trigger enrolled_courses_set_updated_at before update on public.enrolled_courses
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Syllabus documents (each upload is a new version)
-- ---------------------------------------------------------------------------

create table if not exists public.syllabus_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  course_id uuid not null,
  version integer not null check (version >= 1),
  storage_bucket text not null default 'syllabi' check (storage_bucket = 'syllabi'),
  storage_path text not null unique,
  file_name text not null check (char_length(file_name) <= 255),
  mime_type text not null check (mime_type in ('application/pdf', 'image/png', 'image/jpeg')),
  size_bytes integer not null check (size_bytes > 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  page_count integer not null check (page_count between 1 and 60),
  text_method text not null check (text_method in ('pdf_text', 'ocr', 'mixed')),
  processing_state text not null default 'processing'
    check (processing_state in ('processing', 'review_needed', 'reviewed', 'failed')),
  error_code text,
  -- Document-level findings: term/section/instructor mismatches, weights not
  -- totaling 100%, text addressed to AI tools, OCR-only, categories not found.
  findings jsonb not null default '[]'::jsonb,
  -- What the syllabus itself states about its term, course, section, and
  -- instructor, each with page and excerpt.
  stated_identity jsonb not null default '{}'::jsonb,
  extraction_model text,
  extracted_at timestamptz,
  reviewed_at timestamptz,
  uploaded_at timestamptz not null default now(),
  foreign key (course_id, user_id) references public.enrolled_courses (id, user_id) on delete cascade,
  unique (course_id, version),
  unique (course_id, sha256),
  unique (id, user_id)
);

create index if not exists idx_syllabus_documents_course on public.syllabus_documents (course_id, version desc);

-- ---------------------------------------------------------------------------
-- Extracted facts (document-sourced; never edited by students)
-- ---------------------------------------------------------------------------

create table if not exists public.syllabus_facts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid not null,
  category text not null check (category in (
    'exam', 'assignment_deadline', 'office_hours', 'contact', 'attendance', 'participation',
    'grading_weight', 'late_work', 'makeup', 'materials', 'requirement', 'restriction'
  )),
  label text not null check (char_length(label) between 1 and 200),
  -- Typed details: summary, date_text, date, date_basis, times, timezone,
  -- relative timing, recurrence, exam format, weight, location, appointment,
  -- contact, restrictions. Only values stated in the document.
  value jsonb not null default '{}'::jsonb,
  excerpt text not null check (char_length(excerpt) between 1 and 1200),
  page integer not null check (page >= 1),
  qualifiers text[] not null default '{}',
  -- verified: excerpt found on the cited page; other_page: found on a different
  -- page; approximate: same words, but the PDF's text order differs (flagged);
  -- not_found: the excerpt isn't in the document (flagged).
  evidence text not null check (evidence in ('verified', 'other_page', 'approximate', 'not_found')),
  issues text[] not null default '{}',
  review_state text not null default 'pending' check (review_state in ('pending', 'confirmed', 'rejected')),
  reviewed_at timestamptz,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  foreign key (document_id, user_id) references public.syllabus_documents (id, user_id) on delete cascade,
  unique (id, user_id)
);

create index if not exists idx_syllabus_facts_document on public.syllabus_facts (document_id, sort_order);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.enrolled_courses enable row level security;
alter table public.syllabus_documents enable row level security;
alter table public.syllabus_facts enable row level security;

-- Courses: owner reads and manages; must belong to the student's own active
-- institution and a published term of it.
drop policy if exists "enrolled courses are user owned" on public.enrolled_courses;
create policy "enrolled courses are user owned" on public.enrolled_courses
for all to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and institution_id = (select p.institution_id from public.profiles p where p.id = auth.uid())
  and exists (
    select 1 from public.academic_terms t
    where t.id = enrolled_courses.term_id and t.institution_id = enrolled_courses.institution_id
      and t.status = 'published'
  )
);

drop policy if exists "syllabus documents are readable by owner" on public.syllabus_documents;
create policy "syllabus documents are readable by owner" on public.syllabus_documents
for select to authenticated using (auth.uid() = user_id);

drop policy if exists "syllabus documents are deletable by owner" on public.syllabus_documents;
create policy "syllabus documents are deletable by owner" on public.syllabus_documents
for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "syllabus facts are readable by owner" on public.syllabus_facts;
create policy "syllabus facts are readable by owner" on public.syllabus_facts
for select to authenticated using (auth.uid() = user_id);

grant select, insert, update, delete on public.enrolled_courses to authenticated;
grant select, delete on public.syllabus_documents to authenticated;
grant select on public.syllabus_facts to authenticated;
grant select, insert, update, delete on public.enrolled_courses, public.syllabus_documents,
  public.syllabus_facts to service_role;

-- ---------------------------------------------------------------------------
-- Private storage bucket
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('syllabi', 'syllabi', false, 10485760, array['application/pdf', 'image/png', 'image/jpeg'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Owner-only, by top-level folder. No update policy: a new version is a new
-- object, so stored originals are never overwritten.
drop policy if exists "syllabus files are readable by owner" on storage.objects;
create policy "syllabus files are readable by owner" on storage.objects
for select to authenticated using (
  bucket_id = 'syllabi' and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "syllabus files are uploadable by owner" on storage.objects;
create policy "syllabus files are uploadable by owner" on storage.objects
for insert to authenticated with check (
  bucket_id = 'syllabi' and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "syllabus files are deletable by owner" on storage.objects;
create policy "syllabus files are deletable by owner" on storage.objects
for delete to authenticated using (
  bucket_id = 'syllabi' and auth.uid()::text = (storage.foldername(name))[1]
);
