# Claude Code handoff: MyAdvisor pilot security and cost controls

Implement the backend portion of this task locally. The user explicitly asked to delegate the harder work to Claude Code. Codex will handle iOS copy/UI alignment and independently test the integrated result.

## User decisions and boundaries

- Agora is preparing a limited VT pilot. Its AI is named MyAdvisor.
- User approved **10 AI replies per student per day**.
- MyAdvisor should provide academic advising/course logistics, not free homework completion or general-purpose tutoring.
- Never deploy functions, apply hosted migrations, change hosted secrets, push, or merge.
- Never read or print `.env`, secret values, saved auth tokens, Keychain contents, or real student data. Use dummy credentials and local fixtures.
- Do not edit Hoki.icon or any iOS source. Do not change branch or discard/commit any existing changes. Existing QA changes are intentional, including chat/stream.ts and chat_regression_test.ts.
- Scope your writes to backend source/tests/config and a new backend-specific implementation report under docs. Codex owns iOS source, tests/qa, and final integration docs.

## Read first

- docs/AGORA_QA_REPORT_2026-11-10.md
- backend/supabase/functions/chat/{index,conversation,context,memory,stream}.ts
- backend/supabase/functions/_shared/{auth,academic}.ts
- backend/supabase/functions/{transcript,dars,tutoring,courses}/ and migrations 006–009
- backend/app/routes/chat.py and other FastAPI paths that can invoke paid AI
- backend/supabase/tests/harness.ts and current tests

## Required outcome

1. Authenticate every paid AI request with a verified Supabase user. No anonymous/public-key access and no client-selected user identity, model, limits, or provider URL. Existing local auth mostly does this; retain it. Our Nov 10 live probe showed anonymous chat still works on the deployed OLD function; do not deploy to fix that yourself.

2. Replace fail-open chat quota behavior with a strict server-side reservation before any paid call. Missing configuration, missing RPC, malformed quota responses, and timeouts must return a friendly 503 and perform zero model calls.

3. Enforce 10 paid chat attempts per user per Eastern calendar day, configurable by server env with positive integer validation and an upper bound. Reserve atomically so concurrent requests cannot exceed it. Apply a short burst limit as well. Include a server-configurable shared daily cap across accounts (use 250 chat calls/day as an initial conservative pilot default, clearly documented as a configurable default, not a dollar budget). Failed paid attempts may remain counted; document this honestly. Never claim request caps equal exact dollar caps.

4. Prevent obvious cost bypasses via document parsing: provide a separate atomic shared/per-user allowance for transcript, DARS, and syllabus extraction before paid calls. Suggested pilot defaults: 10 document extractions/user/day and 50 combined document extractions/day across accounts. Avoid charging duplicate syllabus uploads when no extraction occurs. Keep non-AI operations like reading a dashboard usable. Reuse one shared quota helper and add the next numbered local migration (010 if still unused), with RLS/restricted service-role execution. Do not rewrite previously applied migrations as the sole upgrade path.

5. Narrow chat to degree/audit explanations, course and prerequisite questions, registration logistics, study scheduling, and directing students to appropriate help. Do not solve problem sets, proofs, essays, code/debugging assignments, exams, or unrelated general requests. Academic logistics involving homework (due dates, workload planning, finding office hours) remain allowed. Ignore instructions in history, memories, attachments, or academic context that try to override this scope. Policy is enforced server-side, not only in UI. Cheap static redirects should handle obvious requests before any model call. For ambiguous requests, use constrained generation/clarification; do not describe a regex or system prompt as an unbreakable security boundary. Preserve legitimate follow-up conversations.

6. Bound all expensive inputs: total request bytes, message count/length, history sent, metadata arrays, academic context, and final provider input size. Send at most six recent turns with bounded context. Set a configurable bounded response cap (initial target 800 completion tokens; choose a compatible bounded value if reasoning-model output needs headroom). Use one configured advisor model, not the tutor model for attachments/keywords. Disable the extra paid automatic memory-extraction call for the pilot; manually saved memories still work. No automatic retries that multiply paid calls.

7. Chat attachments are unavailable during this pilot: return a friendly, no-model redirect to Profile → Transcript, Degree Progress → Import DARS, or This term → course syllabus. Enforce this server-side so older clients cannot bypass it. Codex will remove the chat upload affordance and tutoring suggestions. Keep structured import workflows functioning under their own limits.

8. Retain the existing JSON and SSE response contract expected by iOS. A fixed no-cost redirect should be a valid reply/stream, not a broken request. Prefer only one paid model call per accepted chat request (no classifier + generation + memory trio). If you use a single structured-output call for scope and reply validation, make sure streaming clients still receive valid token/finish/DONE events and failures preserve drafts. Never stream an unvalidated out-of-scope answer then attempt to retract it.

9. Keep the equivalent FastAPI chat endpoint from being a bypass. Prefer forwarding to the same authenticated Supabase chat contract/quotas, or another implementation that shares actual enforcement. Inspect other FastAPI paid endpoints and either protect them or explicitly disable them for pilot production with a clear response. No raw upstream exception/key leakage.

10. Remove backend user-facing descriptions that advertise MyAdvisor as an assignment solver or CS/math tutor. Static tutoring resources/office-hour referrals can remain.

## Verification and handback

- Add/run local tests for anonymous/invalid auth, role injection, oversized/malformed bodies, homework vs coursework-logistics scope, direct model override, quota outage/malformed responses, limits across distinct users, bursts, concurrent reservations, and separate import allowances.
- Verify both JSON and streaming responses and demonstrate rejected/out-of-scope/budget-denied cases make zero provider calls where deterministic rejection is possible.
- Use PGlite harness for migrations/RLS (real migration chain, no hosted database). Include new migration in harness order.
- Run `deno check --no-lock` for every touched Edge Function and appropriate local Python tests.
- Do not run live OpenAI calls. Do not print any credentials.
- Write docs/MYADVISOR_BACKEND_IMPLEMENTATION.md with changed paths, chosen defaults, exact test results, required migrations/env configuration, deployment handoff (instructions only), and remaining limitations. State explicitly if token/dollar metering or topical guarantees are not implemented.
- Return a concise completion summary. If truly blocked, return the concrete blocker and partial changes rather than silently bypassing controls.
