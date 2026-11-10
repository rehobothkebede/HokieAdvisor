// Stage 3 tests: review, corrections, updated syllabi, the dashboard, and
// reminders.   deno test -A backend/supabase/tests/review_test.ts

import { assert, assertEquals, assertFalse, assertRejects } from "jsr:@std/assert@1";
import type { Extractor, RawExtraction } from "../functions/courses/extraction.ts";
import { type Deps, handleAction } from "../functions/courses/handler.ts";
import { zonedTimeToUTC } from "../functions/courses/review.ts";
import { QA_RECORDINGS, QA_V1_EXTRACTION, QA_V1_PAGES, QA_V2_PAGES } from "./fixtures/qa_syllabi.ts";
import { buildPDF } from "./fixtures/make_qa_pdfs.ts";
import { asUser, createTestDatabase, createUser } from "./harness.ts";
import { fileBytes, PgliteStore } from "./store_pglite.ts";

const db = await createTestDatabase();
const NOW = new Date("2026-11-09T15:00:00Z");

const recorded: Extractor = (pages) => {
  const id = pages.map((p) => p.text).join("\n").match(/QA-FIXTURE-ID:\s*(\S+)/)?.[1];
  return Promise.resolve(id && QA_RECORDINGS[id] ? { ok: true, data: structuredClone(QA_RECORDINGS[id]), model: "qa" } : { ok: false, code: "NONE" });
};

function deps(userId: string, extractor: Extractor = recorded): Deps {
  return { store: new PgliteStore(db, userId), now: () => NOW, userId, extractor };
}

async function call(userId: string, action: string, body: Record<string, unknown> = {}, extractor?: Extractor) {
  return await handleAction(action, { action, ...body }, deps(userId, extractor));
}

async function ok(userId: string, action: string, body: Record<string, unknown> = {}, extractor?: Extractor): Promise<any> {
  const result = await call(userId, action, body, extractor);
  assertEquals(result.status, 200, `${action}: ${JSON.stringify(result.body)}`);
  return result.body;
}

async function setup(userId: string, section: string, pages = QA_V1_PAGES, extractor?: Extractor) {
  const { course } = await ok(userId, "add_course", {
    term_key: "spring-2027", subject: "CS", number: "2114", section_code: section, instructor_name: "Dr. Test Instructor",
  });
  const upload = await ok(userId, "upload_syllabus", {
    course_id: course.id, text_method: "pdf_text", pages: JSON.stringify(pages),
    file: new File([buildPDF(pages)], "syllabus.pdf", { type: "application/pdf" }),
  }, extractor);
  return { course, document: upload.document, facts: upload.facts as any[] };
}

async function upload(userId: string, courseId: string, pages: typeof QA_V1_PAGES) {
  return await ok(userId, "upload_syllabus", {
    course_id: courseId, text_method: "pdf_text", pages: JSON.stringify(pages),
    file: new File([buildPDF(pages)], "syllabus-v2.pdf", { type: "application/pdf" }),
  });
}

const byLabel = (facts: any[], category: string, label: string) => facts.find((f) => f.category === category && f.label === label);

/** Confirms everything confirmable, rejects the unsupported invented fact. */
async function reviewAll(userId: string, documentId: string) {
  const { facts } = await ok(userId, "get_document", { document_id: documentId });
  await ok(userId, "confirm_unflagged", { document_id: documentId });
  for (const f of facts) {
    const decision = f.evidence === "not_found" ? "reject" : "confirm";
    const current = (await ok(userId, "get_document", { document_id: documentId })).facts.find((x: any) => x.id === f.id);
    if (current.review_state === "pending") await ok(userId, "review_fact", { fact_id: f.id, decision });
  }
  return await ok(userId, "complete_review", { document_id: documentId });
}

// ---------------------------------------------------------------------------

Deno.test("review: bulk confirm skips dates and flagged items; finishing needs every item decided", async () => {
  const alice = await createUser(db, "a1@vt.edu");
  const { document, facts } = await setup(alice, "10001");
  const { confirmed } = await ok(alice, "confirm_unflagged", { document_id: document.id });
  const confirmedFacts = facts.filter((f) => confirmed.includes(f.id));
  assert(confirmedFacts.length > 0);
  assert(confirmedFacts.every((f) => f.issues.length === 0 && !f.value.date && f.category !== "exam"));
  assertFalse(confirmed.includes(byLabel(facts, "exam", "Midterm Exam").id));

  const early = await call(alice, "complete_review", { document_id: document.id });
  assertEquals(early.status, 409);
});

Deno.test("review: an unsupported fact can't be confirmed, even directly in the database", async () => {
  const alice = await createUser(db, "a2@vt.edu");
  const { facts } = await setup(alice, "10002");
  const invented = byLabel(facts, "assignment_deadline", "Project 1");
  assertEquals((await call(alice, "review_fact", { fact_id: invented.id, decision: "confirm" })).status, 409);
  await assertRejects(() =>
    asUser(db, alice, (tx) => tx.query("update public.syllabus_facts set review_state = 'confirmed' where id = $1", [invented.id]))
  );
  // Correcting it is allowed; the student's value is then used, labeled as theirs.
  await ok(alice, "correct_fact", { fact_id: invented.id, corrected: { date: "2027-02-12" }, note: "Per Canvas" });
  const after = (await ok(alice, "get_document", { document_id: invented.document_id })).facts.find((f: any) => f.id === invented.id);
  assertEquals(after.review_state, "confirmed");
});

Deno.test("corrections stay separate; the document's facts are never edited", async () => {
  const alice = await createUser(db, "a3@vt.edu");
  const { document, facts } = await setup(alice, "10003");
  const office = byLabel(facts, "office_hours", "Office hours");
  await ok(alice, "correct_fact", { fact_id: office.id, corrected: { location: "Room 202" }, note: "Moved, per email" });

  const stored = await db.query<{ value: any }>("select value from public.syllabus_facts where id = $1", [office.id]);
  assertEquals(stored.rows[0].value.location, "Room 101 Example Hall");
  const correction = await db.query<{ corrected: any }>("select corrected from public.syllabus_fact_corrections where fact_id = $1", [office.id]);
  assertEquals(correction.rows[0].corrected, { location: "Room 202" });

  await reviewAll(alice, document.id);
  const dash = await ok(alice, "course_dashboard", { course_id: document.course_id });
  const shown = dash.facts.find((f: any) => f.id === office.id);
  assertEquals(shown.effective.location, "Room 202");
  assertEquals(shown.value.location, "Room 101 Example Hall"); // original stays visible
  assert(shown.correction);

  // Students can't rewrite extracted content directly either.
  await assertRejects(() =>
    asUser(db, alice, (tx) => tx.query("update public.syllabus_facts set value = '{}'::jsonb where id = $1", [office.id]))
  );
});

Deno.test("dashboard: only confirmed facts; next confirmed date; 'Week 6' stays undated", async () => {
  const alice = await createUser(db, "a4@vt.edu");
  const { course, document } = await setup(alice, "10004");
  const before = await ok(alice, "course_dashboard", { course_id: course.id });
  assertEquals(before.current_document, null); // nothing until reviewed
  await reviewAll(alice, document.id);
  const dash = await ok(alice, "course_dashboard", { course_id: course.id });
  assertEquals(dash.course.status, "ready");
  assertEquals(dash.next.label, "Midterm Exam");
  assertEquals(dash.next.effective.date, "2027-03-04");
  assert(dash.undated.some((f: any) => f.label === "Quiz 3"));
  assertFalse(dash.facts.some((f: any) => f.label === "Project 1")); // rejected
  assert(dash.facts.every((f: any) => f.review_state === "confirmed"));
});

Deno.test("reminders: confirmed dates only, no duplicates, correct time zone", async () => {
  const alice = await createUser(db, "a5@vt.edu");
  const { course, document, facts } = await setup(alice, "10005");
  const midterm = byLabel(facts, "exam", "Midterm Exam");
  assertEquals((await call(alice, "add_reminder", { fact_id: midterm.id, lead: "day_before" })).status, 409); // not reviewed yet
  await assertRejects(() =>
    asUser(db, alice, (tx) =>
      tx.query(
        `insert into public.course_reminders (user_id, course_id, fact_id, lead, fires_at, title, body, dedupe_key)
         values ($1, $2, $3, 'day_before', now() + interval '1 day', 't', 'b', 'k')`,
        [alice, course.id, midterm.id],
      )
    )
  );

  await reviewAll(alice, document.id);
  const first = await ok(alice, "add_reminder", { fact_id: midterm.id, lead: "day_before" });
  // 9:00 a.m. Eastern on Mar 3, 2027 (before DST) is 14:00 UTC.
  assertEquals(new Date(first.reminder.fires_at).toISOString(), "2027-03-03T14:00:00.000Z");
  const again = await ok(alice, "add_reminder", { fact_id: midterm.id, lead: "day_before" });
  assertEquals(again.duplicate, true);
  assertEquals(again.reminder.id, first.reminder.id);
  const count = await db.query<{ n: number }>("select count(*)::int as n from public.course_reminders where user_id = $1", [alice]);
  assertEquals(count.rows[0].n, 1);
  const { reminders } = await ok(alice, "list_reminders");
  assertEquals(reminders.length, 1);
});

Deno.test("updated syllabus: confirmed date isn't silently replaced; reminder must be reconfirmed", async () => {
  const alice = await createUser(db, "a6@vt.edu");
  const { course, document, facts } = await setup(alice, "10006");
  await reviewAll(alice, document.id);
  const midterm = byLabel(facts, "exam", "Midterm Exam");
  const { reminder } = await ok(alice, "add_reminder", { fact_id: midterm.id, lead: "day_before" });

  const v2 = await upload(alice, course.id, QA_V2_PAGES);
  assertEquals(v2.document.version, 2);
  const pendingDash = await ok(alice, "course_dashboard", { course_id: course.id });
  assertEquals(pendingDash.course.status, "update_available");
  assertEquals(pendingDash.next.effective.date, "2027-03-04"); // still the confirmed v1 date

  const detail = await ok(alice, "get_document", { document_id: v2.document.id });
  const change = detail.changes.changed.find((c: any) => c.label === "Midterm Exam");
  assertEquals(change.fields.find((f: any) => f.field === "date"), { field: "date", before: "2027-03-04", after: "2027-03-09" });
  assertEquals(change.affected_reminder_ids, [reminder.id]);

  const done = await reviewAll(alice, v2.document.id);
  assertEquals(done.reminders_needing_reconfirm, [reminder.id]);
  assertEquals((await ok(alice, "list_reminders")).reminders.length, 0); // not scheduled until reconfirmed

  const resolved = await ok(alice, "resolve_reminder", { reminder_id: reminder.id, resolution: "update" });
  assertEquals(resolved.reminder.state, "active");
  assertEquals(new Date(resolved.reminder.fires_at).toISOString(), "2027-03-08T14:00:00.000Z");
  const dash = await ok(alice, "course_dashboard", { course_id: course.id });
  assertEquals(dash.next.effective.date, "2027-03-09");
});

Deno.test("updated syllabus: reminders for unchanged dates carry over", async () => {
  const alice = await createUser(db, "a7@vt.edu");
  const { course, document, facts } = await setup(alice, "10007");
  await reviewAll(alice, document.id);
  const { reminder } = await ok(alice, "add_reminder", { fact_id: byLabel(facts, "exam", "Midterm Exam").id, lead: "week_before" });
  // Same content, different file (a reformatted copy).
  const reformatted = QA_V1_PAGES.map((p) => ({ ...p, text: p.text + "\n(revised formatting)" }));
  const v2 = await upload(alice, course.id, reformatted);
  const done = await reviewAll(alice, v2.document.id);
  assertEquals(done.reminders_needing_reconfirm, []);
  const { reminders } = await ok(alice, "list_reminders");
  assertEquals(reminders.map((r: any) => r.id), [reminder.id]);
  const moved = await db.query<{ document_id: string }>(
    "select f.document_id from public.course_reminders r join public.syllabus_facts f on f.id = r.fact_id where r.id = $1",
    [reminder.id],
  );
  assertEquals(moved.rows[0].document_id, v2.document.id);
});

Deno.test("another term's syllabus: its dates can't be confirmed and review can't finish", async () => {
  const alice = await createUser(db, "a8@vt.edu");
  const fallPages = QA_V1_PAGES.map((p) => ({ ...p, text: p.text.replace("Spring 2027", "Fall 2025") }));
  const fallExtractor: Extractor = () => {
    const raw: RawExtraction = structuredClone(QA_V1_EXTRACTION);
    raw.stated_identity.term = { value: "Fall 2025", excerpt: "Fall 2025 - CRN 99999", page: 1 };
    raw.stated_identity.section = { value: "CRN 99999", excerpt: "Fall 2025 - CRN 99999", page: 1 };
    return Promise.resolve({ ok: true, data: raw, model: "qa" });
  };
  const { document, facts } = await setup(alice, "10008", fallPages, fallExtractor);
  assert(document.findings.some((f: any) => f.code === "term_mismatch"));
  const midterm = byLabel(facts, "exam", "Midterm Exam");
  assertEquals((await call(alice, "review_fact", { fact_id: midterm.id, decision: "confirm" })).status, 409);
  await assertRejects(() =>
    asUser(db, alice, (tx) => tx.query("update public.syllabus_facts set review_state = 'confirmed' where id = $1", [midterm.id]))
  );
  assertEquals((await call(alice, "correct_fact", { fact_id: midterm.id, corrected: { date: "2027-03-04" } })).status, 409);
  assertEquals((await call(alice, "complete_review", { document_id: document.id })).status, 409);
});

Deno.test("access: another student can't review, correct, or add reminders to Alice's syllabus", async () => {
  const alice = await createUser(db, "a9@vt.edu");
  const bob = await createUser(db, "b9@vt.edu");
  const { course, document, facts } = await setup(alice, "10009");
  const office = byLabel(facts, "office_hours", "Office hours");
  for (const [action, body] of [
    ["review_fact", { fact_id: office.id, decision: "confirm" }],
    ["correct_fact", { fact_id: office.id, corrected: { location: "X" } }],
    ["confirm_unflagged", { document_id: document.id }],
    ["complete_review", { document_id: document.id }],
    ["course_dashboard", { course_id: course.id }],
    ["add_reminder", { fact_id: office.id, lead: "day_before" }],
  ] as const) {
    assertEquals((await call(bob, action, body)).status, 404, action);
  }
  await asUser(db, bob, (tx) => tx.query("update public.syllabus_facts set review_state = 'rejected' where id = $1", [office.id]));
  const unchanged = await db.query<{ review_state: string }>("select review_state from public.syllabus_facts where id = $1", [office.id]);
  assertEquals(unchanged.rows[0].review_state, "pending");
  await assertRejects(() =>
    asUser(db, bob, (tx) =>
      tx.query(`insert into public.syllabus_fact_corrections (user_id, fact_id, corrected) values ($1, $2, '{}')`, [bob, office.id])
    )
  );
});

Deno.test("deletion: deleting a reviewed version removes its corrections and reminders too", async () => {
  const alice = await createUser(db, "a10@vt.edu");
  const { course, document, facts } = await setup(alice, "10010");
  await ok(alice, "correct_fact", { fact_id: byLabel(facts, "office_hours", "Office hours").id, corrected: { location: "Room 9" } });
  await reviewAll(alice, document.id);
  const { reminder } = await ok(alice, "add_reminder", { fact_id: byLabel(facts, "exam", "Midterm Exam").id, lead: "day_before" });

  const result = await ok(alice, "delete_document", { document_id: document.id });
  assertEquals(result.deleted_reminder_ids, [reminder.id]);
  const left = await db.query<{ n: number }>(
    `select (select count(*)::int from public.course_reminders where user_id = $1)
          + (select count(*)::int from public.syllabus_fact_corrections where user_id = $1)
          + (select count(*)::int from public.syllabus_facts where user_id = $1) as n`,
    [alice],
  );
  assertEquals(left.rows[0].n, 0);
  assertFalse([...fileBytes.keys()].some((k) => k.startsWith(`${alice}/`)));
  assertEquals((await ok(alice, "course_dashboard", { course_id: course.id })).course.status, "needed");
});

Deno.test("time zones: reminder times follow daylight saving time", () => {
  assertEquals(zonedTimeToUTC("2027-03-03", "09:00", "America/New_York").toISOString(), "2027-03-03T14:00:00.000Z");
  assertEquals(zonedTimeToUTC("2027-03-15", "09:00", "America/New_York").toISOString(), "2027-03-15T13:00:00.000Z");
  assertEquals(zonedTimeToUTC("2026-11-02", "08:00", "America/New_York").toISOString(), "2026-11-02T13:00:00.000Z");
});
