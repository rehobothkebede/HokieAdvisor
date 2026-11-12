# Advisor Chat Fix Plan

The Advisor chat is the app's main selling point. Fix the issues below in the
order given. Work on a branch named `advisor-fixes` (create it from `main`).
Plan first, then implement phase by phase, committing after each phase.

## Ground rules

- Do NOT deploy Edge Functions or apply migrations to hosted Supabase. Write the
  code and migrations only; I will deploy.
- Do NOT touch `ios/HokieAdvisor/HokieAdvisor/Hoki.icon`.
- Never commit secrets. The service-role key stays server-side only.
- Keep Virginia Tech behaviour working exactly as today.
- Build the iOS app after the iOS phases (`xcodebuild ... CODE_SIGNING_ALLOWED=NO build`
  against an iPhone simulator) and fix any errors before moving on.
- After each phase, summarise what changed and anything you could not verify.

## Phase 1 - Security (highest priority)

All functions in `backend/supabase/config.toml` have `verify_jwt = false`, and
`functions/chat/index.ts` never checks the caller, so anyone with the URL can
spend our OpenAI credits.

1. Add a shared helper in `functions/_shared/` that reads the `Authorization`
   bearer token, validates it with Supabase Auth (`/auth/v1/user`), and returns
   the user id or a 401. Use it in `chat`, `tutoring`, `audit`, `transcript`,
   `dars`, and `account`. Reject requests carrying only the anon key.
2. In `chat`, drop any client-sent `system` or `tool` role messages; accept only
   `user` and `assistant`.
3. Add per-user rate limiting for `chat` (e.g. 60 requests per hour, 300 per
   day). Add a migration `006_chat_usage.sql` with a small usage table (RLS on,
   service-role writes only) and enforce the limit in the function. Return a
   friendly 429 with a `CHAT_RATE_LIMITED` code; make the iOS app show it.
4. Cap request size: max message length (~8k chars), max messages per request.

## Phase 2 - Make the advisor actually know the student's requirements

1. Server-side context: in `chat`, use the authenticated user id to load the
   student's profile (major, institution), latest `degree_audits` and
   `dars_audits` results, from Postgres with the service-role key. Do not trust
   the client for this. Keep accepting the client transcript for now.
2. Include in the prompt: remaining requirements and unmet items from the
   latest audit/DARS, the relevant `catalog_requirements` for the student's
   program, and Pathways (gen-ed) progress.
3. Course catalog: remove the "first 80 CS courses" cutoff. Instead pick
   relevant courses: those mentioned in the user's latest message (regex the
   course codes), courses in unmet requirements, and courses whose prereqs the
   student has satisfied. Keep the total context within a sensible budget.
4. Replace `subjectForMajor` (CS only) with a lookup against `catalog_programs`
   so any major gets catalog context. Gracefully handle unknown majors.
5. Pass the current date and the current/next term (e.g. "Today is 2026-10-21;
   current term Fall 2026; next registration term Spring 2027") into the prompt.
6. Make this institution-aware where cheap (read `institution_id` from the
   profile if the column exists), but don't block on migration 005.

## Phase 3 - Conversation length and cost

1. Trim history server-side: keep the last ~20 messages verbatim, and when
   older messages exist, summarise them into one short system note (or just drop
   them with a note) so long chats never overflow the context window.
2. Raise `max_completion_tokens` to a value that won't truncate proofs, and make
   it configurable via env (`CHAT_MAX_TOKENS`). Make the model configurable via
   env as it already is, and document trying a larger model than nano.
3. iOS: if the user leaves mid-stream or the stream fails after tokens arrived,
   keep the partial answer (marked as interrupted) instead of deleting it.

## Phase 4 - Graph visuals that match the suggestion chips

The system prompt says "include a fenced graph block" but never specifies the
format, so the model guesses. `SimpleGraph.parse` in `ContentView.swift` is
also limited.

1. Define a clear graph block spec and put it in the system prompt with a short
   example. Support:
   - undirected `A -- B`, directed `A -> B`, weighted `A -- B : 4`
   - node ids with hyphens/spaces via quotes, e.g. `"node-1" -- "node-2"`
   - `highlight: A B D` (path)
   - `steps:` blocks for algorithm walkthroughs (e.g. BFS visit order, one step per line)
2. Update the parser and `GraphDiagramView` to: draw arrowheads for directed
   edges, show weights as edge labels, stop splitting hyphenated names, use a
   better layout than a fixed circle (simple force-directed or layered for trees),
   and render `steps` with a step slider / next-prev control.
3. Add unit-testable parsing (a pure function) and a few sample blocks as previews.
4. Check each suggestion chip in `ChatView.swift` produces a correct visual.

## Phase 5 - Math rendering

The homegrown `LaTeXFormatter` only approximates LaTeX. Integrate a real native
renderer via Swift Package Manager (SwiftMath is a good choice; it's pure
Swift/CoreText, no WebView). Use it for display math and inline `$...$` math,
falling back to the current formatter only if rendering fails. Make sure it
works in light and dark mode and scrolls horizontally for wide equations.

## Phase 6 - Real attachments (photo of a homework problem)

Attachments currently only send the text "Direct file analysis is not
connected yet".

1. Photos: downscale/compress on device (max ~1600px, JPEG), upload to a
   user-owned Supabase Storage path (follow the existing transcript/DARS storage
   pattern and RLS), and send the storage path with the chat request. In the
   function, download it with the service role and send it to the model as an
   image input. Use a vision-capable model for those requests.
2. PDFs/text files: extract text server-side (or on device for plain text) and
   include it, size-capped.
3. Show the attachment thumbnail in the sent message bubble and persist it in
   chat history.

## Phase 7 - Smarter memory

`captureMemory` stores the entire user message when it contains phrases like
"remember that" or "I prefer". Replace it with a small server-side extraction
step: after a reply completes, ask the model (cheap model, short prompt, JSON
output) whether the user's message contains a durable preference or fact, and
store only that one-line fact. Dedupe against existing memories, cap at 100,
and add a Settings screen section where the user can view and delete memories.

## Done means

- All phases committed on `advisor-fixes`, iOS app builds cleanly.
- A short `docs/ADVISOR_FIX_NOTES.md` listing: what changed, new env vars,
  migrations to apply and their order, functions to redeploy, and a manual test
  checklist (one test per issue above).
