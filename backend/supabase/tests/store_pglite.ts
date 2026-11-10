// TEST/QA-ONLY store: runs the courses handler's queries against the local
// PGlite database *as the signed-in student* (role `authenticated`, RLS on),
// so tests and the local QA server exercise the real migration policies.
// Trusted writes run as `service_role`, mirroring production.

import type { PGlite } from "npm:@electric-sql/pglite@0.2.17";
import type {
  CourseRow,
  CoursesStore,
  DeadlineRow,
  DocumentRow,
  FactRow,
  GuideTopicRow,
  Institution,
  NewCourse,
  NewDocument,
  NewFact,
  SourceRow,
  TermRow,
  TrustedWriter,
} from "../functions/courses/types.ts";
import { asUser, type Tx } from "./harness.ts";

const COURSE_COLUMNS = `id, term_id, subject, number, title, section_code, instructor_name, origin,
  syllabus_remind_on::text, created_at::text`;
const DOCUMENT_COLUMNS = `id, course_id, version, storage_path, file_name, mime_type, size_bytes, sha256,
  page_count, text_method, processing_state, error_code, findings, stated_identity, extraction_model,
  extracted_at::text, reviewed_at::text, uploaded_at::text`;
const FACT_COLUMNS = `id, document_id, category, label, value, excerpt, page, qualifiers, evidence, issues,
  review_state, reviewed_at::text, sort_order`;

/** File bytes for local QA; object metadata lives in storage.objects (RLS applies). */
export const fileBytes = new Map<string, Uint8Array>();

export class PgliteStore implements CoursesStore {
  readonly trusted: TrustedWriter;

  constructor(protected db: PGlite, protected userId: string) {
    this.trusted = new ServiceRoleWriter(db);
  }

  protected run<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return asUser(this.db, this.userId, fn);
  }

  protected async rows<T>(sql: string, params: unknown[] = []): Promise<T[]> {
    return await this.run(async (tx) => (await tx.query<T>(sql, params)).rows);
  }

  async institutionForUser(): Promise<Institution | null> {
    const rows = await this.rows<Institution>(
      `select i.id, i.slug, i.name from public.profiles p
         join public.institutions i on i.id = p.institution_id
        where p.id = auth.uid() and i.is_active`,
    );
    return rows[0] ?? null;
  }

  listTerms(institutionId: string): Promise<TermRow[]> {
    return this.rows(
      `select id, term_key, name, classes_begin::text, classes_end::text, finals_end::text, timezone, source_id
         from public.academic_terms where institution_id = $1 order by classes_begin`,
      [institutionId],
    );
  }

  listDeadlines(termId: string): Promise<DeadlineRow[]> {
    return this.rows(
      `select id, term_id, kind, audience, label, starts_on::text, ends_on::text, time_note, detail, is_tentative, source_id
         from public.term_deadlines where term_id = $1 order by starts_on`,
      [termId],
    );
  }

  listGuideTopics(institutionId: string): Promise<GuideTopicRow[]> {
    return this.rows(
      `select topic, sort_order, title, points, comparison, links
         from public.registration_guide_topics where institution_id = $1 order by sort_order`,
      [institutionId],
    );
  }

  listSources(institutionId: string): Promise<SourceRow[]> {
    return this.rows(
      `select id, kind, title, publisher, url, checked_on::text
         from public.official_sources where institution_id = $1`,
      [institutionId],
    );
  }

  // ----- Stage 2 -----

  listCourses(termId: string): Promise<CourseRow[]> {
    return this.rows(`select ${COURSE_COLUMNS} from public.enrolled_courses where term_id = $1`, [termId]);
  }

  async getCourse(id: string): Promise<CourseRow | null> {
    const rows = await this.rows<CourseRow>(`select ${COURSE_COLUMNS} from public.enrolled_courses where id = $1`, [id]);
    return rows[0] ?? null;
  }

  async insertCourse(row: NewCourse): Promise<CourseRow> {
    const rows = await this.rows<CourseRow>(
      `insert into public.enrolled_courses
         (user_id, institution_id, term_id, subject, number, title, section_code, instructor_name, origin)
       values (auth.uid(), $1, $2, $3, $4, $5, $6, $7, $8)
       returning ${COURSE_COLUMNS}`,
      [row.institution_id, row.term_id, row.subject, row.number, row.title, row.section_code, row.instructor_name, row.origin],
    );
    return rows[0];
  }

  async setSyllabusReminder(courseId: string, remindOn: string | null): Promise<void> {
    await this.rows(`update public.enrolled_courses set syllabus_remind_on = $2 where id = $1`, [courseId, remindOn]);
  }

  async deleteCourse(id: string): Promise<void> {
    await this.rows(`delete from public.enrolled_courses where id = $1`, [id]);
  }

  listDocuments(courseIds: string[]): Promise<DocumentRow[]> {
    if (!courseIds.length) return Promise.resolve([]);
    return this.rows(
      `select ${DOCUMENT_COLUMNS} from public.syllabus_documents where course_id = any($1::uuid[])`,
      [courseIds],
    );
  }

  async getDocument(id: string): Promise<DocumentRow | null> {
    const rows = await this.rows<DocumentRow>(`select ${DOCUMENT_COLUMNS} from public.syllabus_documents where id = $1`, [id]);
    return rows[0] ?? null;
  }

  async deleteDocument(id: string): Promise<void> {
    await this.rows(`delete from public.syllabus_documents where id = $1`, [id]);
  }

  listFacts(documentId: string): Promise<FactRow[]> {
    return this.rows(
      `select ${FACT_COLUMNS} from public.syllabus_facts where document_id = $1 order by sort_order`,
      [documentId],
    );
  }

  // Storage: object rows are written as the student, so bucket policies apply.
  async putFile(path: string, bytes: Uint8Array, mimeType: string): Promise<void> {
    await this.rows(
      `insert into storage.objects (bucket_id, name, owner, metadata) values ('syllabi', $1, auth.uid(), $2::jsonb)`,
      [path, JSON.stringify({ mimetype: mimeType, size: bytes.length })],
    );
    fileBytes.set(path, bytes);
  }

  async getFile(path: string): Promise<Uint8Array> {
    const rows = await this.rows(`select 1 from storage.objects where bucket_id = 'syllabi' and name = $1`, [path]);
    const bytes = fileBytes.get(path);
    if (!rows.length || !bytes) throw new Error("Storage download failed: 404");
    return bytes;
  }

  async removeFiles(paths: string[]): Promise<void> {
    if (!paths.length) return;
    const removed = await this.rows<{ name: string }>(
      `delete from storage.objects where bucket_id = 'syllabi' and name = any($1::text[]) returning name`,
      [paths],
    );
    for (const row of removed) fileBytes.delete(row.name);
  }
}

/** Writes as `service_role` (bypasses RLS), mirroring production. */
class ServiceRoleWriter implements TrustedWriter {
  constructor(private db: PGlite) {}

  private async exec(sql: string, params: unknown[]): Promise<void> {
    await this.db.transaction(async (tx) => {
      await tx.exec("set local role service_role");
      await tx.query(sql, params);
    });
  }

  insertDocument(row: NewDocument): Promise<void> {
    return this.exec(
      `insert into public.syllabus_documents (id, user_id, course_id, version, storage_path, file_name, mime_type,
         size_bytes, sha256, page_count, text_method, processing_state)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
      [row.id, row.user_id, row.course_id, row.version, row.storage_path, row.file_name, row.mime_type,
        row.size_bytes, row.sha256, row.page_count, row.text_method, row.processing_state],
    );
  }

  async updateDocument(id: string, patch: Partial<DocumentRow>): Promise<void> {
    const entries = Object.entries(patch);
    if (!entries.length) return;
    const jsonColumns = new Set(["findings", "stated_identity"]);
    const sets = entries.map(([key], i) => `${key} = $${i + 2}${jsonColumns.has(key) ? "::jsonb" : ""}`);
    const values = entries.map(([key, value]) => (jsonColumns.has(key) ? JSON.stringify(value) : value));
    await this.exec(`update public.syllabus_documents set ${sets.join(", ")} where id = $1`, [id, ...values]);
  }

  async insertFacts(rows: NewFact[]): Promise<void> {
    for (const r of rows) {
      await this.exec(
        `insert into public.syllabus_facts (user_id, document_id, category, label, value, excerpt, page, qualifiers,
           evidence, issues, sort_order)
         values ($1, $2, $3, $4, $5::jsonb, $6, $7, $8::text[], $9, $10::text[], $11)`,
        [r.user_id, r.document_id, r.category, r.label, JSON.stringify(r.value), r.excerpt, r.page, r.qualifiers,
          r.evidence, r.issues, r.sort_order],
      );
    }
  }
}
