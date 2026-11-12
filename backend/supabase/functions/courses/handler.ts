// Course companion actions. Pure with respect to I/O: everything external
// (database, storage, model, clock) comes in through `deps`, so the same code
// runs in the edge function, in tests, and in the local QA server.

import type { QuotaDecision } from "../_shared/quota.ts";
import type { Extractor } from "./extraction.ts";
import * as review from "./review.ts";
import * as syllabi from "./syllabi.ts";
import {
  type CoursesStore,
  type DeadlineRow,
  HandlerError,
  type HandlerResult,
  type TermRow,
} from "./types.ts";

export type Deps = {
  store: CoursesStore;
  now: () => Date;
  /** The signed-in student; used only to name their private storage folder. */
  userId: string;
  extractor: Extractor;
  /**
   * Reserves one paid document extraction for this student (migration 010).
   * Called only when an extraction will actually run, never for duplicates.
   */
  reserveExtraction: () => Promise<QuotaDecision>;
};

const REGISTRATION_KINDS = new Set([
  "course_request",
  "add_drop_begins",
  "add_drop_reopens",
  "last_day_add",
  "last_day_drop",
]);

export async function handleAction(
  action: string,
  body: Record<string, unknown>,
  deps: Deps,
): Promise<HandlerResult> {
  try {
    switch (action) {
      case "overview":
        return ok(await overview(deps));
      case "registration_guide":
        return ok(await registrationGuide(stringField(body, "term_key"), deps));
      case "list_courses":
        return ok(await syllabi.listCourses(body, deps));
      case "add_course":
        return ok(await syllabi.addCourse(body, deps));
      case "set_syllabus_reminder":
        return ok(await syllabi.setSyllabusReminder(body, deps));
      case "delete_course":
        return ok(await syllabi.deleteCourse(body, deps));
      case "upload_syllabus":
        return ok(await syllabi.uploadSyllabus(body, deps));
      case "get_document":
        return ok(await syllabi.getDocument(body, deps));
      case "document_file":
        return ok(await syllabi.documentFile(body, deps));
      case "delete_document":
        return ok(await syllabi.deleteDocument(body, deps));
      case "review_fact":
        return ok(await review.reviewFact(body, deps));
      case "confirm_unflagged":
        return ok(await review.confirmUnflagged(body, deps));
      case "correct_fact":
        return ok(await review.correctFact(body, deps));
      case "remove_correction":
        return ok(await review.removeCorrection(body, deps));
      case "complete_review":
        return ok(await review.completeReview(body, deps));
      case "course_dashboard":
        return ok(await review.courseDashboard(body, deps));
      case "add_reminder":
        return ok(await review.addReminder(body, deps));
      case "delete_reminder":
        return ok(await review.deleteReminder(body, deps));
      case "resolve_reminder":
        return ok(await review.resolveReminder(body, deps));
      case "list_reminders":
        return ok(await review.listReminders(deps));
      default:
        throw new HandlerError(400, "COURSES_UNKNOWN_ACTION", "Unknown action.");
    }
  } catch (error) {
    if (error instanceof HandlerError) {
      return { status: error.status, body: { detail: { code: error.code, message: error.message } } };
    }
    console.error("courses handler error", error);
    return {
      status: 500,
      body: { detail: { code: "COURSES_INTERNAL", message: "Something went wrong. Please try again." } },
    };
  }
}

// ---------------------------------------------------------------------------
// Stage 1: terms and registration guidance
// ---------------------------------------------------------------------------

async function overview(deps: Deps) {
  const institution = await deps.store.institutionForUser();
  if (!institution) {
    return { supported: false, institution: null, terms: [], current_term_key: null, registration: null };
  }
  const terms = await deps.store.listTerms(institution.id);
  if (!terms.length) {
    return { supported: false, institution, terms: [], current_term_key: null, registration: null };
  }

  const current = currentTerm(terms, deps.now());
  const next = await nextRegistrationDeadline(terms, deps);

  return {
    supported: true,
    institution,
    terms: terms.map(termDTO),
    current_term_key: current?.term_key ?? null,
    registration: next ? { term_key: next.term_key, term_name: next.term_name, deadline: next.deadline } : null,
  };
}

async function registrationGuide(termKey: string | null, deps: Deps) {
  const institution = await deps.store.institutionForUser();
  if (!institution) throw unsupported();
  const terms = await deps.store.listTerms(institution.id);
  if (!terms.length) throw unsupported();

  const term = termKey
    ? terms.find((t) => t.term_key === termKey)
    : (await nextRegistrationDeadline(terms, deps))?.term ?? currentTerm(terms, deps.now());
  if (!term) throw new HandlerError(404, "COURSES_TERM_NOT_FOUND", "That term isn't available.");

  const [deadlines, topics, sources] = await Promise.all([
    deps.store.listDeadlines(term.id),
    deps.store.listGuideTopics(institution.id),
    deps.store.listSources(institution.id),
  ]);
  const today = localDate(deps.now(), term.timezone);

  return {
    institution,
    term: termDTO(term),
    terms: terms.map(termDTO),
    deadlines: deadlines
      .slice()
      .sort((a, b) => a.starts_on.localeCompare(b.starts_on) || a.kind.localeCompare(b.kind))
      .map((d) => ({ ...deadlineDTO(d), state: deadlineState(d, today) })),
    topics: topics.slice().sort((a, b) => a.sort_order - b.sort_order),
    sources,
    // Agora shows guidance; it never acts in the registration system.
    can_register_in_app: false,
  };
}

/** The soonest registration-related deadline still ahead, across terms. */
async function nextRegistrationDeadline(terms: TermRow[], deps: Deps) {
  const ordered = terms.slice().sort((a, b) => a.classes_begin.localeCompare(b.classes_begin));
  for (const term of ordered) {
    const today = localDate(deps.now(), term.timezone);
    const upcoming = (await deps.store.listDeadlines(term.id))
      .filter((d) => REGISTRATION_KINDS.has(d.kind) && (d.ends_on ?? d.starts_on) >= today)
      .sort((a, b) => a.starts_on.localeCompare(b.starts_on));
    if (upcoming.length) {
      const d = upcoming[0];
      return { term, term_key: term.term_key, term_name: term.name, deadline: { ...deadlineDTO(d), state: deadlineState(d, today) } };
    }
  }
  return null;
}

/** The term in session today; otherwise the next one; otherwise the latest. */
export function currentTerm(terms: TermRow[], now: Date): TermRow | null {
  const ordered = terms.slice().sort((a, b) => a.classes_begin.localeCompare(b.classes_begin));
  for (const term of ordered) {
    const today = localDate(now, term.timezone);
    if (today >= term.classes_begin && today <= (term.finals_end ?? term.classes_end)) return term;
  }
  for (const term of ordered) {
    if (localDate(now, term.timezone) < term.classes_begin) return term;
  }
  return ordered.at(-1) ?? null;
}

function deadlineState(d: DeadlineRow, today: string): "past" | "open" | "today" | "upcoming" {
  const end = d.ends_on ?? d.starts_on;
  if (end < today) return "past";
  if (d.ends_on && d.starts_on <= today) return "open";
  if (d.starts_on === today) return "today";
  return "upcoming";
}

/** yyyy-mm-dd for `now` in the given IANA time zone. */
export function localDate(now: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function termDTO(t: TermRow) {
  return {
    term_key: t.term_key,
    name: t.name,
    classes_begin: t.classes_begin,
    classes_end: t.classes_end,
    finals_end: t.finals_end,
    timezone: t.timezone,
    source_id: t.source_id,
  };
}

function deadlineDTO(d: DeadlineRow) {
  return {
    id: d.id,
    kind: d.kind,
    audience: d.audience,
    label: d.label,
    starts_on: d.starts_on,
    ends_on: d.ends_on,
    time_note: d.time_note,
    detail: d.detail,
    is_tentative: d.is_tentative,
    source_id: d.source_id,
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ok(body: unknown): HandlerResult {
  return { status: 200, body };
}

function unsupported() {
  return new HandlerError(404, "COURSES_UNSUPPORTED_SCHOOL", "Course tools aren't available for your school yet.");
}

export function stringField(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
}
