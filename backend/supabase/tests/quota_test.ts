// Paid-AI allowances (migration 010 + _shared/quota.ts). Local only: PGlite
// with the real migration chain, dummy credentials, no provider calls.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { quotaLimits, reserveQuota } from "../functions/_shared/quota.ts";
import { handleAction } from "../functions/courses/handler.ts";
import type { Deps } from "../functions/courses/handler.ts";
import type { Extractor } from "../functions/courses/extraction.ts";
import { buildPDF } from "./fixtures/make_qa_pdfs.ts";
import { QA_RECORDINGS, QA_V1_PAGES } from "./fixtures/qa_syllabi.ts";
import { asAnon, asUser, createTestDatabase, createUser, quotaRPCFetch, reserveAsServiceRole } from "./harness.ts";
import { PgliteStore } from "./store_pglite.ts";

const db = await createTestDatabase();
let seq = 0;
const newUser = () => createUser(db, `quota-${++seq}@vt.edu`);

const DUMMY_ENV: Record<string, string> = {
  SUPABASE_URL: "http://supabase.test",
  SUPABASE_SERVICE_ROLE_KEY: "dummy-service-role",
};
const envWith = (extra: Record<string, string> = {}) => (name: string) => ({ ...DUMMY_ENV, ...extra })[name];

function reserve(userId: string, kind: "chat" | "document", limits: [number, number, number, number]) {
  const [user, global, burst, window] = limits;
  return reserveAsServiceRole(db, {
    p_user_id: userId, p_kind: kind, p_user_daily_limit: user, p_global_daily_limit: global,
    p_burst_limit: burst, p_burst_window_seconds: window,
  }).then((rows) => rows[0] as Record<string, any>);
}

async function resetGlobal(kind: string) {
  await db.query("delete from public.ai_usage_global_daily where kind = $1", [kind]);
}

// MARK: - Database enforcement

Deno.test("quota db: 10 per student per day, then denied without counting", async () => {
  await resetGlobal("chat");
  const user = await newUser();
  for (let i = 1; i <= 10; i++) {
    const row = await reserve(user, "chat", [10, 250, 100, 60]);
    assertEquals([row.allowed, row.user_used], [true, i]);
  }
  const denied = await reserve(user, "chat", [10, 250, 100, 60]);
  assertEquals([denied.allowed, denied.reason, denied.user_used], [false, "user_daily", 10]);
  assert(denied.retry_after_seconds > 0 && denied.retry_after_seconds <= 25 * 3600);
  const again = await reserve(user, "chat", [10, 250, 100, 60]);
  assertEquals(again.user_used, 10, "denials must not increment");
});

Deno.test("quota db: one student's limit doesn't affect another; shared cap spans accounts", async () => {
  await resetGlobal("chat");
  const [a, b, c] = [await newUser(), await newUser(), await newUser()];
  for (let i = 0; i < 3; i++) assert((await reserve(a, "chat", [3, 5, 100, 60])).allowed);
  assertEquals((await reserve(a, "chat", [3, 5, 100, 60])).reason, "user_daily");
  assert((await reserve(b, "chat", [3, 5, 100, 60])).allowed);
  assert((await reserve(b, "chat", [3, 5, 100, 60])).allowed);
  const capped = await reserve(c, "chat", [3, 5, 100, 60]);
  assertEquals([capped.allowed, capped.reason, capped.global_used], [false, "global_daily", 5]);
  assertEquals((await reserve(c, "chat", [3, 5, 100, 60])).user_used, 0, "capped student was not charged");
});

Deno.test("quota db: burst limit, then the window resets", async () => {
  await resetGlobal("chat");
  const user = await newUser();
  for (let i = 0; i < 3; i++) assert((await reserve(user, "chat", [10, 250, 3, 60])).allowed);
  const burst = await reserve(user, "chat", [10, 250, 3, 60]);
  assertEquals([burst.allowed, burst.reason], [false, "burst"]);
  assert(burst.retry_after_seconds >= 1 && burst.retry_after_seconds <= 60);
  await db.query("update public.ai_usage_burst set window_started_at = now() - interval '61 seconds' where user_id = $1", [user]);
  const after = await reserve(user, "chat", [10, 250, 3, 60]);
  assertEquals([after.allowed, after.user_used], [true, 4]);
});

Deno.test("quota db: 30 parallel reservations never exceed the limit", async () => {
  await resetGlobal("chat");
  const user = await newUser();
  const rows = await Promise.all(Array.from({ length: 30 }, () => reserve(user, "chat", [10, 250, 100, 60])));
  assertEquals(rows.filter((r) => r.allowed).length, 10);
  const stored = await db.query<{ request_count: number }>(
    "select request_count from public.ai_usage_daily where user_id = $1 and kind = 'chat'", [user],
  );
  assertEquals(stored.rows[0].request_count, 10);
});

Deno.test("quota db: chat and document allowances are independent", async () => {
  await resetGlobal("chat");
  await resetGlobal("document");
  const user = await newUser();
  for (let i = 0; i < 2; i++) await reserve(user, "chat", [2, 250, 100, 60]);
  assertEquals((await reserve(user, "chat", [2, 250, 100, 60])).allowed, false);
  assertEquals((await reserve(user, "document", [10, 50, 100, 300])).allowed, true);
});

Deno.test("quota db: the day is the America/New_York calendar day; yesterday's usage doesn't count", async () => {
  await resetGlobal("chat");
  const user = await newUser();
  const today = (await db.query<{ d: string }>("select ((now() at time zone 'America/New_York')::date)::text as d")).rows[0].d;
  await db.query(
    "insert into public.ai_usage_daily (user_id, kind, usage_date, request_count) values ($1, 'chat', $2::date - 1, 10)",
    [user, today],
  );
  const row = await reserve(user, "chat", [10, 250, 100, 60]);
  assertEquals([row.allowed, row.user_used], [true, 1]);
  const stored = await db.query<{ d: string }>(
    "select usage_date::text as d from public.ai_usage_daily where user_id = $1 and request_count = 1", [user],
  );
  assertEquals(stored.rows[0].d, today);
  // retry_after for a daily denial points at the next Eastern midnight.
  for (let i = 0; i < 9; i++) await reserve(user, "chat", [10, 250, 100, 60]);
  const denied = await reserve(user, "chat", [10, 250, 100, 60]);
  const expected = (await db.query<{ s: number }>(
    "select ceil(extract(epoch from ((((now() at time zone 'America/New_York')::date + 1)::timestamp at time zone 'America/New_York') - now())))::int as s",
  )).rows[0].s;
  assert(Math.abs(denied.retry_after_seconds - expected) <= 2);
});

Deno.test("quota db: limits are validated in SQL too", async () => {
  const user = await newUser();
  for (const limits of [[0, 250, 5, 60], [10, 0, 5, 60], [10, 250, 0, 60], [10, 250, 5, 0], [1001, 250, 5, 60]] as const) {
    await assertRejects(() => reserve(user, "chat", [...limits] as [number, number, number, number]));
  }
  await assertRejects(() =>
    reserveAsServiceRole(db, { p_user_id: user, p_kind: "images", p_user_daily_limit: 1, p_global_daily_limit: 1, p_burst_limit: 1, p_burst_window_seconds: 1 })
  );
});

Deno.test("quota db: students can read only their own usage and can't change any of it", async () => {
  const [a, b] = [await newUser(), await newUser()];
  await reserve(a, "chat", [10, 250, 100, 60]);
  await reserve(b, "chat", [10, 250, 100, 60]);
  await asUser(db, a, async (tx) => {
    const own = await tx.query<{ user_id: string }>("select user_id from public.ai_usage_daily");
    assert(own.rows.length >= 1 && own.rows.every((r) => r.user_id === a));
  });
  const attempts = [
    "select * from public.reserve_ai_quota(auth.uid(), 'chat', 1000, 100000, 100, 1)",
    "update public.ai_usage_daily set request_count = 0",
    "delete from public.ai_usage_daily",
    "insert into public.ai_usage_daily (user_id, kind, usage_date) values (auth.uid(), 'chat', current_date + 1)",
    "select * from public.ai_usage_global_daily",
    "select * from public.ai_usage_burst",
    "update public.ai_usage_burst set request_count = 0",
  ];
  for (const sql of attempts) {
    await assertRejects(() => asUser(db, a, (tx) => tx.query(sql)), Error, undefined, sql);
  }
  for (const sql of ["select * from public.ai_usage_daily", "select * from public.reserve_ai_quota(gen_random_uuid(), 'chat', 1, 1, 1, 1)"]) {
    await assertRejects(() => asAnon(db, (tx) => tx.query(sql)), Error, undefined, sql);
  }
});

// MARK: - Edge helper: configuration and fail-closed behavior

Deno.test("quota helper: pilot defaults and server-side configuration", () => {
  assertEquals(quotaLimits("chat", () => undefined), { userDaily: 10, globalDaily: 250, burst: 5, burstWindowSeconds: 60 });
  assertEquals(quotaLimits("document", () => undefined), { userDaily: 10, globalDaily: 50, burst: 3, burstWindowSeconds: 300 });
  assertEquals(quotaLimits("chat", envWith({ MYADVISOR_CHAT_USER_DAILY_LIMIT: "25" }))?.userDaily, 25);
  for (const bad of ["abc", "0", "-1", "1.5", "1e3", "1001", " 10x"]) {
    assertEquals(quotaLimits("chat", envWith({ MYADVISOR_CHAT_USER_DAILY_LIMIT: bad })), null, bad);
  }
});

Deno.test("quota helper: allowed and denied decisions come from the database", async () => {
  await resetGlobal("document");
  const user = await newUser();
  const options = { env: envWith({ MYADVISOR_DOCUMENT_USER_DAILY_LIMIT: "2" }), fetch: quotaRPCFetch(db) };
  assertEquals((await reserveQuota(user, "document", options)).status, "allowed");
  assertEquals((await reserveQuota(user, "document", options)).status, "allowed");
  const denied = await reserveQuota(user, "document", options);
  assertEquals(denied.status === "denied" && denied.reason, "user_daily");
});

Deno.test("quota helper: fails closed on every uncertain path, without calling out when it can't", async () => {
  const user = crypto.randomUUID();
  let calls = 0;
  const counting = (response: () => Response | Promise<Response>): typeof fetch => () => {
    calls++;
    return Promise.resolve(response());
  };
  const cases: [string, Parameters<typeof reserveQuota>[2], boolean][] = [
    ["no service key", { env: (n) => (n === "SUPABASE_URL" ? "http://supabase.test" : undefined), fetch: counting(() => Response.json([])) }, false],
    ["no url", { env: (n) => (n === "SUPABASE_SERVICE_ROLE_KEY" ? "x" : undefined), fetch: counting(() => Response.json([])) }, false],
    ["invalid limit", { env: envWith({ MYADVISOR_CHAT_GLOBAL_DAILY_LIMIT: "lots" }), fetch: counting(() => Response.json([])) }, false],
    ["rpc missing", { env: envWith(), fetch: counting(() => Response.json({ code: "PGRST202" }, { status: 404 })) }, true],
    ["server error", { env: envWith(), fetch: counting(() => new Response("oops", { status: 500 })) }, true],
    ["not json", { env: envWith(), fetch: counting(() => new Response("<html>")) }, true],
    ["empty rows", { env: envWith(), fetch: counting(() => Response.json([])) }, true],
    ["two rows", { env: envWith(), fetch: counting(() => Response.json([okRow(), okRow()])) }, true],
    ["allowed as string", { env: envWith(), fetch: counting(() => Response.json([{ ...okRow(), allowed: "true" }])) }, true],
    ["unknown reason", { env: envWith(), fetch: counting(() => Response.json([{ ...okRow(), reason: "vip" }])) }, true],
    ["allowed but reason burst", { env: envWith(), fetch: counting(() => Response.json([{ ...okRow(), reason: "burst" }])) }, true],
    ["negative count", { env: envWith(), fetch: counting(() => Response.json([{ ...okRow(), user_used: -1 }])) }, true],
    ["network error", { env: envWith(), fetch: () => (calls++, Promise.reject(new TypeError("connection refused"))) }, true],
  ];
  for (const [label, options, expectsCall] of cases) {
    calls = 0;
    const decision = await reserveQuota(user, "chat", options);
    assertEquals(decision.status, "unavailable", label);
    assertEquals(calls, expectsCall ? 1 : 0, label);
  }
  // Timeout: a database that never answers.
  const hung: typeof fetch = (_input, init) =>
    new Promise((_resolve, reject) => init?.signal?.addEventListener("abort", () => reject(init.signal!.reason)));
  assertEquals((await reserveQuota(user, "chat", { env: envWith(), fetch: hung, timeoutMs: 50 })).status, "unavailable");
});

function okRow() {
  return { allowed: true, reason: "ok", user_used: 1, user_limit: 10, global_used: 1, global_limit: 250, retry_after_seconds: 0 };
}

// MARK: - Syllabus extraction allowance

const recorded = (calls: { n: number }): Extractor => (pages) => {
  calls.n++;
  const id = pages.map((p) => p.text).join("\n").match(/QA-FIXTURE-ID:\s*(\S+)/)?.[1];
  return Promise.resolve(id && QA_RECORDINGS[id] ? { ok: true, data: structuredClone(QA_RECORDINGS[id]), model: "qa" } : { ok: false, code: "QA_NO_RECORDING" });
};

function syllabusDeps(userId: string, calls: { n: number }, env: Record<string, string> = {}): Deps {
  return {
    store: new PgliteStore(db, userId),
    now: () => new Date("2026-11-09T15:00:00Z"),
    userId,
    extractor: recorded(calls),
    reserveExtraction: () => reserveQuota(userId, "document", { env: envWith(env), fetch: quotaRPCFetch(db) }),
  };
}

async function addCourse(userId: string, deps: Deps) {
  const result = await handleAction("add_course", {
    term_key: "spring-2027", subject: "CS", number: "2114", section_code: "99999",
    instructor_name: "Dr. Test Instructor", title: "Software Design and Data Structures",
  }, deps);
  assertEquals(result.status, 200, JSON.stringify(result.body));
  return (result.body as any).course.id as string;
}

function upload(courseId: string) {
  return {
    action: "upload_syllabus", course_id: courseId, text_method: "pdf_text", pages: JSON.stringify(QA_V1_PAGES),
    file: new File([buildPDF(QA_V1_PAGES)], "syllabus.pdf", { type: "application/pdf" }),
  };
}

async function documentCount(userId: string): Promise<number> {
  const r = await db.query<{ request_count: number }>(
    "select coalesce(sum(request_count), 0)::int as request_count from public.ai_usage_daily where user_id = $1 and kind = 'document'", [userId],
  );
  return r.rows[0].request_count;
}

Deno.test("syllabus quota: an extraction counts once; an identical re-upload is free", async () => {
  await resetGlobal("document");
  const user = await newUser();
  const calls = { n: 0 };
  const deps = syllabusDeps(user, calls);
  const course = await addCourse(user, deps);
  const first = await handleAction("upload_syllabus", upload(course), deps);
  assertEquals(first.status, 200, JSON.stringify(first.body));
  const again = await handleAction("upload_syllabus", upload(course), deps);
  assertEquals((again.body as any).duplicate, true);
  assertEquals(calls.n, 1);
  assertEquals(await documentCount(user), 1);
});

Deno.test("syllabus quota: denied uploads store nothing and make no AI call", async () => {
  await resetGlobal("document");
  const user = await newUser();
  const calls = { n: 0 };
  const deps = syllabusDeps(user, calls, { MYADVISOR_DOCUMENT_USER_DAILY_LIMIT: "1" });
  const course = await addCourse(user, deps);
  await db.query(
    "insert into public.ai_usage_daily (user_id, kind, usage_date, request_count) values ($1, 'document', (now() at time zone 'America/New_York')::date, 1)",
    [user],
  );
  const denied = await handleAction("upload_syllabus", upload(course), deps);
  assertEquals(denied.status, 429);
  assertEquals((denied.body as any).detail.code, "SYLLABUS_RATE_LIMITED");
  assertEquals(calls.n, 0);
  const docs = await db.query("select 1 from public.syllabus_documents where user_id = $1", [user]);
  assertEquals(docs.rows.length, 0);
  const files = await db.query("select 1 from storage.objects where name like $1", [`${user}/%`]);
  assertEquals(files.rows.length, 0);
});

Deno.test("syllabus quota: an outage blocks extraction with a friendly 503", async () => {
  const user = await newUser();
  const calls = { n: 0 };
  const deps: Deps = {
    ...syllabusDeps(user, calls),
    reserveExtraction: () => reserveQuota(user, "document", { env: envWith(), fetch: () => Promise.resolve(new Response("", { status: 503 })) }),
  };
  const course = await addCourse(user, deps);
  const result = await handleAction("upload_syllabus", upload(course), deps);
  assertEquals(result.status, 503);
  assertEquals((result.body as any).detail.code, "SYLLABUS_TEMPORARILY_UNAVAILABLE");
  assertEquals(calls.n, 0);
});

Deno.test("document quota: pilot defaults allow 10 per student and 50 across the pilot", async () => {
  await resetGlobal("document");
  const options = { env: envWith({ MYADVISOR_DOCUMENT_BURST_LIMIT: "100" }), fetch: quotaRPCFetch(db) };
  const users = await Promise.all(Array.from({ length: 6 }, () => newUser()));
  const results: string[] = [];
  for (const user of users) {
    for (let i = 0; i < 11; i++) {
      const d = await reserveQuota(user, "document", options);
      results.push(d.status === "denied" ? d.reason : d.status);
    }
  }
  assertEquals(results.filter((r) => r === "allowed").length, 50);
  assertEquals(results.slice(0, 11).filter((r) => r === "user_daily").length, 1);
  assert(results.includes("global_daily"));
});
