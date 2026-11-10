// Stage 1 tests: registration reference data, RLS on reference tables, and
// the handler's term/deadline logic. Run:
//   deno test -A backend/supabase/tests/registration_test.ts

import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { asAnon, asUser, createTestDatabase, createUser } from "./harness.ts";
import { PgliteStore } from "./store_pglite.ts";
import { currentTerm, handleAction, localDate } from "../functions/courses/handler.ts";

const db = await createTestDatabase("007_course_companion_registration.sql");
const student = await createUser(db, "student@vt.edu");

const noExtractor = () => Promise.resolve({ ok: false as const, code: "UNUSED" });

function deps(nowISO: string, userId = student) {
  return { store: new PgliteStore(db, userId), now: () => new Date(nowISO), userId, extractor: noExtractor };
}

Deno.test("every seeded deadline cites a published official source", async () => {
  const rows = await asUser(db, student, (tx) =>
    tx.query<{ n: number }>(
      `select count(*)::int as n from public.term_deadlines d
         left join public.official_sources s on s.id = d.source_id and s.status = 'published'
        where s.id is null`,
    ));
  assertEquals(rows.rows[0].n, 0);
});

Deno.test("guide points cite sources that exist", async () => {
  const rows = await asUser(db, student, (tx) =>
    tx.query<{ n: number }>(
      `select count(*)::int as n
         from public.registration_guide_topics t,
              jsonb_array_elements(coalesce(t.points, '[]') || coalesce(t.comparison, '[]')) p
        where not exists (select 1 from public.official_sources s where s.id = (p ->> 'source_id')::uuid)`,
    ));
  assertEquals(rows.rows[0].n, 0);
});

Deno.test("anonymous callers can't read registration reference data", async () => {
  await assertRejects(() => asAnon(db, (tx) => tx.query("select * from public.term_deadlines")));
});

Deno.test("students can't write reference data", async () => {
  await assertRejects(() =>
    asUser(db, student, (tx) =>
      tx.query("update public.term_deadlines set starts_on = '2027-01-01'")
    )
  );
  await assertRejects(() =>
    asUser(db, student, (tx) =>
      tx.query(
        `insert into public.official_sources (institution_id, kind, title, publisher, url, checked_on, status)
         values ('00000000-0000-4000-a000-000000000001', 'other', 'x', 'x', 'https://example.com', now(), 'published')`,
      )
    )
  );
});

Deno.test("staged rows stay hidden from students", async () => {
  await db.query(
    `insert into public.term_deadlines (institution_id, term_id, kind, audience, label, starts_on, source_id, status)
     values ('00000000-0000-4000-a000-000000000001', '00000000-0000-4000-b000-000000000202',
             'classes_end', 'graduate', 'staged row', '2027-05-05', '00000000-0000-4000-b000-000000000102', 'staged')`,
  );
  const visible = await asUser(db, student, (tx) =>
    tx.query("select 1 from public.term_deadlines where label = 'staged row'"));
  assertEquals(visible.rows.length, 0);
  await db.query("delete from public.term_deadlines where label = 'staged row'");
});

Deno.test("local date uses the term's time zone, not UTC", () => {
  // 02:00 UTC on Nov 10 is still Nov 9 in Blacksburg.
  assertEquals(localDate(new Date("2026-11-10T02:00:00Z"), "America/New_York"), "2026-11-09");
});

Deno.test("current term: in session, between terms, and after the last term", async () => {
  const store = new PgliteStore(db, student);
  const inst = (await store.institutionForUser())!;
  const terms = await store.listTerms(inst.id);
  assertEquals(currentTerm(terms, new Date("2026-11-09T15:00:00Z"))?.term_key, "fall-2026");
  assertEquals(currentTerm(terms, new Date("2026-12-28T15:00:00Z"))?.term_key, "spring-2027");
  assertEquals(currentTerm(terms, new Date("2027-08-01T15:00:00Z"))?.term_key, "spring-2027");
});

Deno.test("overview on 2026-11-09 points registration at Spring 2027 Add/Drop", async () => {
  const result = await handleAction("overview", {}, deps("2026-11-09T15:00:00Z"));
  assertEquals(result.status, 200);
  const body = result.body as any;
  assertEquals(body.supported, true);
  assertEquals(body.institution.slug, "vt");
  assertEquals(body.current_term_key, "fall-2026");
  assertEquals(body.registration.term_key, "spring-2027");
  assertEquals(body.registration.deadline.label, "Add/Drop Begins");
  assertEquals(body.registration.deadline.starts_on, "2026-12-07");
});

Deno.test("registration guide marks past deadlines and never offers in-app registration", async () => {
  const result = await handleAction("registration_guide", { term_key: "spring-2027" }, deps("2026-11-09T15:00:00Z"));
  const body = result.body as any;
  assertEquals(body.term.term_key, "spring-2027");
  assertEquals(body.can_register_in_app, false);
  const request = body.deadlines.find((d: any) => d.kind === "course_request");
  assertEquals(request.state, "past"); // Oct 20 - Nov 3, 2026
  const addDrop = body.deadlines.find((d: any) => d.kind === "add_drop_begins");
  assertEquals(addDrop.state, "upcoming");
  assert(body.topics.some((t: any) => t.topic === "drop_vs_withdraw" && t.comparison.length === 4));
  assert(body.sources.every((s: any) => s.url.startsWith("https://") && s.checked_on === "2026-11-09"));
});

Deno.test("unknown terms and actions return clear errors", async () => {
  const term = await handleAction("registration_guide", { term_key: "fall-1999" }, deps("2026-11-09T15:00:00Z"));
  assertEquals(term.status, 404);
  const action = await handleAction("nope", {}, deps("2026-11-09T15:00:00Z"));
  assertEquals(action.status, 400);
});

Deno.test("a student with no active institution gets 'not supported', not VT data", async () => {
  const other = await createUser(db, "someone@example.com");
  await db.query("update public.profiles set institution_id = null where id = $1", [other]);
  const result = await handleAction("overview", {}, deps(new Date().toISOString(), other));
  assertEquals((result.body as any).supported, false);
  const guide = await handleAction("registration_guide", {}, deps(new Date().toISOString(), other));
  assertEquals(guide.status, 404);
});
