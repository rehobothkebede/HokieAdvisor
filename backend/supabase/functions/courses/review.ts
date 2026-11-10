// Stage 3: student review, private corrections, version changes, the course
// dashboard, and reminders for confirmed dates.

import type { Deps } from "./handler.ts";
import { localDate, stringField } from "./handler.ts";
import { normalizeText } from "./extraction.ts";
import { courseDTO, courseStatus, documentDTO, ownedCourse, ownedDocument, termFor } from "./syllabi.ts";
import {
  type CorrectionRow,
  type CourseRow,
  type DocumentRow,
  type FactRow,
  HandlerError,
  type ReminderRow,
  type TermRow,
} from "./types.ts";

const DATED = new Set(["exam", "assignment_deadline"]);
const CORRECTABLE_FIELDS = ["date", "start_time", "end_time", "location", "weight_percent", "text"] as const;
const COMPARED_FIELDS = ["date", "relative_timing", "start_time", "end_time", "exam_format", "weight_percent", "location", "summary"];
const LEAD_TEXT = { week_before: "in one week", day_before: "tomorrow", morning_of: "today" } as const;

// ---------------------------------------------------------------------------
// Review
// ---------------------------------------------------------------------------

export async function reviewFact(body: Record<string, unknown>, deps: Deps) {
  const { fact, document } = await editableFact(stringField(body, "fact_id"), deps);
  const decision = stringField(body, "decision");
  const state = decision === "confirm" ? "confirmed" : decision === "reject" ? "rejected" : decision === "undo" ? "pending" : null;
  if (!state) throw invalid("Choose confirm, reject, or undo.");
  if (state === "confirmed") {
    if (fact.issues.includes("other_term")) throw conflict("Dates from another term's syllabus can't be confirmed.");
    if (fact.evidence === "not_found" && !(await correctionFor(fact.id, document.id, deps))) {
      throw conflict("This detail wasn't found in the document. Correct it or mark it not right.");
    }
  }
  await deps.store.setFactReview(fact.id, state);
  return { fact: await deps.store.getFact(fact.id) };
}

/** Confirms the remaining pending policy facts that have no dates and no flags. */
export async function confirmUnflagged(body: Record<string, unknown>, deps: Deps) {
  const document = await reviewableDocument(stringField(body, "document_id"), deps);
  const facts = await deps.store.listFacts(document.id);
  const eligible = facts.filter((f) => f.review_state === "pending" && f.issues.length === 0 && f.evidence === "verified" &&
    !DATED.has(f.category) && !f.value.date);
  for (const f of eligible) await deps.store.setFactReview(f.id, "confirmed");
  return { confirmed: eligible.map((f) => f.id) };
}

export async function correctFact(body: Record<string, unknown>, deps: Deps) {
  const { fact, document } = await editableFact(stringField(body, "fact_id"), deps);
  if (fact.issues.includes("other_term")) throw conflict("Details from another term's syllabus can't be used.");
  const input = (body.corrected && typeof body.corrected === "object") ? body.corrected as Record<string, unknown> : {};
  const corrected: Record<string, unknown> = {};
  for (const key of CORRECTABLE_FIELDS) {
    if (!(key in input)) continue;
    const value = input[key];
    if (value === null || value === "") {
      corrected[key] = null;
      continue;
    }
    switch (key) {
      case "date":
        if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || isNaN(Date.parse(value))) throw invalid("Enter a valid date.");
        break;
      case "start_time":
      case "end_time":
        if (typeof value !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) throw invalid("Enter a valid time.");
        break;
      case "weight_percent":
        if (typeof value !== "number" || value < 0 || value > 100) throw invalid("Enter a percentage from 0 to 100.");
        break;
      default:
        if (typeof value !== "string" || value.length > 400) throw invalid("Keep corrections under 400 characters.");
    }
    corrected[key] = value;
  }
  if (!Object.keys(corrected).length) throw invalid("Change at least one value.");
  const note = stringField(body, "note")?.slice(0, 500) ?? null;
  await deps.store.upsertCorrection(fact.id, corrected, note);
  // A corrected fact counts as reviewed: the student's value is used, labeled as theirs.
  if (fact.review_state !== "confirmed") await deps.store.setFactReview(fact.id, "confirmed");
  return { fact: await deps.store.getFact(fact.id), correction: await correctionFor(fact.id, document.id, deps) };
}

export async function removeCorrection(body: Record<string, unknown>, deps: Deps) {
  const { fact } = await editableFact(stringField(body, "fact_id"), deps);
  await deps.store.deleteCorrection(fact.id);
  if (fact.evidence === "not_found" && fact.review_state === "confirmed") await deps.store.setFactReview(fact.id, "pending");
  return { fact: await deps.store.getFact(fact.id) };
}

export async function completeReview(body: Record<string, unknown>, deps: Deps) {
  const document = await reviewableDocument(stringField(body, "document_id"), deps);
  const course = (await deps.store.getCourse(document.course_id))!;
  const term = await termFor(course, deps);
  const mismatch = document.findings.find((f) => f.code === "term_mismatch");
  if (mismatch) throw conflict(`This syllabus is for a different term. Upload the ${term.name} syllabus for this section.`);
  const facts = await deps.store.listFacts(document.id);
  const pending = facts.filter((f) => f.review_state === "pending");
  if (pending.length) {
    throw conflict(`Review ${pending.length} more item${pending.length === 1 ? "" : "s"} first.`);
  }

  const before = courseStatus(await deps.store.listDocuments([course.id])).current;
  await deps.store.trusted.updateDocument(document.id, { processing_state: "reviewed", reviewed_at: deps.now().toISOString() });

  // Reminders on the previous version: kept only when the date is unchanged.
  const needsReconfirm: string[] = [];
  if (before) {
    const corrections = await deps.store.listCorrections([document.id, before.id]);
    const newFacts = effectiveFacts(facts.filter((f) => f.review_state === "confirmed"), corrections);
    const oldFacts = new Map((await deps.store.listFacts(before.id)).map((f) => [f.id, f]));
    for (const reminder of await deps.store.listReminders(course.id)) {
      const old = oldFacts.get(reminder.fact_id);
      if (!old) continue;
      const oldEffective = effectiveFacts([old], corrections)[0];
      const match = newFacts.find((f) => identity(f) === identity(oldEffective));
      if (match && match.effective.date === oldEffective.effective.date &&
          match.effective.start_time === oldEffective.effective.start_time) {
        await deps.store.updateReminder(reminder.id, { fact_id: match.id });
      } else {
        await deps.store.updateReminder(reminder.id, { state: "needs_reconfirm" });
        needsReconfirm.push(reminder.id);
      }
    }
  }
  return {
    document: documentDTO((await deps.store.getDocument(document.id))!),
    reminders_needing_reconfirm: needsReconfirm,
  };
}

/** What changed between the reviewed version in use and a newer upload. */
export async function documentChanges(document: DocumentRow, deps: Deps) {
  const documents = await deps.store.listDocuments([document.course_id]);
  const current = documents
    .filter((d) => d.processing_state === "reviewed" && d.version < document.version)
    .sort((a, b) => b.version - a.version)[0];
  if (!current) return null;
  const corrections = await deps.store.listCorrections([current.id]);
  const before = effectiveFacts((await deps.store.listFacts(current.id)).filter((f) => f.review_state === "confirmed"), corrections);
  const after = await deps.store.listFacts(document.id);
  const reminders = await deps.store.listReminders(document.course_id);

  const changed: unknown[] = [];
  const added: unknown[] = [];
  for (const fact of after) {
    const match = before.find((b) => identity(b) === identity({ category: fact.category, label: fact.label }));
    if (!match) {
      added.push({ fact_id: fact.id, category: fact.category, label: fact.label });
      continue;
    }
    const fields = COMPARED_FIELDS.filter((k) => JSON.stringify(match.effective[k] ?? null) !== JSON.stringify(fact.value[k] ?? null));
    if (fields.length) {
      changed.push({
        fact_id: fact.id,
        category: fact.category,
        label: fact.label,
        fields: fields.map((k) => ({ field: k, before: match.effective[k] ?? null, after: fact.value[k] ?? null })),
        affected_reminder_ids: reminders.filter((r) => r.fact_id === match.id).map((r) => r.id),
      });
    }
  }
  const removed = before
    .filter((b) => !after.some((f) => identity({ category: f.category, label: f.label }) === identity(b)))
    .map((b) => ({
      category: b.category,
      label: b.label,
      affected_reminder_ids: reminders.filter((r) => r.fact_id === b.id).map((r) => r.id),
    }));
  return { compared_with_version: current.version, changed, added, removed };
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

export async function courseDashboard(body: Record<string, unknown>, deps: Deps) {
  const course = await ownedCourse(stringField(body, "course_id"), deps);
  const term = await termFor(course, deps);
  const documents = await deps.store.listDocuments([course.id]);
  const status = courseStatus(documents);
  const reminders = await deps.store.listReminders(course.id);
  const base = { course: courseDTO(course, term, documents), term_timezone: term.timezone };
  if (!status.current) return { ...base, current_document: null, facts: [], next: null, undated: [], reminders: [] };

  const corrections = await deps.store.listCorrections([status.current.id]);
  const facts = effectiveFacts(
    (await deps.store.listFacts(status.current.id)).filter((f) => f.review_state === "confirmed"),
    corrections,
  );
  const today = localDate(deps.now(), term.timezone);
  const upcoming = facts
    .filter((f) => DATED.has(f.category) && typeof f.effective.date === "string" && (f.effective.date as string) >= today)
    .sort((a, b) => `${a.effective.date}${a.effective.start_time ?? ""}`.localeCompare(`${b.effective.date}${b.effective.start_time ?? ""}`));
  const undated = facts.filter((f) => DATED.has(f.category) && !f.effective.date);

  return {
    ...base,
    current_document: documentDTO(status.current),
    pending_document: status.pending ? documentDTO(status.pending) : null,
    facts,
    next: upcoming[0] ?? null,
    undated,
    reminders: reminders.map(reminderDTO),
  };
}

// ---------------------------------------------------------------------------
// Reminders
// ---------------------------------------------------------------------------

export async function addReminder(body: Record<string, unknown>, deps: Deps) {
  const lead = stringField(body, "lead");
  if (lead !== "week_before" && lead !== "day_before" && lead !== "morning_of") throw invalid("Choose when to be reminded.");
  const { fact, document } = await editableFact(stringField(body, "fact_id"), deps, { allowReviewed: true });
  const course = (await deps.store.getCourse(document.course_id))!;
  const term = await termFor(course, deps);
  const current = courseStatus(await deps.store.listDocuments([course.id])).current;
  if (!current || current.id !== document.id) throw conflict("Reminders use the syllabus version you've reviewed.");
  if (fact.review_state !== "confirmed") throw conflict("Confirm this date before adding a reminder.");
  const [effective] = effectiveFacts([fact], await deps.store.listCorrections([document.id]));
  const reminder = buildReminder(course, term, effective, lead, deps.now());

  const existing = (await deps.store.listReminders(course.id)).find((r) => r.dedupe_key === reminder.dedupe_key);
  if (existing) return { reminder: reminderDTO(existing), duplicate: true };
  return { reminder: reminderDTO(await deps.store.insertReminder(reminder)), duplicate: false };
}

export async function deleteReminder(body: Record<string, unknown>, deps: Deps) {
  const reminder = await ownedReminder(stringField(body, "reminder_id"), deps);
  await deps.store.deleteReminder(reminder.id);
  return { deleted_reminder_ids: [reminder.id] };
}

/** After a date changed in a newer version: move the reminder to the new date, or remove it. */
export async function resolveReminder(body: Record<string, unknown>, deps: Deps) {
  const reminder = await ownedReminder(stringField(body, "reminder_id"), deps);
  if (stringField(body, "resolution") === "remove") {
    await deps.store.deleteReminder(reminder.id);
    return { deleted_reminder_ids: [reminder.id], reminder: null };
  }
  const course = (await deps.store.getCourse(reminder.course_id))!;
  const term = await termFor(course, deps);
  const current = courseStatus(await deps.store.listDocuments([course.id])).current;
  const oldFact = await deps.store.getFact(reminder.fact_id);
  if (!current || !oldFact) throw conflict("There's no reviewed date to move this reminder to.");
  const corrections = await deps.store.listCorrections([current.id, oldFact.document_id]);
  const [old] = effectiveFacts([oldFact], corrections);
  const candidates = effectiveFacts((await deps.store.listFacts(current.id)).filter((f) => f.review_state === "confirmed"), corrections);
  const match = candidates.find((f) => identity(f) === identity(old));
  if (!match || !match.effective.date) throw conflict("The new syllabus doesn't give a confirmed date for this. Remove the reminder instead.");
  const updated = buildReminder(course, term, match, reminder.lead, deps.now());
  const clash = (await deps.store.listReminders(course.id)).find((r) => r.dedupe_key === updated.dedupe_key && r.id !== reminder.id);
  if (clash) {
    await deps.store.deleteReminder(reminder.id);
    return { deleted_reminder_ids: [reminder.id], reminder: reminderDTO(clash) };
  }
  await deps.store.updateReminder(reminder.id, { ...updated, state: "active" });
  const refreshed = (await deps.store.listReminders(course.id)).find((r) => r.id === reminder.id)!;
  return { deleted_reminder_ids: [], reminder: reminderDTO(refreshed) };
}

/** Every active reminder, so the device can match its scheduled notifications. */
export async function listReminders(deps: Deps) {
  return { reminders: (await deps.store.listReminders(null)).filter((r) => r.state === "active").map(reminderDTO) };
}

export async function reminderIdsForDocuments(documentIds: string[], deps: Deps): Promise<string[]> {
  if (!documentIds.length) return [];
  const factIds = new Set<string>();
  for (const id of documentIds) for (const f of await deps.store.listFacts(id)) factIds.add(f.id);
  return (await deps.store.listReminders(null)).filter((r) => factIds.has(r.fact_id)).map((r) => r.id);
}

export function buildReminder(
  course: CourseRow,
  term: TermRow,
  fact: EffectiveFact,
  lead: ReminderRow["lead"],
  now: Date,
) {
  const date = fact.effective.date as string | null;
  if (!date) throw conflict("This item doesn't have a confirmed date.");
  const start = fact.effective.start_time as string | null;
  let fireDate = date;
  let fireTime = "09:00";
  if (lead === "week_before") fireDate = shiftDay(date, -7);
  if (lead === "day_before") fireDate = shiftDay(date, -1);
  if (lead === "morning_of") {
    fireTime = "08:00";
    if (start && start <= "08:30") fireTime = minusMinutes(start, 60);
  }
  const firesAt = zonedTimeToUTC(fireDate, fireTime, term.timezone);
  if (firesAt <= now) throw invalid("That reminder time has already passed.");

  const when = humanDate(date) + (start ? ` at ${humanTime(start)}` : "");
  return {
    course_id: course.id,
    fact_id: fact.id,
    lead,
    fires_at: firesAt.toISOString(),
    title: `${course.subject} ${course.number}: ${fact.label}`.slice(0, 200),
    body: `${capitalize(LEAD_TEXT[lead])}: ${when}. Check your course announcements for any changes.`.slice(0, 400),
    dedupe_key: `${course.id}|${identity(fact)}|${date}|${start ?? ""}|${lead}`,
  };
}

// ---------------------------------------------------------------------------
// Effective values: document facts with the student's corrections on top
// ---------------------------------------------------------------------------

export type EffectiveFact = FactRow & {
  effective: Record<string, unknown>;
  correction: { corrected: Record<string, unknown>; note: string | null; updated_at: string } | null;
};

export function effectiveFacts(facts: FactRow[], corrections: CorrectionRow[]): EffectiveFact[] {
  return facts.map((f) => {
    const c = corrections.find((x) => x.fact_id === f.id) ?? null;
    const effective: Record<string, unknown> = { ...f.value };
    if (c) {
      for (const [key, value] of Object.entries(c.corrected)) {
        if (key === "text") effective.summary = value;
        else effective[key] = value;
      }
    }
    return { ...f, effective, correction: c ? { corrected: c.corrected, note: c.note, updated_at: c.updated_at } : null };
  });
}

export function identity(fact: { category: string; label: string }): string {
  return `${fact.category}|${normalizeText(fact.label).replace(/[^a-z0-9]/g, "")}`;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function editableFact(id: string | null, deps: Deps, options: { allowReviewed?: boolean } = {}) {
  if (!id) throw new HandlerError(404, "SYLLABUS_FACT_NOT_FOUND", "Item not found.");
  const fact = await deps.store.getFact(id);
  if (!fact) throw new HandlerError(404, "SYLLABUS_FACT_NOT_FOUND", "Item not found.");
  const document = await ownedDocument(fact.document_id, deps);
  if (!options.allowReviewed && document.processing_state !== "review_needed") {
    throw conflict("This version has already been reviewed. Upload a new version to make changes.");
  }
  return { fact, document };
}

async function reviewableDocument(id: string | null, deps: Deps) {
  const document = await ownedDocument(id, deps);
  if (document.processing_state !== "review_needed") throw conflict("This version isn't waiting for review.");
  return document;
}

async function correctionFor(factId: string, documentId: string, deps: Deps) {
  return (await deps.store.listCorrections([documentId])).find((c) => c.fact_id === factId) ?? null;
}

async function ownedReminder(id: string | null, deps: Deps) {
  const reminder = id ? (await deps.store.listReminders(null)).find((r) => r.id === id) : undefined;
  if (!reminder) throw new HandlerError(404, "REMINDER_NOT_FOUND", "Reminder not found.");
  return reminder;
}

function reminderDTO(r: ReminderRow) {
  return { id: r.id, course_id: r.course_id, fact_id: r.fact_id, lead: r.lead, fires_at: r.fires_at, title: r.title, body: r.body, state: r.state };
}

function shiftDay(iso: string, days: number): string {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function minusMinutes(time: string, minutes: number): string {
  const [h, m] = time.split(":").map(Number);
  const total = Math.max(0, h * 60 + m - minutes);
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

/** The UTC instant of a wall-clock time in an IANA zone (handles DST). */
export function zonedTimeToUTC(day: string, time: string, timeZone: string): Date {
  const [y, mo, d] = day.split("-").map(Number);
  const [h, mi] = time.split(":").map(Number);
  const guess = Date.UTC(y, mo - 1, d, h, mi);
  const offset = (instant: number) => {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
    }).formatToParts(new Date(instant));
    const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
    return Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute")) - instant;
  };
  const first = guess - offset(guess);
  return new Date(guess - offset(first));
}

function humanDate(iso: string): string {
  return new Date(`${iso}T12:00:00Z`).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });
}

function humanTime(time: string): string {
  const [h, m] = time.split(":").map(Number);
  const suffix = h >= 12 ? "PM" : "AM";
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, "0")} ${suffix}`;
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function invalid(message: string) {
  return new HandlerError(400, "COURSES_INVALID", message);
}

function conflict(message: string) {
  return new HandlerError(409, "COURSES_CONFLICT", message);
}
