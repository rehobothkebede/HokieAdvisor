// Production store: Supabase REST (PostgREST) and Storage called with the
// student's own access token, so row-level security and bucket policies
// decide what each request can see or change. The service role is used only
// by ServiceRoleWriter, to record extraction results after the handler has
// confirmed (with the student's token) that the course and document are theirs.

import type {
  CorrectionRow,
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
  NewReminder,
  ReminderRow,
  SourceRow,
  TermRow,
  TrustedWriter,
} from "./types.ts";

const BUCKET = "syllabi";
const COURSE_COLUMNS = "id,term_id,subject,number,title,section_code,instructor_name,origin,syllabus_remind_on,created_at";
const DOCUMENT_COLUMNS =
  "id,course_id,version,storage_path,file_name,mime_type,size_bytes,sha256,page_count,text_method," +
  "processing_state,error_code,findings,stated_identity,extraction_model,extracted_at,reviewed_at,uploaded_at";
const FACT_COLUMNS =
  "id,document_id,category,label,value,excerpt,page,qualifiers,evidence,issues,review_state,reviewed_at,sort_order";

const REMINDER_COLUMNS = "id,course_id,fact_id,lead,fires_at,title,body,dedupe_key,state";

function storagePath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

export class RestStore implements CoursesStore {
  readonly trusted: TrustedWriter;

  constructor(
    private supabaseURL: string,
    private anonKey: string,
    private accessToken: string,
    private userId: string,
    serviceRoleKey: string,
  ) {
    this.trusted = new ServiceRoleWriter(supabaseURL, serviceRoleKey);
  }

  protected async rest<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await fetch(`${this.supabaseURL}/rest/v1/${path}`, {
      ...init,
      headers: {
        apikey: this.anonKey,
        Authorization: `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        ...(init.headers ?? {}),
      },
    });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`REST ${init.method ?? "GET"} ${path.split("?")[0]} failed: ${response.status} ${text.slice(0, 200)}`);
    }
    if (response.status === 204) return undefined as T;
    const text = await response.text();
    return (text ? JSON.parse(text) : undefined) as T;
  }

  async institutionForUser(): Promise<Institution | null> {
    const rows = await this.rest<{ institutions: Institution & { is_active: boolean } | null }[]>(
      `profiles?select=institutions(id,slug,name,is_active)&id=eq.${this.userId}`,
    );
    const inst = rows[0]?.institutions;
    if (!inst || !inst.is_active) return null;
    return { id: inst.id, slug: inst.slug, name: inst.name };
  }

  listTerms(institutionId: string): Promise<TermRow[]> {
    return this.rest(
      `academic_terms?select=id,term_key,name,classes_begin,classes_end,finals_end,timezone,source_id` +
        `&institution_id=eq.${institutionId}&order=classes_begin`,
    );
  }

  listDeadlines(termId: string): Promise<DeadlineRow[]> {
    return this.rest(
      `term_deadlines?select=id,term_id,kind,audience,label,starts_on,ends_on,time_note,detail,is_tentative,source_id` +
        `&term_id=eq.${termId}&order=starts_on`,
    );
  }

  listGuideTopics(institutionId: string): Promise<GuideTopicRow[]> {
    return this.rest(
      `registration_guide_topics?select=topic,sort_order,title,points,comparison,links` +
        `&institution_id=eq.${institutionId}&order=sort_order`,
    );
  }

  listSources(institutionId: string): Promise<SourceRow[]> {
    return this.rest(
      `official_sources?select=id,kind,title,publisher,url,checked_on&institution_id=eq.${institutionId}`,
    );
  }

  // ----- Stage 2 (all with the student's token; RLS applies) -----

  listCourses(termId: string): Promise<CourseRow[]> {
    return this.rest(`enrolled_courses?select=${COURSE_COLUMNS}&term_id=eq.${termId}`);
  }

  async getCourse(id: string): Promise<CourseRow | null> {
    const rows = await this.rest<CourseRow[]>(`enrolled_courses?select=${COURSE_COLUMNS}&id=eq.${id}`);
    return rows[0] ?? null;
  }

  async insertCourse(row: NewCourse): Promise<CourseRow> {
    const rows = await this.rest<CourseRow[]>(`enrolled_courses?select=${COURSE_COLUMNS}`, {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({ ...row, user_id: this.userId }),
    });
    return rows[0];
  }

  async setSyllabusReminder(courseId: string, remindOn: string | null): Promise<void> {
    await this.rest(`enrolled_courses?id=eq.${courseId}`, {
      method: "PATCH",
      body: JSON.stringify({ syllabus_remind_on: remindOn }),
    });
  }

  async deleteCourse(id: string): Promise<void> {
    await this.rest(`enrolled_courses?id=eq.${id}`, { method: "DELETE" });
  }

  listDocuments(courseIds: string[]): Promise<DocumentRow[]> {
    if (!courseIds.length) return Promise.resolve([]);
    return this.rest(`syllabus_documents?select=${DOCUMENT_COLUMNS}&course_id=in.(${courseIds.join(",")})`);
  }

  async getDocument(id: string): Promise<DocumentRow | null> {
    const rows = await this.rest<DocumentRow[]>(`syllabus_documents?select=${DOCUMENT_COLUMNS}&id=eq.${id}`);
    return rows[0] ?? null;
  }

  async deleteDocument(id: string): Promise<void> {
    await this.rest(`syllabus_documents?id=eq.${id}`, { method: "DELETE" });
  }

  listFacts(documentId: string): Promise<FactRow[]> {
    return this.rest(`syllabus_facts?select=${FACT_COLUMNS}&document_id=eq.${documentId}&order=sort_order`);
  }

  // Storage, also with the student's token: bucket policies allow only their folder.
  async putFile(path: string, bytes: Uint8Array, mimeType: string): Promise<void> {
    const response = await fetch(`${this.supabaseURL}/storage/v1/object/${BUCKET}/${storagePath(path)}`, {
      method: "POST",
      headers: {
        apikey: this.anonKey,
        Authorization: `Bearer ${this.accessToken}`,
        "Content-Type": mimeType,
        "x-upsert": "false",
      },
      body: new Uint8Array(bytes),
    });
    if (!response.ok) throw new Error(`Storage upload failed: ${response.status}`);
  }

  async getFile(path: string): Promise<Uint8Array> {
    const response = await fetch(`${this.supabaseURL}/storage/v1/object/authenticated/${BUCKET}/${storagePath(path)}`, {
      headers: { apikey: this.anonKey, Authorization: `Bearer ${this.accessToken}` },
    });
    if (!response.ok) throw new Error(`Storage download failed: ${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
  }

  async removeFiles(paths: string[]): Promise<void> {
    if (!paths.length) return;
    const response = await fetch(`${this.supabaseURL}/storage/v1/object/${BUCKET}`, {
      method: "DELETE",
      headers: {
        apikey: this.anonKey,
        Authorization: `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ prefixes: paths }),
    });
    if (!response.ok) throw new Error(`Storage delete failed: ${response.status}`);
  }

  // ----- Stage 3 (student's token; RLS and column grants apply) -----

  async getFact(id: string): Promise<FactRow | null> {
    const rows = await this.rest<FactRow[]>(`syllabus_facts?select=${FACT_COLUMNS}&id=eq.${id}`);
    return rows[0] ?? null;
  }

  async setFactReview(id: string, state: FactRow["review_state"]): Promise<void> {
    await this.rest(`syllabus_facts?id=eq.${id}`, { method: "PATCH", body: JSON.stringify({ review_state: state }) });
  }

  listCorrections(documentIds: string[]): Promise<CorrectionRow[]> {
    if (!documentIds.length) return Promise.resolve([]);
    return this.rest(
      `syllabus_fact_corrections?select=fact_id,corrected,note,updated_at,syllabus_facts!inner(document_id)` +
        `&syllabus_facts.document_id=in.(${documentIds.join(",")})`,
    );
  }

  async upsertCorrection(factId: string, corrected: Record<string, unknown>, note: string | null): Promise<void> {
    await this.rest(`syllabus_fact_corrections?on_conflict=fact_id`, {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({ user_id: this.userId, fact_id: factId, corrected, note }),
    });
  }

  async deleteCorrection(factId: string): Promise<void> {
    await this.rest(`syllabus_fact_corrections?fact_id=eq.${factId}`, { method: "DELETE" });
  }

  listReminders(courseId: string | null): Promise<ReminderRow[]> {
    const filter = courseId ? `&course_id=eq.${courseId}` : "";
    return this.rest(`course_reminders?select=${REMINDER_COLUMNS}${filter}&order=fires_at`);
  }

  async insertReminder(row: NewReminder): Promise<ReminderRow> {
    const rows = await this.rest<ReminderRow[]>(`course_reminders?select=${REMINDER_COLUMNS}`, {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({ ...row, user_id: this.userId }),
    });
    return rows[0];
  }

  async updateReminder(id: string, patch: Partial<NewReminder & { state: ReminderRow["state"] }>): Promise<void> {
    await this.rest(`course_reminders?id=eq.${id}`, { method: "PATCH", body: JSON.stringify(patch) });
  }

  async deleteReminder(id: string): Promise<void> {
    await this.rest(`course_reminders?id=eq.${id}`, { method: "DELETE" });
  }
}

/** Service-role writes for extraction results. Callers verify ownership first. */
class ServiceRoleWriter implements TrustedWriter {
  constructor(private supabaseURL: string, private serviceRoleKey: string) {}

  private async write(path: string, init: RequestInit): Promise<void> {
    const response = await fetch(`${this.supabaseURL}/rest/v1/${path}`, {
      ...init,
      headers: {
        apikey: this.serviceRoleKey,
        Authorization: `Bearer ${this.serviceRoleKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
    });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`Trusted write ${path.split("?")[0]} failed: ${response.status} ${text.slice(0, 200)}`);
    }
  }

  insertDocument(row: NewDocument): Promise<void> {
    return this.write("syllabus_documents", { method: "POST", body: JSON.stringify(row) });
  }

  updateDocument(id: string, patch: Partial<DocumentRow>): Promise<void> {
    return this.write(`syllabus_documents?id=eq.${id}`, { method: "PATCH", body: JSON.stringify(patch) });
  }

  insertFacts(rows: NewFact[]): Promise<void> {
    return this.write("syllabus_facts", { method: "POST", body: JSON.stringify(rows) });
  }
}
