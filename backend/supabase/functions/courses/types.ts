// Shapes shared by the courses handler and its stores.

export type Institution = { id: string; slug: string; name: string };

export type TermRow = {
  id: string;
  term_key: string;
  name: string;
  classes_begin: string; // yyyy-mm-dd
  classes_end: string;
  finals_end: string | null;
  timezone: string;
  source_id: string;
};

export type DeadlineRow = {
  id: string;
  term_id: string;
  kind: string;
  audience: string;
  label: string;
  starts_on: string;
  ends_on: string | null;
  time_note: string | null;
  detail: string | null;
  is_tentative: boolean;
  source_id: string;
};

export type GuideTopicRow = {
  topic: string;
  sort_order: number;
  title: string;
  points: { text: string; source_id: string }[];
  comparison: { aspect: string; drop: string; withdraw: string; source_id: string }[] | null;
  links: { title: string; url: string }[];
};

export type SourceRow = {
  id: string;
  kind: string;
  title: string;
  publisher: string;
  url: string;
  checked_on: string;
};

export type CourseRow = {
  id: string;
  term_id: string;
  subject: string;
  number: string;
  title: string;
  section_code: string;
  instructor_name: string;
  origin: string;
  syllabus_remind_on: string | null;
  created_at: string;
};

export type NewCourse = Omit<CourseRow, "id" | "created_at" | "syllabus_remind_on"> & { institution_id: string };

export type DocumentRow = {
  id: string;
  course_id: string;
  version: number;
  storage_path: string;
  file_name: string;
  mime_type: string;
  size_bytes: number;
  sha256: string;
  page_count: number;
  text_method: string;
  processing_state: "processing" | "review_needed" | "reviewed" | "failed";
  error_code: string | null;
  findings: { code: string; message: string; page?: number; detail?: unknown }[];
  stated_identity: Record<string, unknown>;
  extraction_model: string | null;
  extracted_at: string | null;
  reviewed_at: string | null;
  uploaded_at: string;
};

export type NewDocument = Omit<
  DocumentRow,
  "findings" | "stated_identity" | "extraction_model" | "extracted_at" | "reviewed_at" | "uploaded_at" | "error_code"
> & { user_id: string };

export type FactRow = {
  id: string;
  document_id: string;
  category: string;
  label: string;
  value: Record<string, unknown>;
  excerpt: string;
  page: number;
  qualifiers: string[];
  evidence: string;
  issues: string[];
  review_state: "pending" | "confirmed" | "rejected";
  reviewed_at: string | null;
  sort_order: number;
};

export type NewFact = Omit<FactRow, "id" | "review_state" | "reviewed_at"> & { user_id: string };

/**
 * Writes made by the server on the student's behalf after ownership has been
 * verified with the student's own token (service role). Students can't make
 * these writes themselves, so extracted facts can't be forged.
 */
export interface TrustedWriter {
  insertDocument(row: NewDocument): Promise<void>;
  updateDocument(id: string, patch: Partial<DocumentRow>): Promise<void>;
  insertFacts(rows: NewFact[]): Promise<void>;
}

/**
 * Data access for one signed-in student. Every implementation must act with
 * that student's privileges (row-level security), never as the service role.
 */
export interface CoursesStore {
  institutionForUser(): Promise<Institution | null>;
  listTerms(institutionId: string): Promise<TermRow[]>;
  listDeadlines(termId: string): Promise<DeadlineRow[]>;
  listGuideTopics(institutionId: string): Promise<GuideTopicRow[]>;
  listSources(institutionId: string): Promise<SourceRow[]>;

  // Stage 2: the student's own courses, uploads, and extracted facts.
  listCourses(termId: string): Promise<CourseRow[]>;
  getCourse(id: string): Promise<CourseRow | null>;
  insertCourse(row: NewCourse): Promise<CourseRow>;
  setSyllabusReminder(courseId: string, remindOn: string | null): Promise<void>;
  deleteCourse(id: string): Promise<void>;
  listDocuments(courseIds: string[]): Promise<DocumentRow[]>;
  getDocument(id: string): Promise<DocumentRow | null>;
  deleteDocument(id: string): Promise<void>;
  listFacts(documentId: string): Promise<FactRow[]>;
  putFile(path: string, bytes: Uint8Array, mimeType: string): Promise<void>;
  getFile(path: string): Promise<Uint8Array>;
  removeFiles(paths: string[]): Promise<void>;

  trusted: TrustedWriter;
}

export type HandlerResult = { status: number; body: unknown };

export class HandlerError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}
