// Stage 2: enrolled courses and private syllabus uploads.

import type { Deps } from "./handler.ts";
import { localDate, stringField } from "./handler.ts";
import { type PageText, verifyExtraction } from "./extraction.ts";
import { type CourseRow, type DocumentRow, HandlerError, type TermRow } from "./types.ts";

export const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_PAGES = 60;
const MAX_PAGE_CHARS = 20_000;
const MAX_TOTAL_CHARS = 150_000;
const MIN_TOTAL_CHARS = 80;
const ALLOWED_TYPES: Record<string, string> = {
  "application/pdf": "pdf",
  "image/png": "png",
  "image/jpeg": "jpg",
};

export type CourseStatus = "needed" | "processing" | "review_needed" | "ready" | "update_available";

// ---------------------------------------------------------------------------
// Courses
// ---------------------------------------------------------------------------

export async function listCourses(body: Record<string, unknown>, deps: Deps) {
  const { term } = await resolveTerm(stringField(body, "term_key"), deps);
  const courses = await deps.store.listCourses(term.id);
  const documents = await deps.store.listDocuments(courses.map((c) => c.id));
  return {
    term_key: term.term_key,
    courses: courses
      .slice()
      .sort((a, b) => `${a.subject}${a.number}`.localeCompare(`${b.subject}${b.number}`))
      .map((c) => courseDTO(c, term, documents.filter((d) => d.course_id === c.id))),
  };
}

export async function addCourse(body: Record<string, unknown>, deps: Deps) {
  const { institution, term } = await resolveTerm(stringField(body, "term_key"), deps);
  const subject = (stringField(body, "subject") ?? "").toUpperCase().replace(/\s+/g, "");
  const number = (stringField(body, "number") ?? "").toUpperCase().replace(/\s+/g, "");
  const section = (stringField(body, "section_code") ?? "").replace(/\s+/g, "");
  const instructor = (stringField(body, "instructor_name") ?? "").replace(/\s+/g, " ");
  const title = (stringField(body, "title") ?? "").slice(0, 200);
  const origin = stringField(body, "origin") === "transcript" ? "transcript" : "manual";

  if (!/^[A-Z]{2,5}$/.test(subject)) throw invalid("Enter the subject, like CS or MATH.");
  if (!/^[0-9]{3,4}[A-Z]?$/.test(number)) throw invalid("Enter the course number, like 2114.");
  if (!/^[A-Za-z0-9-]{1,20}$/.test(section)) throw invalid("Enter the section's CRN from your schedule.");
  if (instructor.length < 1 || instructor.length > 120) throw invalid("Enter the instructor's name as it appears on your schedule.");

  const existing = await deps.store.listCourses(term.id);
  if (existing.some((c) => c.subject === subject && c.number === number && c.section_code === section)) {
    throw new HandlerError(409, "COURSES_DUPLICATE", "You've already added this section for this term.");
  }
  const course = await deps.store.insertCourse({
    institution_id: institution.id,
    term_id: term.id,
    subject,
    number,
    title,
    section_code: section,
    instructor_name: instructor,
    origin,
  });
  return { course: courseDTO(course, term, []) };
}

export async function setSyllabusReminder(body: Record<string, unknown>, deps: Deps) {
  const course = await ownedCourse(stringField(body, "course_id"), deps);
  const term = await termFor(course, deps);
  const remindOn = stringField(body, "remind_on");
  if (remindOn !== null) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(remindOn)) throw invalid("Choose a reminder date.");
    const today = localDate(deps.now(), term.timezone);
    if (remindOn < today) throw invalid("Choose a date that hasn't passed.");
    if (remindOn > (term.finals_end ?? term.classes_end)) throw invalid(`Choose a date before ${term.name} ends.`);
  }
  await deps.store.setSyllabusReminder(course.id, remindOn);
  return { course_id: course.id, syllabus_remind_on: remindOn };
}

export async function deleteCourse(body: Record<string, unknown>, deps: Deps) {
  const course = await ownedCourse(stringField(body, "course_id"), deps);
  const documents = await deps.store.listDocuments([course.id]);
  // Files first: if that fails nothing is deleted, so no file is ever orphaned.
  if (documents.length) await deps.store.removeFiles(documents.map((d) => d.storage_path));
  await deps.store.deleteCourse(course.id);
  return { deleted_course_id: course.id, deleted_document_ids: documents.map((d) => d.id) };
}

// ---------------------------------------------------------------------------
// Uploads
// ---------------------------------------------------------------------------

export async function uploadSyllabus(body: Record<string, unknown>, deps: Deps) {
  const course = await ownedCourse(stringField(body, "course_id"), deps);
  const term = await termFor(course, deps);

  const file = body.file;
  if (!(file instanceof File)) throw invalid("Choose a PDF, PNG, or JPEG file.");
  const extension = ALLOWED_TYPES[file.type];
  if (!extension) throw new HandlerError(415, "SYLLABUS_TYPE", "Upload a PDF, PNG, or JPEG file.");
  if (file.size === 0 || file.size > MAX_FILE_BYTES) {
    throw new HandlerError(413, "SYLLABUS_SIZE", "The file must be smaller than 10 MB.");
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!matchesSignature(bytes, file.type)) {
    throw new HandlerError(415, "SYLLABUS_TYPE", "That file doesn't look like a PDF, PNG, or JPEG.");
  }

  const pages = parsePages(body.pages);
  const textMethod = stringField(body, "text_method");
  if (!textMethod || !["pdf_text", "ocr", "mixed"].includes(textMethod)) throw invalid("Missing text_method.");

  const sha256 = await sha256Hex(bytes);
  const documents = await deps.store.listDocuments([course.id]);
  const duplicate = documents.find((d) => d.sha256 === sha256);
  if (duplicate && duplicate.processing_state !== "failed") {
    return { duplicate: true, document: documentDTO(duplicate) };
  }
  if (duplicate) {
    // Retrying a failed upload of the same file: replace the failed attempt.
    await deps.store.removeFiles([duplicate.storage_path]);
    await deps.store.deleteDocument(duplicate.id);
  }

  const version = documents.filter((d) => d !== duplicate).reduce((max, d) => Math.max(max, d.version), 0) + 1;
  const id = crypto.randomUUID();
  const path = `${deps.userId}/${course.id}/${id}.${extension}`;
  const fileName = sanitizeFileName(file.name || `syllabus.${extension}`);

  await deps.store.putFile(path, bytes, file.type);
  try {
    await deps.store.trusted.insertDocument({
      id,
      user_id: deps.userId,
      course_id: course.id,
      version,
      storage_path: path,
      file_name: fileName,
      mime_type: file.type,
      size_bytes: bytes.length,
      sha256,
      page_count: pages.length,
      text_method: textMethod,
      processing_state: "processing",
    });
  } catch (error) {
    await deps.store.removeFiles([path]).catch(() => {});
    throw error;
  }

  const extraction = await deps.extractor(pages);
  if (!extraction.ok) {
    await deps.store.trusted.updateDocument(id, { processing_state: "failed", error_code: extraction.code });
    return { duplicate: false, document: documentDTO((await deps.store.getDocument(id))!) };
  }

  const verified = verifyExtraction(
    extraction.data,
    pages,
    { name: term.name, classes_begin: term.classes_begin, finals_end: term.finals_end ?? term.classes_end, timezone: term.timezone },
    { subject: course.subject, number: course.number, section_code: course.section_code, instructor_name: course.instructor_name },
  );
  const findings = [...verified.findings];
  if (textMethod !== "pdf_text") {
    findings.push({
      code: "ocr",
      message: "Some pages were read from images, so numbers and dates may be misread. Compare them with the page.",
    });
  }

  if (verified.facts.length) {
    await deps.store.trusted.insertFacts(
      verified.facts.map((f) => ({ ...f, user_id: deps.userId, document_id: id })),
    );
  }
  await deps.store.trusted.updateDocument(id, {
    processing_state: "review_needed",
    findings,
    stated_identity: verified.stated_identity,
    extraction_model: extraction.model,
    extracted_at: deps.now().toISOString(),
  });

  const document = (await deps.store.getDocument(id))!;
  return { duplicate: false, document: documentDTO(document), facts: await deps.store.listFacts(id) };
}

export async function getDocument(body: Record<string, unknown>, deps: Deps) {
  const document = await ownedDocument(stringField(body, "document_id"), deps);
  const course = (await deps.store.getCourse(document.course_id))!;
  const term = await termFor(course, deps);
  return {
    document: documentDTO(document),
    course: courseDTO(course, term, await deps.store.listDocuments([course.id])),
    facts: await deps.store.listFacts(document.id),
  };
}

export async function documentFile(body: Record<string, unknown>, deps: Deps) {
  const document = await ownedDocument(stringField(body, "document_id"), deps);
  const bytes = await deps.store.getFile(document.storage_path);
  return { mime_type: document.mime_type, file_name: document.file_name, data_base64: base64(bytes) };
}

export async function deleteDocument(body: Record<string, unknown>, deps: Deps) {
  const document = await ownedDocument(stringField(body, "document_id"), deps);
  await deps.store.removeFiles([document.storage_path]);
  await deps.store.deleteDocument(document.id); // cascades extracted facts
  return { deleted_document_id: document.id };
}

// ---------------------------------------------------------------------------
// Status and DTOs
// ---------------------------------------------------------------------------

export function courseStatus(documents: DocumentRow[]): {
  status: CourseStatus;
  current: DocumentRow | null;
  pending: DocumentRow | null;
  last_failed: DocumentRow | null;
} {
  const ordered = documents.slice().sort((a, b) => b.version - a.version);
  const current = ordered.find((d) => d.processing_state === "reviewed") ?? null;
  const latest = ordered[0] ?? null;
  const newer = ordered.filter((d) => !current || d.version > current.version);
  const processing = newer.find((d) => d.processing_state === "processing") ?? null;
  const pending = newer.find((d) => d.processing_state === "review_needed") ?? null;
  const lastFailed = latest?.processing_state === "failed" ? latest : null;

  let status: CourseStatus;
  if (processing) status = "processing";
  else if (pending) status = current ? "update_available" : "review_needed";
  else if (current) status = "ready";
  else status = "needed";
  return { status, current, pending, last_failed: lastFailed };
}

export function courseDTO(course: CourseRow, term: TermRow, documents: DocumentRow[]) {
  const s = courseStatus(documents);
  return {
    id: course.id,
    term_key: term.term_key,
    subject: course.subject,
    number: course.number,
    title: course.title,
    section_code: course.section_code,
    instructor_name: course.instructor_name,
    syllabus_remind_on: course.syllabus_remind_on,
    status: s.status,
    current_document_id: s.current?.id ?? null,
    pending_document_id: s.pending?.id ?? null,
    last_upload_failed: s.last_failed !== null,
    documents: documents
      .slice()
      .sort((a, b) => b.version - a.version)
      .map(documentDTO),
  };
}

export function documentDTO(d: DocumentRow) {
  return {
    id: d.id,
    course_id: d.course_id,
    version: d.version,
    file_name: d.file_name,
    mime_type: d.mime_type,
    size_bytes: d.size_bytes,
    page_count: d.page_count,
    text_method: d.text_method,
    processing_state: d.processing_state,
    error_code: d.error_code,
    findings: d.findings,
    stated_identity: d.stated_identity,
    uploaded_at: d.uploaded_at,
    extracted_at: d.extracted_at,
    reviewed_at: d.reviewed_at,
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function resolveTerm(termKey: string | null, deps: Deps) {
  const institution = await deps.store.institutionForUser();
  if (!institution) throw new HandlerError(404, "COURSES_UNSUPPORTED_SCHOOL", "Course tools aren't available for your school yet.");
  const terms = await deps.store.listTerms(institution.id);
  const term = terms.find((t) => t.term_key === termKey);
  if (!term) throw new HandlerError(404, "COURSES_TERM_NOT_FOUND", "Choose a term.");
  return { institution, term };
}

export async function termFor(course: CourseRow, deps: Deps): Promise<TermRow> {
  const institution = await deps.store.institutionForUser();
  const terms = institution ? await deps.store.listTerms(institution.id) : [];
  const term = terms.find((t) => t.id === course.term_id);
  if (!term) throw new HandlerError(404, "COURSES_TERM_NOT_FOUND", "This course's term isn't available.");
  return term;
}

export async function ownedCourse(id: string | null, deps: Deps): Promise<CourseRow> {
  if (!id || !isUUID(id)) throw new HandlerError(404, "COURSES_NOT_FOUND", "Course not found.");
  const course = await deps.store.getCourse(id); // RLS: other students' rows are invisible
  if (!course) throw new HandlerError(404, "COURSES_NOT_FOUND", "Course not found.");
  return course;
}

export async function ownedDocument(id: string | null, deps: Deps): Promise<DocumentRow> {
  if (!id || !isUUID(id)) throw new HandlerError(404, "SYLLABUS_NOT_FOUND", "Syllabus not found.");
  const document = await deps.store.getDocument(id);
  if (!document) throw new HandlerError(404, "SYLLABUS_NOT_FOUND", "Syllabus not found.");
  return document;
}

function parsePages(value: unknown): PageText[] {
  let parsed: unknown;
  try {
    parsed = typeof value === "string" ? JSON.parse(value) : value;
  } catch {
    throw invalid("The syllabus text couldn't be read. Try again.");
  }
  if (!Array.isArray(parsed) || parsed.length < 1 || parsed.length > MAX_PAGES) {
    throw invalid(`Syllabi can have up to ${MAX_PAGES} pages.`);
  }
  const pages: PageText[] = [];
  let total = 0;
  parsed.forEach((p, i) => {
    const page = (p as { page?: unknown }).page;
    const text = (p as { text?: unknown }).text;
    if (page !== i + 1 || typeof text !== "string") throw invalid("The syllabus text couldn't be read. Try again.");
    const clipped = text.slice(0, MAX_PAGE_CHARS);
    total += clipped.trim().length;
    pages.push({ page: i + 1, text: clipped });
  });
  if (total > MAX_TOTAL_CHARS) throw invalid("This document is too long to process.");
  if (total < MIN_TOTAL_CHARS) {
    throw new HandlerError(422, "SYLLABUS_NO_TEXT", "Agora couldn't read text in this file. Try a clearer copy or the original PDF.");
  }
  return pages;
}

function matchesSignature(bytes: Uint8Array, mimeType: string): boolean {
  const starts = (sig: number[]) => sig.every((b, i) => bytes[i] === b);
  if (mimeType === "application/pdf") return starts([0x25, 0x50, 0x44, 0x46]); // %PDF
  if (mimeType === "image/png") return starts([0x89, 0x50, 0x4e, 0x47]);
  if (mimeType === "image/jpeg") return starts([0xff, 0xd8, 0xff]);
  return false;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sanitizeFileName(name: string): string {
  const cleaned = name.replace(/[\u0000-\u001f/\\]/g, "").trim().slice(0, 200);
  return cleaned || "syllabus";
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

export function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function invalid(message: string) {
  return new HandlerError(400, "COURSES_INVALID", message);
}
