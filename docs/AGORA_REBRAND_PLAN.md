# Agora Rebrand Plan

Branch: `codex/agora-rebrand` (created from `advisor-fixes` at `d15e6f5`, which
carries advisor phases 1–7 not yet on `main`). Started November 5, 2026.

## Brief

- Name: **Agora**. Tagline: "Your next chapter". Supporting line: "Understand
  your degree. Plan what's next."
- Palette from the logo reference: navy, warm ivory, copper; elegant serif
  wordmark.
- Agora is the independent platform; Virginia Tech is the first, and currently
  only, supported school. Later, accent colors adapt to the student's school.
- Frontend rebrand only.

## Constraints

- No backend edits, deploys, migration applies, or pushes.
- Do not touch `ios/HokieAdvisor/HokieAdvisor/Hoki.icon`.
- Keep internal identifiers: bundle id `com.hokieadvisor.HokieAdvisor`, URL
  scheme `hokieadvisor://auth/callback`, target/scheme/project names,
  `Hokie*` Swift type names, `vtPID`/`vtEmail`/other `@AppStorage` keys,
  Keychain keys, Supabase tables and columns, `-HokieVisualQA` /
  `-HokieInitialTab` launch flags.
- Preserve auth, uploads, GPA/audit calculations, chat streaming, graphs,
  math, memories, and the uncommitted `005_multi_institution.sql` and `docs/`.
- Never imply schools or majors beyond VT / the CS B.S. deterministic audit.

## Current state (from the repo)

- **Design system** lives at the top of `ContentView.swift`: `Color.vtBurgundy`,
  `vtBurgundyDark`, `vtOrange`, `hokieStone`; `HokieGlassPalette`;
  `HokieAppBackground` (hard-coded warm-white / near-black-burgundy base plus
  burgundy→orange wash); `HokiePageHeader`, `HokieSignalMark`,
  `HokieIconTile`, `HokieCompactPill`, `HokieSegmentedControl`,
  `FloatingTabBar`, `SectionLabel`, `HokieSheetHeader`.
- **Color usage**: `.vtBurgundy` / `.vtOrange` are referenced directly ~100
  times across `ContentView`, `ChatView`, `HomeView`, `LoginView`,
  `HokieAdvisorApp` (global `.tint`). `.orange` is also used semantically for
  warnings/GPA bands — keep those semantic.
- **Typography**: system fonts with `.fontDesign(.rounded)` on titles/stats. No
  custom fonts bundled.
- **Brand copy** ("Hokie Advisor", "Hokie Tips", "Let's Go, Hokies!", "New
  Hokie setup", "VT students"): `LoginView`, `OnboardingView`, `HomeView`,
  `SettingsView` (footer, Terms, Privacy, policies row), `ContentView` (audit
  empty state), `Info.plist` camera/photo usage strings.
- **Display name**: `Info.plist` has no `CFBundleDisplayName`, so the home
  screen shows `$(PRODUCT_NAME)` = "HokieAdvisor".
- **App icon**: `ASSETCATALOG_COMPILER_APPICON_NAME = Hoki` → `Hoki.icon`
  (Icon Composer). There is no `Assets.xcassets` in the target yet. The project
  uses a file-system-synchronized group, so new files/folders in
  `ios/HokieAdvisor/HokieAdvisor/` are picked up without pbxproj edits.
- **Institutions**: nothing in iOS. The untracked `005_multi_institution.sql`
  adds `institutions` with a `branding` jsonb (VT seed:
  `primary_hex #861F41`, `secondary_hex #E5751F`, `community_name "Hokie"`) and
  `profiles.institution_id`. Not applied; iOS must not depend on it yet.
- **Backend persona**: the `chat` function's system prompt says "You are Hokie
  Advisor…" and context labels say "Hokie Advisor degree audit". Out of scope
  here; the assistant will keep calling itself Hokie Advisor until the backend
  is updated and deployed separately.

## Approach

1. **Brand tokens, not find/replace.** Add `AgoraBrand` (name, tagline,
   supporting line) and a `Theme` with semantic roles: `brandNavy`, `ivory`,
   `copper`, plus `accent`, `accentDeep`, `accentSecondary`. Keep the
   `vtBurgundy`/`vtOrange` statics so nothing breaks mid-migration, then move
   call sites to semantic roles screen by screen.
2. **School accent layer.** A small `SchoolTheme` value (`platform` = Agora
   navy/copper, `virginiaTech` = maroon/orange from the 005 seed values),
   injected via `EnvironmentValues`. Default to `platform` until product decides
   when VT accents apply (see decisions). Shape matches 005's `branding` jsonb
   so it can be fed from the server later without new UI work.
3. **Surfaces.** Retune `HokieAppBackground` and `HokieGlassPalette` to an
   ivory light mode and a deep-navy dark mode; replace the burgundy→orange
   gradients in header, tab bar, icon tiles, and user chat bubble with
   navy/copper (or school accent). Check contrast in both appearances.
4. **Typography.** Serif for the wordmark and large display titles only
   (`.fontDesign(.serif)` first; swap to a bundled face if one is licensed);
   keep body, numbers, code, and math on the system font so SwiftMath,
   code blocks, and graph labels stay unaffected.
5. **Copy.** Agora where the product is named; "Virginia Tech" where the
   school is meant (PID field, `@vt.edu`, Pathways, DARS, VT resources).
   Login/onboarding hero gets wordmark + tagline + supporting line.
6. **Display name and assets.** Add `CFBundleDisplayName = Agora`; update usage
   strings. Add an `Assets.xcassets` with the wordmark/mark images once
   supplied. Icon replacement is a separate, explicit step (new icon package
   pointed to by `ASSETCATALOG_COMPILER_APPICON_NAME`), never an edit to
   `Hoki.icon`.
7. **Verify** after each phase: simulator build per README, then visual QA
   with `-HokieVisualQA` and `-HokieInitialTab` in light and dark, plus a
   signed-in smoke test (sign in, transcript restore, audit, DARS, chat stream
   with math + graph, memories, sign out).

## Missing assets

- The logo reference was not in the repo or the conversation. Needed:
  - Wordmark, vector (PDF or SVG), light and dark/inverted variants.
  - Standalone mark/monogram for small spaces (headers, tab, loading).
  - Exact hex values for navy, ivory, copper (and any secondary tints).
  - Serif typeface name and license (or confirmation to use system serif).
  - App icon artwork (1024×1024, light/dark/tinted) or an Icon Composer file.

## Product decisions needed

1. **App icon**: keep `Hoki.icon` for now, or add a new Agora icon package and
   switch the build setting? (`Hoki.icon` itself stays untouched either way.)
2. **School accents now or later**: for VT students, ship Agora navy/copper
   everywhere, or apply VT maroon/orange accents on top of the Agora base in
   this pass?
3. **VT voice**: keep "Hokie Tips" and "Let's Go, Hokies!" as school-flavored
   copy, or neutralize to "Tips" / "Let's go"?
4. **Legal text**: confirm the Terms/Privacy rewording (Agora as an
   independent platform, not affiliated with or endorsed by Virginia Tech).
   Changes to legal copy should be reviewed by whoever owns it.
5. **Advisor persona**: the backend prompt still says "Hokie Advisor". Accept
   the mismatch until a separate backend change, or schedule that change?
6. **Launch screen**: keep the blank `UILaunchScreen`, or add an ivory/navy
   background color with the mark?

## Progress checklist

- [x] Inspect repo, branch, docs, and screens
- [x] Create `codex/agora-rebrand` from `advisor-fixes` (untracked work kept)
- [x] Write this plan
- [ ] Receive logo assets, color hexes, font decision
- [ ] Resolve product decisions 1–6
- [x] Phase 1: `AgoraBrand` + semantic theme tokens + `SchoolTheme` environment
- [x] Phase 2: background, glass, header, tab bar, icon tiles, pills
- [x] Phase 3a: Welcome screen, school picker, signed-out flow, Login restyle
- [x] Phase 3b: Onboarding step screens (buttons, tiles, community-name button)
- [x] Phase 4: Home and Audit/DARS (redesign, tokens, copy)
- [x] Phase 5: Advisor chat (bubbles, composer, graph/step tints; math/code untouched)
- [x] Phase 6: Profile/Settings, Help & FAQ, Transcript/Tutoring/Memory/Legal sheets
- [x] Phase 7a: `CFBundleDisplayName = Agora`, camera/photo usage strings
- [ ] Phase 7b: asset catalog with real wordmark, icon (if approved)
- [ ] Build passes after each phase (phases 1–6, 7a: passed)
- [ ] Visual QA light/dark on all four tabs + login/onboarding
- [ ] Signed-in regression smoke test
- [ ] Grep confirms no user-facing "Hokie Advisor" left in iOS; internal ids unchanged

## Stage log

### Stage 1 — shared visual foundation (phases 1–2)

New `ios/HokieAdvisor/HokieAdvisor/AgoraTheme.swift`:

- `AgoraBrand` (name, tagline, supporting line).
- Platform colors `agoraNavy`, `agoraNavyDeep`, `agoraIvory`, `agoraCopper`,
  `agoraCopperLit`, and the light/dark semantic `AgoraPalette` (background,
  surface, surfaceInset, stroke, brandInk, copper). **Hex values are
  provisional** (navy `#1B2A41`, ivory `#F7F2E8`, copper `#B06A3B`) until the
  logo files give exact values.
- `AgoraSpacing` and `AgoraRadius` scales; `Font.agoraDisplay` (system serif,
  brand headings only) and `Font.agoraEyebrow`.
- `AgoraWordmark`: **temporary text wordmark** in the system serif. It is not
  the logo lettering; swap it for the vector wordmark once supplied. Not yet
  placed on any screen.
- `.agoraPrimary` / `.agoraSecondary` button styles and `.agoraField()` input
  modifier. Defined only; screens adopt them in phases 3–6.
- `SchoolTheme` (`accent`, `accentDeep`, `onAccent`, `secondaryAccent`) with
  `.agora` (neutral) and `.virginiaTech` (values from the 005 `branding` seed;
  maroon lifted in dark mode for visibility), exposed as
  `EnvironmentValues.schoolTheme`.

Institution source: no new stored state. `HokieAdvisorApp` resolves the theme
from the existing `vtEmail` value (synced from the Supabase profile) by email
domain, and injects it plus a global `.tint` at the root. No email / unknown
domain → neutral Agora theme. When `profiles.institution_id` from migration 005
ships, switch the resolver to that slug.

Shared components changed in `ContentView.swift` (names and APIs unchanged):

- Glass surfaces → flat ivory/navy cards, hairline stroke, softer shadow; sheen
  gradients removed.
- `HokieAppBackground` → solid Agora background (burgundy/orange wash and
  diagonal lines removed).
- `HokiePageHeader` → serif title in brand ink, quieter eyebrow, solid accent
  rule. `HokieSignalMark` is always navy/ivory (platform identity), accent
  only on its bottom edge. `HokieSignalTrack` → navy / accent / copper.
- `HokieIconTile` → solid fill, no blur blobs or burgundy/orange overlay.
- `HokieSegmentedControl` and `FloatingTabBar` selected state → school accent
  (`accent:` override still honored).
- `SectionLabel`, `HokieSheetHeader`, `HokieCompactPill` typography.
- Shared progress indicators (`centeredLoadingView`, `AuditSummaryCard`,
  transcript parsing, launch loader) inherit the school tint.

Deliberately untouched: status/data colors (`.orange` warnings, GPA bands,
DARS segment colors, code-block syntax colors, graph path highlighting), and
screen-level `.vtBurgundy`/`.vtOrange` call sites, which move in phases 3–6.

Verified: simulator build (`CODE_SIGNING_ALLOWED=NO`) on iPhone 18 Pro; Home,
Audit, Advisor, Profile in light and dark via `-HokieVisualQA`, plus the login
screen in light.

Follow-ups found during QA (for screen phases):

- Screen-level `.vtBurgundy` text on dark navy is low contrast (Advisor
  suggestion chips, Profile major pill). Move to `theme.accent` or brand ink.
- ~~Login still shows "Hokie Advisor" and explicit VT accents~~ (done in stage 2).
- ~~Neutral theme unseen; signed-out students keep VT accents~~ (resolved in
  stage 2: signed out is always neutral Agora until a school is chosen).

### Stage 2 — welcome experience (phases 3a, 7a)

School selection research: the iOS app had no school picker or institution
model; Virginia Tech was implicit. Migration 005 (not applied) backfills every
existing profile to VT and defaults new profiles to VT. So:

- `SchoolTheme.supported` (only Virginia Tech) is the one list of selectable
  schools. No mock schools.
- Signed-in accounts resolve with `SchoolTheme.forAccount(email:)`: match the
  email domain, else Virginia Tech. This replaces stage 1's domain-only
  lookup, which would have shown non-`vt.edu` accounts (allowed at sign-up) as
  school-less.
- The school picked before sign-in lives only in `SignedOutFlow` view state. No
  new storage key; the account remains the source of truth after sign-in.

New `WelcomeView.swift`:

- `SignedOutFlow` replaces `LoginView` in the root's signed-out branch:
  Welcome → school → Login (themed with the chosen school), with "Not at
  <school>? Change school" back to Welcome. A pending email confirmation
  (`pendingSignupEmail`) skips Welcome and opens Login directly.
- `WelcomeView`: temporary text wordmark, "Your next chapter", "Understand your
  degree. Plan what's next." New device → "Find your school". A device with a
  previous account email → "Continue with Virginia Tech" plus "Choose a
  different school".
- `SchoolPickerSheet`: search over supported schools only; footnote
  "Agora is available to Virginia Tech students today." No colors are shown
  as a reason to choose.

Other changes:

- Root theme: signed in → account school; signed out → neutral Agora (Welcome
  is always Agora navy/copper).
- `LoginView`: Agora wordmark, school name as eyebrow, school accent header,
  segmented control and `.agoraPrimary` submit button, `.agoraField()` inputs,
  "Agora" in footer copy. Auth logic, PID → `@vt.edu` normalization, and
  stored keys are unchanged.
- `OnboardingView`: step 0 header is Agora + supporting line + school
  eyebrow; progress bar uses school accent; product name → Agora in step
  copy. Step layouts, "Let's Go, Hokies!", and storage unchanged.
- Profile: school chip now comes from the theme (building icon + name, school
  accent). Footer reads "Agora · v1.0.0 / Your next chapter". Terms/Privacy
  text unchanged pending decision 4.
- `Info.plist`: `CFBundleDisplayName = Agora`; usage strings say Agora. Bundle
  id `com.hokieadvisor.HokieAdvisor`, URL scheme `hokieadvisor`, signing, and
  `Hoki.icon` unchanged (verified in the built `Info.plist`).

Verified on the iPhone 18 Pro simulator after a successful build:

- New user (fresh install): Welcome with "Find your school", light and dark.
- Returning signed-out user (account email on device, non-`vt.edu`):
  "Continue with Virginia Tech".
- Pending email confirmation: opens Login directly with VT accents and the
  change-school link.
- Signed-in returning user (`-HokieVisualQA`): skips Welcome and onboarding,
  lands in tabs with VT accents; Profile shows the Virginia Tech chip.

Not verified: tapping through Welcome → picker → Login (no simulator tap
automation available; Simulator runs headless), and a real Supabase sign-in.
The session-restore path in `restoreSession()` is unchanged.

### Stage 3 — Home and Degree Progress (phase 4)

Data sources, calculations, and actions are unchanged: GPA/credits from
`AppState`, transcript audit via `DegreeAuditViewModel.runAudit`, DARS via
`DarsAuditViewModel.upload`, caches from `appState.latestDegreeAudit` /
`latestDarsAudit`, tutoring sheet, refresh, DARS import/replace/remove.

Home (`HomeView.swift`, rewritten layout):

- Header: time-of-day greeting with first name; eyebrow is the school;
  subtitle is the program (latest audit's major + degree, else profile major)
  and "Class of <year>" when set.
- "Next step" card, chosen from real state only: no transcript → import
  transcript (opens the same `TranscriptView` sheet Profile uses); transcript
  but no audit yet → open Degree Progress; audit with "attention" groups →
  review those; remaining groups → review remaining; all groups complete →
  confirm with official audit and advisor (no graduation promise).
- Degree progress card (only when an audit exists): percent, credits, groups,
  and a source note ("Estimated from your transcript", plus DARS prepared
  date when on file).
- "From your transcript" stats (credits, GPA, courses, grad year) appear only
  with a transcript; no placeholder numbers. GPA icon keeps its grade-band
  color. One column at accessibility text sizes.
- Advisor entry point kept. VT tips now titled "Tips for Virginia Tech" and
  shown only for VT students (resolves decision 3 for Home; onboarding's
  "Let's Go, Hokies!" is still pending).

Degree Progress (`DegreeAuditView` in `ContentView.swift`):

- Title "Degree Progress"; eyebrow is the school; subtitle is the program
  from the DARS audit, else the transcript audit, else the profile major.
- With an official DARS audit on file it leads; otherwise the transcript
  estimate leads. Both stay on the screen.
- "Transcript estimate": source line "Estimated by Agora from your imported
  transcript", "Updated <time>" only when calculated this session (new
  `DegreeAuditViewModel.calculatedAt`; restored caches have no timestamp in
  the app, so none is shown), and a note that DARS takes priority when both
  exist. Summary card shows program, school, catalog year.
- Requirement groups: Needs attention / Remaining (all, previously capped at
  14) / Completed (all, collapsible, previously capped at 8). DARS sections
  are no longer capped at 12.
- "Official audit (DARS)": import/replace/remove kept; loaded subtitle shows
  only real fields (prepared date, file name). Summary adds school, catalog
  pill, and the audit's graduation term when present. Status colors for
  complete / in progress / open / planned are unchanged.
- Empty state (no transcript, no DARS): explains both sources, states that
  transcript estimates cover the Computer Science B.S. only, and offers
  "Import transcript" and "Import DARS audit" buttons.
- No "verified" labels, confidence scores, or graduation guarantees.

Shared: `HokiePageHeader` title now scales with Dynamic Type (capped at 52pt,
wraps to two lines) and its stat row stacks when it doesn't fit.

Debug QA: `-HokieVisualQAEmpty` (with `-HokieVisualQA`) signs in the sample
student without transcript data, for empty states.

Verified on the iPhone 18 Pro simulator: Home and Degree Progress, populated
and empty, light and dark; both at Accessibility XL text. Bottom inset
(`HokieChrome.contentBottomInset`) kept on both screens.

Not verified: a loaded DARS audit (no sample DARS exists in QA mode; layout
built from the same cards), scrolled-to-bottom positions (no simulator scroll
automation), and Home's degree-progress card in QA mode (the sample audit
only loads when the Audit tab opens; in real use it also comes from the
Supabase restore).

### Stage 4 — Advisor (phase 5)

Visual only. `ChatViewModel`, `APIService`, request payloads, prompts, model
settings, streaming, cancellation (switching or clearing chats supersedes the
active request), truncation/interruption handling, saving, memories, and the
attachment pipeline are unchanged. `ChatViewModel.swift` is not modified.

`ChatView.swift`:

- Header: "Advisor", school eyebrow, subtitle "Academic advising for your
  degree, with study help when you need it." (shorter at accessibility
  sizes). History and new-chat buttons are 44pt, school accent.
- Empty state: removed the decorative sample graph and non-interactive topic
  chips. A context card states only what the app sends: "Questions include
  your transcript (N courses) and N saved memories", or, without a
  transcript, an "Import transcript" button (same `TranscriptView` sheet).
  Suggestions in two groups:
  - Plan your degree: What requirements do I have left? / Explain my latest
    degree audit. / What prerequisites am I missing? / Help me prepare for my
    advising appointment.
  - Study help: "Help me understand a course topic…" (puts "Help me
    understand " in the composer and focuses it instead of sending) / Show
    me BFS on a graph with a visual.
  The struggling-course suggestion is kept. Other suggestions send exactly
  as before (`vm.inputText` + `sendMessage()`).
- Messages: user bubbles use the school accent with `.body` text; an
  attachment's "📎 name" line shows as a paperclip chip. Advisor answers get
  a small "Advisor" label and render with `MarkdownBody` at `.body` size
  (was `.subheadline`).
- Truncation/interruption: the notes `ChatViewModel` appends are still stored
  and sent unchanged; the bubble strips them only for display and shows
  "Answer was cut off. Ask to continue." or "Answer interrupted before it
  finished." labels. Continue chip is now a filled school-accent capsule.
- Loading: typing indicator is accent dots plus "Thinking" (VoiceOver:
  "Advisor is responding"). Streaming cursor uses the accent.
- Errors: banner text is primary-colored and wraps; the draft-restore logic
  is unchanged.
- Composer: placeholder "Ask about your degree or a course", `.body` font,
  accent cursor and send button, 44pt send target, red over-limit message.
  Attachment menu rows and chip use the school accent; remove button 32pt
  with a VoiceOver label. The microphone button is still the existing
  placeholder (no voice input); decide whether to remove it.
- History sheet: school accent, serif empty-state title, 44pt controls,
  titles up to three lines, date and count on one wrapping line.

`ContentView.swift`: graph diagrams and step controls use `theme.accent`
(path/highlight) and `theme.secondaryAccent` (current node), which are the
same VT maroon/orange as before; highlighted node text uses `onAccent`. The
YouTube resource card icon uses the accent.

Debug QA: `-HokieVisualQAChat` (with `-HokieVisualQA`) loads a long sample
conversation: lists, long display math, inline math, a four-step graph, a
code block, an attachment, and cut-off and interrupted answers.
`-HokieVisualQAChatError` adds an error banner; `-HokieVisualQAKeyboard`
focuses the composer.

Verified on the iPhone 18 Pro simulator: empty state with and without a
transcript (light/dark/Accessibility XL); long conversation in light and
dark (wide equation scrolls horizontally inside its card, graph stepper,
code block, attachment chip, status labels); error banner; Accessibility XL
conversation; composer focus.

Not verified: the on-screen keyboard layout (the simulator uses a hardware
keyboard, so no software keyboard appears; the keyboard-avoidance code is
unchanged), the Continue chip (it only appears after a live streamed answer
stops at the length limit), live streaming, and real attachment picking.

### Stage 5 — Profile, Help & FAQ, remaining screens (phases 3b, 6)

Account, transcript, privacy, appearance, memory, sign-out, Clear Local Data,
and Reset Account logic is unchanged (`resetAccount`, `signOut`,
`clearLocalAccountData`, profile sync, `ChatHistoryStore`). Stored keys
(`vtPID`, `vtEmail`, …) are not renamed.

School labels from existing configuration: `SchoolTheme` gains
`studentIDLabel` ("PID") and `communityName` ("Hokie"), matching
`institutions.student_id_label` and `branding.community_name` in the 005 VT
seed.

Profile (`SettingsView.swift`):

- Header: school eyebrow, "Your school, records, and account."
- Card: avatar in school accent (person icon when no name; the old "HK"
  placeholder is gone), editable name in serif, email, GPA.
- "School & Program" group: School, Program (read-only; not editable in the
  app), PID (label from theme; shown when set), editable Grad Year.
- Transcript row now opens the existing Transcript sheet when a transcript
  exists too, so students can review courses and re-upload (previously the
  row was inert once imported).
- Groups reordered: School & Program, Transcript, Chat Memory, Appearance,
  Help & About, Account. Section titles are headers for VoiceOver; rows are
  at least 52pt and stack label/value at accessibility sizes.
- New "Help & FAQ" row opens `HelpView`.
- Clear Local Data alert title now matches its row (was "Clear All Data").

`HelpView.swift` (new): collapsible FAQ. Every answer was checked against code:

- Schools: built from `SchoolTheme.supported`; transcript estimate is CS B.S.
  only (audit engine), DARS import and advisor available otherwise.
- Transcript import: Profile/Home/Degree Progress entry points; PDF/PNG/JPEG
  (`TranscriptView` file importer); AI extraction on the server.
- DARS import: PDF/PNG/JPEG; replace/remove; takes priority when on file.
- Review/correct: review and re-upload in Transcript (replaces previous
  import); current-class status; name and grad year editable; individual
  courses and program not editable; DARS replace/remove.
- Advisor can: context sent per `ChatRequest` (transcript, in-progress
  courses, program, memories); attachments per `ChatAttachmentProcessor`
  (photos compressed, text PDFs up to 30 pages, text files).
- Advisor can't: no school-system access, AI can be wrong, scanned PDFs not
  read, no voice input.
- Saved chats: auto-save, history reopen/delete; attachment bytes not stored.
- Memories: manual add, recurring-topic capture, model-extracted facts;
  edit/delete/delete all; synced deletes when signed in
  (`syncDeleteMemory`).
- Account and data: Sign Out keeps account data; Clear Local Data is
  device-only (`ChatHistoryStore.deleteAll` does not sync deletes); Reset
  Account deletes the auth user via the `account` function, and user-owned
  rows cascade (README). The FAQ does not claim deletion of uploaded files in
  Storage, since the `account` function only deletes the auth user; verify
  Storage cleanup separately.

No support contact, privacy promise, integration, or endorsement was added.

Branding replaced: "Hokie Advisor" → "Agora" in Terms and Privacy (product
name only) and the legal sheet subtitle; Privacy's deletion paths now name the
real controls ("Profile → Clear Local Data", "Profile → Reset Account &
Restart"). Onboarding's final button reads "Let's go, Hokies!" from
`communityName` (plain "Let's go" without a school). VT terms (PID, @vt.edu,
DARS, Pathways, Virginia Tech resources) are kept.

Remaining screens moved from VT constants to the school theme: Transcript
sheet, onboarding steps (option tiles, appearance tiles, primary buttons now
`.agoraPrimary`), Tutoring sheet and resource cards, Chat Memory editor,
Legal sheet. No `.vtBurgundy` / `.vtOrange` uses remain outside their
definitions; `hokieStone` stays as a neutral gray for "not started" status.

Debug QA: `-HokieOpenProfileSheet help|memories|transcript|terms|privacy`
opens that sheet; `-HokieExpandFAQ` expands all answers.

Verified on the iPhone 18 Pro simulator: Profile with and without a
transcript (light, dark, Accessibility XL), Help & FAQ collapsed and expanded
(light, dark), Chat Memory editor, Transcript sheet with data, Terms sheet.

Not verified by tapping: Sign Out, Clear Local Data, Reset Account (their
code is unchanged; Reset would delete a real account), memory add/edit/delete,
grad-year editing. Known limitation: at Accessibility XL a long name
truncates in the single-line name field.

Needs owner review (decision 4): Terms/Privacy still say "Last updated: May
2026", describe Agora as "an independent student project", and Privacy's
Contact line points to "the Virginia Tech CS department", which is not an
Agora support channel. Only the product name and control names were changed.
