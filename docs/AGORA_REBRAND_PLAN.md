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
- [ ] Phase 3: Login and Onboarding (wordmark, tagline, copy)
- [ ] Phase 4: Home and Audit/DARS (tokens + copy)
- [ ] Phase 5: Advisor chat (bubbles, composer, graph/step tints; math/code untouched)
- [ ] Phase 6: Profile/Settings (footer, Terms, Privacy, policies row)
- [ ] Phase 7: `CFBundleDisplayName`, usage strings, asset catalog, icon (if approved)
- [ ] Build passes after each phase (phases 1–2: passed)
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
- Login still shows "Hokie Advisor" and explicit VT accents (phase 3).
- The neutral Agora theme was not seen on-device: the simulator already had a
  VT email stored. `vtEmail` is not cleared on sign-out, so a signed-out
  returning student keeps VT accents on Login; decide if that is wanted.
