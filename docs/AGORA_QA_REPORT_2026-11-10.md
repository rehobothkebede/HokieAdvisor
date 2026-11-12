# Agora — QA Results and Launch Priorities

**Tested November 10, 2026.** Scope: the student features described in the partner overview, the current local source, an isolated simulator, local integration fixtures, and limited live endpoint checks.

## Assessment

The local course/syllabus pipeline and core chat client are in good shape under automated tests. The biggest immediate problems are deployment consistency and a live authentication gap, followed by reminders, account recovery, and the reliability of course-eligibility claims.

**Do not treat the current live service as ready for a wider pilot:** the deployed chat endpoint returned an AI answer without a signed-in user, and the new courses endpoint is missing. Neither issue was changed on the hosted service during this review.

## What passed

| Check | Result | What this establishes |
|---|---|---|
| iOS Debug build for the isolated QA simulator | Passed | Current source compiles with normal simulator signing |
| Install and launch on “Agora Design QA” | Passed; process remained running | Basic launch, not a full screen-by-screen test |
| Backend automated tests | **53 passed, 0 failed** | Existing 43 course tests plus 10 new chat/auth/quota regressions |
| Actual Swift client integration and model checks | **36 passed, 0 failed** | Real transport, decoding, view-model, graph, and math-text behavior with local fixtures |
| Seven Edge Function entrypoint checks | Passed | Chat, tutoring, audit, transcript, DARS, account, and courses type-check |
| Diff whitespace check | Passed | No patch whitespace errors |

The backend tests run the local migration chain in an in-memory Postgres-compatible database. They cover registration references, term handling, ownership boundaries, syllabus upload/review/corrections, unsupported evidence, updated syllabus versions, reminders, and deletion. The new quota test checks the cap, owner visibility, and rejection of student writes and direct quota-RPC calls.

The Swift integration test runs this sequence against the real course handler:

**Load terms → read registration guide → add a section → set/clear a syllabus reminder → upload a fixture PDF → retrieve the original → review extracted facts → load the dashboard → add/delete a reminder → delete the test course.**

It also checks normal chat, extracted memories, long-answer continuation, abrupt disconnects, provider interruption, empty responses, rate-limit errors, graph directions/weights/steps/layout, and inline/display math parsing.

## Live-service findings — address first

### 1. Critical: chat answers without a signed-in student

**Confirmed by a live test.** A request carrying only the public anonymous key already shipped with the iOS app returned HTTP 200 and `{"reply":"AUTH_PROBE"}` for one harmless test prompt. No user session or student record was used.

This public key is intended to be public; rotating or hiding it is not the fix. The deployed function needs to verify a real user session before requesting an AI response. The local chat code already calls `requireUser` before parsing the body, so the deployed behavior differs from the reviewed local code.

**Next action:** Review and deploy the authenticated chat version, then verify that missing credentials, the public anonymous key, and expired sessions return 401, while a valid student session works. Confirm the quota migration and configuration are active. Check the streaming route as well as the normal chat route.

Tutoring also accepted an anonymous request far enough to validate its body, returning `TUTORING_COURSES_REQUIRED` rather than 401. This confirms an authentication-order mismatch, but a successful anonymous tutoring response was not tested. Audit, transcript, and DARS rejected the anonymous probes with 401.

### 2. High: “This term” cannot work against the current live backend

**Confirmed by a live test.** `/functions/v1/courses` returned HTTP 404 with `NOT_FOUND` / “Requested function was not found.” The other five checked function paths responded to OPTIONS requests.

This explains the Home error previously shown in screenshots. The local feature works through the Swift integration test; its live service is absent.

**Next action:** Review the courses function, required database migrations, private storage setup, and extraction configuration, then deploy and test the full student flow with a test account. Check which migrations are already applied before choosing deployment commands.

The local tests require migration 005, and that file is still untracked. Migrations 007–009 depend on the institution foundation. Include the reviewed dependency in version control before expecting a clean checkout or another developer’s environment to reproduce this build. Do not run an indiscriminate database push based on this report.

## Fixes made locally during this review

### Chat interruptions are no longer silently presented as complete

The new Swift test reproduced a failure: the server connection could close after sending partial text without throwing a transport error, and the app would treat that as a completed answer.

The client now detects completion markers, handles the server’s explicit interruption reason, and lets the existing view-model behavior preserve partial text marked “(interrupted).” Empty streams restore the draft. The stream task is cancelled when its consumer terminates.

The backend relay was moved into a testable module and now reports `interrupted` if the model stream ends without a completion reason, rather than manufacturing `stop`. This backend change requires a later deployment.

### Course loading has a recovery path

- Added a Retry action when loading or refreshing the course list fails.
- Kept already-loaded courses visible with a stale-list explanation when refresh fails.
- Added a loading indicator for an initially empty course list.
- Added pull-to-refresh on Home for the course overview and course list.
- Recognized a missing courses deployment and replaced the misleading connection error with a service-unavailable message.
- Added vertical space to the “This term” error card.

These controls compile, but their visual appearance and tap behavior still need simulator/device acceptance testing.

### Build warnings cleaned up

Fixed the ambiguous loading-state switch and the actor-isolation warnings between the course client and shared API helpers. The final build retained only Xcode’s informational App Intents metadata warning; no application-code warnings were reported.

## Remaining work, in priority order

| Priority | Finding | Evidence and impact | Recommended work |
|---|---|---|---|
| High | Scheduled reminders are not cleared on sign-out | Code review: sign-out/local-data reset clears records and credentials but does not cancel course notifications. A previous student’s reminders could remain on the device. Notification delivery was not tested. | Scope notifications to the account; cancel pending/delivered course notifications on sign-out, local reset, and account deletion; protect against in-flight work rescheduling them. Test switching accounts. |
| High | Updated reminder times can stay stale on another device | Code review: reconciliation compares notification identifiers only and skips ones already pending. A changed date under the same ID is not replaced. | Reconcile trigger/content changes as well as IDs. Refresh on foregrounding and after changes. Test two-device changes and permission denial. |
| High | Course eligibility is overstated for non-course restrictions | Executed diagnostic: both “Junior standing” and “Consent of instructor” return `true` for an empty passed-course set. The context labels selected courses “prerequisites met.” | Use met / unmet / needs confirmation states. Preserve grade thresholds, standing, consent, and grouped AND/OR rules. Do not label unknown restrictions as satisfied. |
| High | No visible password-recovery flow | Code review: login offers sign-in/sign-up but no Forgot password action. | Implement the recovery email, app-link handling, new-password flow, expired-link state, and clear success/error messages. Verify on a test account. |
| High | Chat quota permits requests if its check fails | Code review: a missing quota configuration, RPC failure, or exception returns `allowed: true`. The quota itself passed local database tests. | Decide and implement a bounded fallback or a friendly temporary-unavailable response. Verify behavior when the quota database is unavailable. |
| Medium | Advisor does not automatically use confirmed syllabus details | Code review: chat context fetches profile/catalog/audits but not course-companion facts. | Add reviewed, account-owned facts for the relevant section and term, with evidence. Test questions about the student’s next exam and office hours. |
| Medium | Microphone button has no speech functionality | Code review: the empty composer’s microphone only triggers haptic feedback. | Remove the misleading control until voice input exists, or implement speech input with proper permission and error handling. |
| Medium | Transcript corrections require replacing the file | Confirmed by current UI/help implementation. | Add a review-and-correct workflow before imported information changes advising results. Keep original values and student corrections distinguishable. |
| Medium | Branding is inconsistent inside AI instructions | Local chat system prompt still introduces “Hokie Advisor.” | Update student-facing AI identity to Agora while retaining VT academic context for VT users. |
| Medium | FastAPI remains behind the Supabase feature path | Code review: equivalent chat route lacks the same auth/quota and newer context/attachment/memory behavior. | Either complete parity before exposing it, or explicitly retire/document it as a non-production path. It was not deployed or exercised against live AI here. |

Additional reliability work: use a user-scoped selected-term preference; add safe diagnostics for failures without recording student documents or credentials; and establish a release check that verifies which app version, functions, and migrations are running together.

## Improvements to sequence after reliability work

1. Make the first-run path explicit: import record, review results, see progress, add current courses, review syllabi, optionally enable reminders.
2. Explain the source and freshness of advising information next to recommendations.
3. Add verified syllabus context to chat so the two features feel like one product.
4. Complete editable planning before advertising automatic semester roadmaps.
5. Expand to transfers, additional schools, shared syllabi, and professor feedback after the VT pilot’s core flows are reliable.

## What this review did not verify

- Full tap-through visual testing, keyboard behavior, dark mode, large text, and VoiceOver. The computer-use connection timed out twice. No visual pass is claimed.
- Real-user sign-up, verification emails, password recovery, session expiry, or Keychain persistence.
- Production syllabus upload/storage/extraction, because the courses function is not deployed.
- Real on-device OCR, notification delivery, background behavior, or two-device synchronization.
- The correctness of AI academic answers or a representative set of real transcript/audit imports. Most tests use synthetic data and recorded extraction results. The only live model response requested was the harmless authentication probe.
- Hosted migration state, security policies, or account-deletion behavior. Local RLS tests are useful but do not certify the hosted configuration.

## Acceptance checklist for the next release

- [ ] Public/anonymous chat and tutoring calls return 401; valid students can use both.
- [ ] The courses endpoint exists and works for a signed-in test student.
- [ ] A new student can sign up, sign in, relaunch, recover a password, and sign out.
- [ ] Upload a real test transcript and DARS audit; compare every displayed result with the source.
- [ ] Complete syllabus upload → source review → corrections → dashboard → notification on a device.
- [ ] Change a syllabus date and verify the old reminder is paused/replaced correctly.
- [ ] Sign out and sign in as another test student; no prior data or notifications appear.
- [ ] Lose connectivity during an upload, course refresh, and chat answer; recovery is clear and drafts/partial answers survive.
- [ ] Check all main screens at large text sizes, in dark mode, with the keyboard open, and with VoiceOver.
- [ ] Try the original five demo prompts: BFS visual, paths vs circuits, eigenvalue example, recurrence proof by induction, and next-semester course choices. Check answer quality and every visual; routing tests alone do not establish answer accuracy.
- [ ] Try the current planning suggestions: remaining requirements, latest audit, missing prerequisites, and preparing for an advising appointment.
- [ ] Confirm “Junior standing,” consent, minimum grades, and missing catalog data never become unconditional eligibility claims.

## Re-running the automated checks

See [local test instructions](/Users/mula/HokieAdvisor/tests/qa/README.md). From the repository root:

```sh
bash tests/qa/run_client_smoke.sh
deno test --no-lock --allow-read --allow-env backend/supabase/tests
deno check --no-lock backend/supabase/functions/{chat,tutoring,audit,transcript,dars,account,courses}/index.ts
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/HokieAdvisor/HokieAdvisor.xcodeproj \
  -scheme HokieAdvisor -configuration Debug \
  -destination 'platform=iOS Simulator,id=A92036A3-0253-4D30-8A2B-14AE41335DE8' \
  -derivedDataPath /tmp/agora-qa-build build
```

All changes from this review are local and uncommitted. No functions were deployed, no hosted migrations were applied, and no real student records were changed. Existing edits to `SupabaseService.swift` were preserved; `Hoki.icon` was not edited.
