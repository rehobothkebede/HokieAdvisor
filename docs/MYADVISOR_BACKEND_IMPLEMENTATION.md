# MyAdvisor pilot: backend security and usage controls

Two stages: usage controls (below), then pilot scope and input bounds (see "Stage 2"). Status: both implemented and tested locally on 2026-11-11. **Nothing is deployed.** No migration has been applied to hosted Supabase, no hosted secret was changed, and nothing was committed or pushed.

## What is enforced (once deployed)

| Control | Where | Default |
|---|---|---|
| Verified Supabase user before any paid call (anon key rejected) | `_shared/auth.ts` (unchanged), `app/services/ai_guard.py` | always |
| MyAdvisor chat, per student per day | `reserve_ai_quota` (migration 010) | 10, resets at midnight America/New_York |
| MyAdvisor chat, shared across the pilot per day | same | 250 |
| Chat burst, per student | same | 5 per 60 s |
| Document extraction (transcript + DARS + syllabus), per student per day | same, separate counter | 10 |
| Document extraction, shared across the pilot per day | same | 50 |
| Document burst, per student | same | 3 per 300 s |

These are **request counts, not token or dollar caps.** A long reply costs more than a short one, and image uploads cost more than text. No token or dollar metering is implemented.

### How counting works

- One unit is reserved **immediately before** each paid provider call, after authentication, validation, and prompt building. Requests rejected earlier (no session, bad JSON, empty or too-long message, wrong file type, unreadable PDF, an exact duplicate syllabus) cost nothing.
- Reservation is a single Postgres transaction that locks the three counter rows (user daily, user burst, shared daily) in a fixed order. Parallel requests serialize, so a limit can't be overshot.
- A denied reservation increments nothing.
- **A reserved unit is never refunded.** If the provider errors or times out after reserving, the attempt still counts, because the provider may have billed it.
- **One reservation covers exactly one paid call.** Chat has no automatic retries. The automatic memory-extraction call, a second paid call per message, is turned off for the pilot; memories the student saved still go into the prompt. The legacy Python clients are set to `max_retries=0`, and its retry helper now makes one attempt.
- Syllabus: an identical re-upload of a file that was already read makes no AI call and costs nothing. Re-uploading a file whose earlier attempt **failed** runs extraction again and counts.

### Fail-closed rules

The paid call is skipped and the student sees "MyAdvisor is temporarily unavailable…" (or "Document reading…") with HTTP 503 when:
- `OPENAI_API_KEY`, `SUPABASE_URL`, or `SUPABASE_SERVICE_ROLE_KEY` is missing (checked before reserving, so nothing is charged);
- a `MYADVISOR_*` limit is set but isn't a whole number within bounds (an unset limit uses the default above);
- the quota RPC is unreachable, takes longer than 5 s, returns non-200 (for example before migration 010 exists), or returns anything other than exactly one well-formed row.

Limit reached: HTTP 429 with `Retry-After`. Codes are `<PREFIX>_RATE_LIMITED` (student daily), `<PREFIX>_BURST_LIMITED`, and `<PREFIX>_PILOT_CAPACITY_REACHED` (shared), with prefix `CHAT`, `TRANSCRIPT`, `DARS`, or `SYLLABUS`. The legacy API uses the `AI_` prefix.

## Changed paths

New:
- `backend/supabase/migrations/010_ai_usage_quotas.sql`: the other agent's draft, reviewed and kept. Added `pg_temp` last in the function's `search_path`, plus counting and concurrency comments. It's additive: 006's `chat_usage`/`consume_chat_quota` stay but are no longer called.
- `backend/supabase/functions/_shared/quota.ts`: one helper for every Edge Function (limits, strict reply validation, messages).
- `backend/supabase/functions/chat/handler.ts`: the chat handler, moved from `index.ts` so it can be tested; `index.ts` now only calls `Deno.serve`. The other agent's `stream.ts` is used unchanged.
- `backend/app/services/ai_guard.py`: protection for the legacy FastAPI routes.
- Tests: `backend/supabase/tests/quota_test.ts`, `chat_quota_test.ts`, `quota_fixtures.ts`; `backend/tests/conftest.py`, `test_ai_guard.py`.

Modified:
- `functions/_shared/academic.ts` (transcript and DARS reserve inside `extractJsonFromOpenAI`), `transcript/index.ts`, `dars/index.ts` (pass the verified user id).
- `functions/courses/handler.ts`, `index.ts`, `syllabi.ts`: syllabus reservation after the duplicate check and before any file or row is stored. Without a provider key the upload is refused with a 503 instead of being saved as a failed document.
- Chat no longer logs provider error text (it can echo request details); it logs the status only. Provider errors never reach the client.
- Legacy FastAPI: `routes/chat.py`, `advisor.py`, `transcript.py`, `tutoring.py`, `admin.py`; `services/ai_service.py`, `transcript_service.py`, `dars_audit_service.py`.
- Test plumbing: `tests/harness.ts` (010 added to the migration chain, PGlite RPC helpers), `courses_dev_server.ts`, `registration_test.ts`, `review_test.ts`, `syllabi_test.ts`.

### Legacy FastAPI

- `/chat`, `/chat/stream`, and `/tutoring/recommend` are **retired for the pilot** (503 `LEGACY_CHAT_RETIRED`) whatever the flag says, because they have none of the Stage 2 scope controls.
- The other paid routes (`/advisor/plan`, `/transcript/upload`, `/advisor/dars/upload`) return 503 `LEGACY_AI_DISABLED` unless `LEGACY_AI_ROUTES_ENABLED=true`.
- When enabled, each needs a session that Supabase Auth verifies, and reserves through the same `reserve_ai_quota` with the same limits, so both backends share one set of counters. Plan and tutoring use the chat allowance; transcript and DARS use the document allowance.
- Raw exception text (which previously included `AI service error: …`) is no longer returned to clients.
- Corrupt PDFs now return a clean 422 before any paid call (previously an unhandled 500).
- `/admin/*` writes shared data using the service role and had no authentication. It is now off unless `ADMIN_API_TOKEN` is set, and then needs a matching `X-Admin-Token` header.

## Secrets review (no values printed)

- App code, tracked config, untracked files, and full git history: no OpenAI keys, no `sb_secret_` keys, and no service-role JWTs. The only embedded key is the Supabase **anon** key in `SupabaseService.swift`, which is public by design; RLS protects the data.
- `backend/.env.example` holds only empty placeholders for the keys. `.env` files are git-ignored, and no `backend/.env` exists locally.
- `OPENAI_API_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are read only by server code (Edge Functions and FastAPI).
- Not changed, belongs to the iOS owner: in **Debug** builds, `APIService.debugLogResponse` prints up to 800 characters of response bodies to the Xcode console, which can include transcript data. Release builds don't log it.

## Local test results (2026-11-11)

- `deno test -A backend/supabase/tests/`: **82 passed, 0 failed** (53 existing plus 29 new).
- `deno check --no-lock` on every `functions/*/index.ts` and all test files: clean.
- `pytest backend/tests` (scratch virtualenv with `requirements.txt` + pytest): **20 passed.**
- Mutation check: making the helper treat a database error as "allowed" fails 4 tests; restored afterwards.

Coverage: no session, the anon key, invalid tokens, and the service-role key used as a user token are all rejected before any quota or provider call. Client-sent `user_id`, `model`, token, and limit fields are ignored, and client system-role messages are dropped. Malformed or empty bodies cost nothing. Also covered: 10 per day then 429, the burst limit, the shared ceiling across students, 12 and 30 parallel requests, and chat and document counters staying independent. The New York day boundary and next-midnight `Retry-After` are checked, as are SQL bounds checks and RLS (students read only their own daily row and can't call or write anything; anon gets nothing). Fail-closed cases: outage, malformed reply, timeout, missing key or credentials, invalid limit. A provider failure counts once with no retry. JSON and SSE each make exactly one provider call and keep the existing contract (`memories: []`, tokens, `finish`, `[DONE]`); a denied stream request is a JSON error. Syllabus: duplicate free, denial stores nothing, outage gives 503. Document defaults allow exactly 10 per student and 50 across the pilot.

Everything runs against PGlite with the real migration chain and dummy credentials. No OpenAI calls, no hosted database, no student records.

## Not verified locally

- Hosted Postgres row locking under true multi-connection load. PGlite runs one connection, so the parallel tests show correctness, not lock behavior; the fixed lock order is what prevents deadlock.
- The real Supabase Auth and PostgREST behavior of the deployed functions, including the RPC response shape (the code expects PostgREST's array of one row).
- Real provider spend per request, and how the iOS app displays the new 429 and 503 messages. iOS shows 429 and 503 server messages as-is.

## Deployment handoff (instructions only; nothing here was run)

1. Apply migrations to hosted Supabase **in order**: 005, 006, 007, 008, 009, **010**. On 2026-11-10 the hosted database had only 001–004 (the 005 and 006 tables were missing).
2. Deploy migration 010 **before** the new functions. Otherwise every paid request fails closed with 503.
3. Deploy Edge Functions: `chat`, `transcript`, `dars`, `courses` (and `account`, already pending). The deployed chat function currently accepts anonymous requests (probe of 2026-11-10); that is fixed only after this deploy.
4. Function secrets: hosted Supabase injects `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` automatically; confirm they're present. `OPENAI_API_KEY` is required. Optional: `MYADVISOR_CHAT_USER_DAILY_LIMIT`, `MYADVISOR_CHAT_GLOBAL_DAILY_LIMIT`, `MYADVISOR_CHAT_BURST_LIMIT`, `MYADVISOR_CHAT_BURST_WINDOW_SECONDS`, and the matching `MYADVISOR_DOCUMENT_*` names. The old `CHAT_DAILY_LIMIT` is no longer read; remove it to avoid confusion.
5. If the FastAPI app runs anywhere: leave `LEGACY_AI_ROUTES_ENABLED` and `ADMIN_API_TOKEN` unset unless needed. If enabled, it needs `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `OPENAI_API_KEY`, and migration 010 applied.
6. After deploying, check that an anonymous chat request gets 401, a signed-in test account's 11th message gets 429, and `ai_usage_daily` shows the count. Run the 11-message check only on a test account.

## Stage 2: pilot scope, input bounds, one model

MyAdvisor answers academic-advising questions: degree requirements, audits, prerequisites, course planning, registration steps and deadlines from records, study and workload planning, office hours, tutoring referrals, and reviewed syllabus policies. Solving homework, proofs, essays, assignment debugging, subject tutoring, and unrelated requests are outside the pilot.

### Layers (`functions/chat/scope.ts`, `handler.ts`)

1. **Fixed redirects, no paid call, no quota.** A pattern classifier catches clear homework, unrelated, or instruction-override requests that contain no advising intent. They get a short redirect pointing to office hours, the Student Success Center, or what MyAdvisor can do, in the normal JSON or SSE shape. These still work after the daily allowance is used up.
2. **Mixed requests** (advising intent plus an out-of-scope signal) go to the model with an added instruction: answer only the advising part, decline the rest in one sentence, and point to office hours. One paid call, counted.
3. **Every paid call** carries scope and trust rules in the single system message.
4. **Untrusted data.** Academic context and the student's records (transcript, in-progress courses, parser notes, saved memories) are wrapped in `<academic_context>` and `<student_records>`, and the prompt says never to follow instructions inside them or in earlier turns. Memories and notes phrased as instructions are dropped. Client `system`, `developer`, `tool`, and `function` roles, and non-string content, are dropped.

**Keyword filters and prompts cannot guarantee enforcement.** Rephrased or novel requests can pass layer 1, and the model can still be talked into answering. False positives are also possible: an advising question phrased like homework may get a redirect. The layers reduce cost and misuse; they are not a security boundary. The quotas bound what any one student can spend regardless.

### Bounds

| Input | Limit |
|---|---|
| Request body | 512 KB, checked while streaming, so a missing or false Content-Length doesn't help. Larger gets 413 with a pointer to the import screens. |
| Newest message | 4,000 characters (400 if longer) |
| History received | last 40 turns, each cut to 8,000 characters (older app builds send this much) |
| History sent to the model | last 6 messages, starting with a student turn; older turns in the window cut to 1,500 characters. Nothing older is sent, not even a summary. |
| Transcript entries | 120, with fields cut (code 16, name 80, grade 8, term 24 characters) |
| In-progress courses / parser notes / memories | 30 × 120 / 10 × 300 / 10 × 200 characters |
| Records block / academic context | 8,000 / 9,000 characters |
| Everything sent (system + window) | at most 32,000 characters (about 8,000 tokens); a final check refuses anything larger |
| Reply | `max_completion_tokens` 1,200 by default (`CHAT_MAX_COMPLETION_TOKENS`, allowed 400–2,000), `reasoning_effort` "low" (`CHAT_REASONING_EFFORT`: none, minimal, low, medium, or `off` to omit). Invalid values fail closed with 503. |

**Reasoning tokens:** for reasoning models, hidden reasoning counts against `max_completion_tokens`. The 1,200 default allows low-effort reasoning plus a concise answer of roughly 250–400 words; the prompt asks for under 250 words. If the limit is hit, `truncated: true` (JSON) or `finish: length` (SSE) is returned as before, and the app shows its existing "continue" note. If the limit is hit **before any text** (all reasoning), the server now sends a clear message ("That question needed a longer answer… ask about one part at a time") instead of an empty reply, which the app would otherwise show as nothing.

**Unverified:** whether the configured model (default `gpt-5.4-nano`) accepts `reasoning_effort` and "low". If it rejects the parameter, every chat returns 502 until `CHAT_REASONING_EFFORT=off` is set. Check this on the first deployed request with a test account.

### Model and extra calls

- One model: `OPENAI_MODEL_ADVISOR`, then `OPENAI_MODEL_CHAT`, then `OPENAI_MODEL`, then `gpt-5.4-nano`. `OPENAI_MODEL_TUTOR` and the keyword-based tutor routing are gone. The request body can't choose the model, tokens, effort, temperature, tools, or streaming (streaming is set by the URL path).
- No separate memory-extraction call: `chat/memory.ts` is deleted, and replies always carry `memories: []`. Memories the student saves on the device are still sent, bounded, as data.
- Exactly one paid call per accepted request, no retries.

### Attachments

Any non-empty `attachments` returns a fixed reply, with no paid call and no quota: Profile → Transcript, Degree Progress → Import DARS, or This term → course → upload syllabus. Older builds that try to send a photo larger than the body cap get the 413 instead, which also points to those screens. `attachments.ts` remains only for the other agent's regression test.

### Response contract

Unchanged for iOS: JSON `{reply, truncated, memories}`, plus an optional `scope` field (`out_of_scope` or `attachments_disabled`) on fixed replies that decoders can ignore; SSE string tokens, then `{"type":"finish","reason":...}`, then `[DONE]`. Nothing on the server touches saved conversations.

### For the iOS owner (not changed here)

- `ChatViewModel.maxMessageCharacters` is 8,000 but the server now allows 4,000 for the newest message. Lower it to match, or students will see a 400 for long messages.
- The app can stop sending more than 6 history messages and stop sending attachments; the server enforces both anyway.

### Stage 2 tests (2026-11-11)

- `deno test -A backend/supabase/tests/`: **96 passed, 0 failed.** That's the 82 from Stage 1 plus 14 in `chat_scope_test.ts`; the other agent's `chat_regression_test.ts` was updated for the 6-message window and the single model.
- `deno check --no-lock` on every function and test file: clean. `pytest backend/tests`: **21 passed.**
- Covered: 11 advising phrasings, 14 redirects (homework, unrelated, injection) with no provider or quota calls in JSON and SSE, redirects after the daily limit, 4 mixed requests answered once with the advising-only note, and injected roles, model, tokens, effort, temperature, tools, stream, and limit fields ignored. Also: instruction-like memories and notes dropped, record text fenced, a 512 KB+ body refused with and without Content-Length, a 4,001-character message refused, a near-cap conversation sent as at most 6 messages and at most 32,000 characters with at most 10 memories, attachments redirected, invalid token or effort settings failing closed, and the empty "length" reply message.
- Mutation checks: with the classifier disabled, 5 scope tests fail; with the attachment check removed, the attachment test fails. Both restored.

## Remaining limitations

- Request counts and token caps bound usage, but they **don't guarantee a fixed dollar spend.** Per-request cost depends on the model's price, how much of the bounded input is used, and reasoning tokens. A worst-case daily estimate is 250 chat requests × (about 8,000 input + 1,200 output tokens) plus 50 document extractions at their own caps (5,000 output tokens for transcript/DARS, 12,000 for syllabi, plus file input). That's an upper estimate to price, not a measured or enforced budget.
- Scope enforcement is best-effort, as described above.
- The `tutoring` Edge Function (static, no AI call) no longer calls MyAdvisor an "AI tutor"; it now describes it as planning help. Matching iOS copy belongs to the iOS owner.
