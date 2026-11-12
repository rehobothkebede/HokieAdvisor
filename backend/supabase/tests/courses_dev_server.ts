// LOCAL QA SERVER: never deploy. Serves the courses edge function's real HTTP
// layer and handler on 127.0.0.1, backed by an in-memory Postgres (PGlite)
// with the project's migrations, so the iOS app can be exercised in the
// simulator without touching hosted Supabase. Data disappears on exit.
//
//   deno run -A backend/supabase/tests/courses_dev_server.ts
//
// Then launch a Debug build with:
//   -AgoraCoursesEndpoint http://127.0.0.1:8787/functions/v1/courses
//   -AgoraCoursesToken qa-token-student
//
// Two isolated test accounts exist: qa-token-student and qa-token-other.
// QA_NOW=2026-11-09T15:00:00Z pins the clock.

import { errorResponse } from "../functions/_shared/academic.ts";
import type { Extractor } from "../functions/courses/extraction.ts";
import { handleHTTP } from "../functions/courses/http.ts";
import { QA_RECORDINGS } from "./fixtures/qa_syllabi.ts";
import { reserveQuota } from "../functions/_shared/quota.ts";
import { createTestDatabase, createUser, quotaRPCFetch } from "./harness.ts";
import { PgliteStore } from "./store_pglite.ts";

// No model calls locally: synthetic QA syllabi carry a fixture ID, and the
// recorded model output for that ID is returned. Anything else fails visibly.
const recordedExtractor: Extractor = (pages) => {
  const id = pages.map((p) => p.text).join("\n").match(/QA-FIXTURE-ID:\s*(\S+)/)?.[1];
  const data = id ? QA_RECORDINGS[id] : undefined;
  return Promise.resolve(data ? { ok: true, data: structuredClone(data), model: "qa-recorded" } : { ok: false, code: "QA_NO_RECORDING" });
};

const db = await createTestDatabase();
const tokens = new Map<string, string>([
  ["qa-token-student", await createUser(db, "qa-student@vt.edu")],
  ["qa-token-other", await createUser(db, "qa-other@vt.edu")],
]);
const pinnedNow = Deno.env.get("QA_NOW");

const port = Number(Deno.env.get("PORT") ?? 8787);
Deno.serve({ hostname: "127.0.0.1", port }, (req) => {
  const url = new URL(req.url);
  if (url.pathname !== "/functions/v1/courses") return new Response("Not found", { status: 404 });
  return handleHTTP(req, {
    authenticate: async (req) => {
      const token = (req.headers.get("authorization") ?? "").replace(/^bearer\s+/i, "");
      const userId = tokens.get(token);
      return userId ? { userId, token } : errorResponse("AUTH_REQUIRED", "Unknown QA token.", 401);
    },
    deps: ({ userId }) => ({
      store: new PgliteStore(db, userId),
      now: () => (pinnedNow ? new Date(pinnedNow) : new Date()),
      userId,
      extractor: recordedExtractor,
      // The real reserve_ai_quota from migration 010, with pilot defaults.
      reserveExtraction: () =>
        reserveQuota(userId, "document", {
          env: (name) => ({ SUPABASE_URL: "http://qa.local", SUPABASE_SERVICE_ROLE_KEY: "qa-only" } as Record<string, string>)[name] ?? Deno.env.get(name),
          fetch: quotaRPCFetch(db),
        }),
    }),
  });
});
console.log(`Courses QA server on http://127.0.0.1:${port}/functions/v1/courses`);
