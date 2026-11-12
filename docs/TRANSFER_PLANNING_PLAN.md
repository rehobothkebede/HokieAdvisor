# Transfer Planning: Implementation Plan and Data-Readiness Assessment

Status: **proposal, awaiting approval.** No code, schema, or migration has been changed for this feature.
Prepared 2026-11-09 from the repository on branch `codex/agora-rebrand` and from official sources checked the same day.

---

## 1. Summary

Agora can support a credible first transfer pilot: **Northern Virginia Community College (NOVA) → Virginia Tech, Computer Science B.S.**, for students entering VT in the **2026–2027 catalog year** (Summer 2026 – Spring 2027).

Virginia Tech is the only proposed destination with all three of the following today:

1. **An official, structured equivalency source.** The VT Office of the University Registrar publishes year-labeled VCCS equivalency tables, with explicit notation for exact equivalents, electives, no-credit courses, combinations, and department review.
2. **Destination degree requirements already modeled in Agora.** The CS B.S. requirements live in `backend/data/catalog/computer_science.json`, with a deterministic audit engine. They need updating from catalog 2025–2026 to 2026–2027.
3. **Existing institution support.** VT is the app's only supported institution, and migration 005 already models institutions by stable ID.

UVA and JMU publish transfer-equivalency tools, but I have not assessed their formats or their CS degree-requirement data. They are **future expansion**, not pilot scope.

Several prerequisites must be resolved before or during the pilot (Section 4). The most significant is that **Agora cannot onboard a NOVA student today**. Every account resolves to Virginia Tech, and the transcript parser only reads VT transcripts. Section 6 asks you to choose how the pilot handles this.

---

## 2. What exists today (repository inspection)

| Area | Current state | Implication for transfer planning |
|---|---|---|
| Roadmap | **No roadmap or editable plan exists.** "Planned courses" are only what the AI transcript parser extracts (`AppState.plannedCourses`) and are read-only. `PlanViewModel.swift` contains the degree-audit view model. The FastAPI `advisor.py` has an AI "next semester plan" endpoint, and the CS JSON has a static `four_year_plan`. | The "connected roadmap" must be built new. Scenario coursework cannot reuse a roadmap that doesn't exist; it can reuse transcript, in-progress, and parser-extracted planned courses. |
| Course model | `TranscriptCourse { code, name, credits, grade, semester }`; `InProgressCourse { code, name, credits, semester }`. **No school/institution field.** | Courses can't currently say which school they came from. Scenario courses need their own records that carry the original school, code, credits, grade, and term. |
| Transcript import | Edge function `transcript/index.ts` uses an AI prompt: "You are parsing a Virginia Tech student academic transcript… Use VT format SUBJECT NNNN." Transfer credit without a VT number becomes `SUBJ 1XXX`. | A NOVA transcript (3-digit VCCS codes, such as `CSC 221`) isn't supported. AI extraction of a transcript is acceptable as data entry, with student confirmation, but must never decide equivalency. |
| Degree audit | Production path: edge function `audit/index.ts`, mirrored by `degree_audit_service.py`. Hardcoded: "Degree audit currently supports Computer Science B.S. only." C-or-better rules; transfer grades (T, TR, TRANSFER) count for exact mapped VT codes. | A good basis for evaluating "after transfer" requirements. It must become spec-driven, using the `degree_audit_specs` table from migration 005, and must report allocations so nothing is double-counted. |
| Institutions | Migration **005 is untracked and not applied**. It adds `institutions` (VT seeded with a fixed UUID), `degree_audit_specs`, institution-scoped catalog tables, and `profiles.institution_id`. Migration 006 (`chat_usage`) is committed. | The transfer schema depends on 005 and should be **007 or later**. 005's notes say its own deployment requires sync-script changes. |
| Accounts / theme | `SchoolTheme.supported = [.virginiaTech]`; `forAccount(email:)` falls back to VT; `handle_new_user()` defaults to VT. | A NOVA student would be themed and modeled as VT today. The account's school must not be silently changed; see Decision 1. |
| VT catalog data | `vt_catalog_202601.json` has course codes, titles, credits, descriptions, and **prerequisites as free text**. The CS JSON has structured prerequisites only for its four-year-plan courses. | Prerequisite checking against destination equivalents is reliable only for courses with structured prerequisites. Other courses get "prerequisites not evaluated." |
| RLS pattern | User-owned tables use `auth.uid() = user_id`, plus composite `(id, user_id)` foreign keys (migration 004) so child rows can't point at another user's parent. Reference tables are select-only. | Reuse this pattern unchanged for scenarios. |
| AI | Chat edge function with memory and context. | It may *explain* a stored, sourced evaluation result. It must never produce equivalencies or credit decisions. |

---

## 3. Official data sources (checked 2026-11-09)

### Usable for the pilot

**VT Registrar: VCCS Equivalencies**
- Landing page: <https://transferguide.registrar.vt.edu/VCCS-Equivalencies.html>
- Current edition: <https://transferguide.registrar.vt.edu/content/transferguide_registrar_vt_edu/en/VCCS-Equivalencies/VCCS-Equivalencies-2026.html> ("Summer 2026 – Spring 2027")
- Policy page: <https://transferguide.registrar.vt.edu/Transfer-Requirements/VCCS-Transfer.html>
- HTML editions cover Summer 2021 through Spring 2027; PDF editions cover 2015–2016 through 2020–2021.
- Table columns: `VCCS Course Number | VCCS Course Title | VCCS Credits | VT Course Number | VT Course Title | VT Credits | Comments`
- The notation maps onto the required outcome categories:

| Source notation (verbatim examples) | Agora outcome |
|---|---|
| `CSC 221 → CS 1064` (3 → 3) | Documented course equivalency |
| `ACC 105 → BUS 1XXX "Business Elective"`; `VT 1XXX` | Credit as a subject or general elective only |
| `ENG 100 → VT XXXX "No Virginia Tech Credit", 0` | Documented nontransferable |
| "College of Engineering will consider direct equivalent credit when syllabus is provided." | Needs institutional review |
| `CSC 205 + CSC 215 → …` with "Both courses are required to receive equivalent credit." | Combination rule (all sending courses required) |
| `CSC 222 → CS 1114 + CS 1XXX` (4 → 3+1), "If taught in a language other than Java, please see your advisor." | Split credit plus a condition. The condition is shown to the student; it isn't auto-decided. |
| "With Passport or UCGS, applies to General Education, Pathway 1F." | Pathways credit **only when** Passport or UCGS completion is documented |
| "A grade of B is required for degrees in chemistry." | Major-specific minimum grade |
| Any course with no row | Needs review. Missing data is never treated as "won't transfer." |

- Disclaimers to show in the app: "The provisions of this Transfer Guide do not constitute a contract…" Credit is evaluated "after you accept Virginia Tech's offer of admission," and the dean's office or department decides.
- The policy page also says "the Associate of Applied Science degree does not transfer." An AAS must never be treated as a transfer degree.

**VT CS B.S. degree requirements**
- Agora has 2025–2026 data, sourced from the advising guide PDF in `backend/data/catalog/`.
- VT states: "Degree requirements are determined by your catalog year, which is your date of entry to Virginia Tech." A student entering in Fall 2027 follows the 2027–2028 catalog.
- **The 2026–2027 CS checksheet must be obtained and modeled for the pilot.** The 2025–2026 data only applies to students who entered in 2025–2026.

### Located but not usable without further work

| Source | Status |
|---|---|
| Transfer Virginia, VT CS B.S. Transfer Guide 2025–2026 (<https://www.transfervirginia.org/node/6904>) | Exists, but the site returned **HTTP 403** to automated requests. Contents are unverified. It needs a manual download by the team, and its terms of use need review. |
| Transfer Virginia, UVA CS B.S. Transfer Guide 2025–2027 (<https://www.transfervirginia.org/node/6845>) | Same 403 block. |
| UVA Transfer Credit Analyzer, College of Arts & Sciences (<https://ascs8.eservices.virginia.edu/asEquivs>) | Exists. UVA says it is not exhaustive. "T" codes (such as 1000T) mean transferable credit with no exact equivalent. UVA Engineering keeps a separate list (<https://engineering.virginia.edu/undergraduate-study/future-undergrads/transferring-uva-engineering/transfer-credit-equivalency>). Format not assessed. |
| JMU: VCCS general education equivalents (<https://www.jmu.edu/transfer/vccs-transfer/genedequiv.shtml>) and the registrar VCCS page (<https://www.jmu.edu/registrar/prospective-student/from-vccs.shtml>) | Exist. JMU documents C-or-better (C- doesn't transfer), "AND" sequences, and a limit on gen-ed transfer courses. The full equivalency database URL wasn't located. |

### Verified facts versus open questions

Only the VT registrar pages above were read directly. The UVA and JMU facts come from search-result summaries of their official pages and **must be re-verified** before any expansion.

---

## 4. Data-readiness gaps

Each gap is classified as blocking the pilot, handled as a flagged assumption, or outside pilot scope.

| # | Gap | Effect | Handling |
|---|---|---|---|
| G1 | **Which equivalency edition applies to a course** isn't stated by VT. | Edition choice changes outcomes. | **Assumption, flagged in the app:** use the edition covering the term the course was taken. Planned courses use the current edition and are marked "may change." Confirm with VT (transfercredit@vt.edu) before launch. |
| G2 | A general **VCCS minimum grade** isn't stated on the registrar pages read. A VT advising document (sas.vt.edu, "Steps to Transfer Credits") says only C or better transfers. | Grade failures can't be cited authoritatively. | **Blocking for launch:** find the governing VT catalog or registrar statement and record it as a source. Until then, show "minimum grade rule: needs confirmation." |
| G3 | **Residency** (minimum VT credits) and **maximum transfer credit** weren't found. | Remaining-terms estimates and transfer limits can't be computed. | **Blocking for estimated terms only.** Source them from the VT undergraduate catalog. Without them, Agora shows no term estimate. |
| G4 | **VT CS 2026–2027 requirements** aren't in the repo. | "After transfer" can't be evaluated for the pilot catalog year. | **Blocking.** Model the 2026–2027 checksheet as a `degree_audit_specs` row with source links. |
| G5 | **Transfer Virginia guides** block automated access. | Major-specific pathway guidance and admission prerequisites are unavailable. | Not required for credit evaluation. Optional manual ingestion after a terms-of-use review. |
| G6 | **CS major admission criteria** for transfer students weren't verified. | — | Kept separate: show "Admission to Virginia Tech and to the CS major is decided separately and is not assessed here," with a link. No admission predictions. |
| G7 | **Source anomalies.** Example: the CSC 205+215 row lists "CSC 2505", which looks like a typo for CS 2505. Some cells are blank and credit formats vary (`3-4`, `3+1`, `3 OR 3+1`). | Auto-correcting would invent data. | The parser **never corrects** codes. Anomalous rows are stored verbatim and marked needs review; a human reviewer can approve a documented interpretation. |
| G8 | Only part of the 2026 table was verified during this assessment, and MTH 263/264 rows are unconfirmed. | — | The ingestion script parses the full page. The pilot's CS-relevant rows get a manual spot check before publishing. |
| G9 | **NOVA identity and offerings.** The guide is VCCS-wide; VT notes "Individual community colleges may not offer all of the courses listed." NOVA isn't named. | — | Model NOVA as an institution in the VCCS system, with a stable ID (IPEDS UnitID, recorded at ingestion from NCES College Navigator, not from memory). Equivalency rules attach to VCCS course numbers. Whether NOVA offers a course is "not checked" unless a NOVA catalog source is added. |
| G10 | **Prerequisites** are free text for most VT courses. | — | Evaluate prerequisites only where structured data exists; otherwise show "prerequisites not evaluated." |
| G11 | VT site **Acceptable Use** terms weren't reviewed. | — | Review before automated ingestion. Run ingestion manually and infrequently, with snapshots. |
| G12 | Migration 005 isn't applied, and its own notes list deployment hazards. | The transfer schema depends on `institutions`. | 005 must ship first, or together with the transfer migration, in an approved window. |
| G13 | **NOVA students can't be Agora account holders today.** | See Decision 1. | Decision required. |

---

## 5. Proposed design

### 5.1 Principles

- **Deterministic evaluation; sources required.** Every outcome records the rule and source edition it came from. No source means "needs review."
- **Original records are never changed.** Transcripts, the account's institution, the major, and existing audits are read-only inputs. Scenarios hold copies or references and their own planned courses.
- **Credit, admission, and major admission are separate.** Only credit is evaluated. Admission is shown as an explicit "not assessed" item with links.
- **Partial over fabricated.** When data is incomplete, Agora shows what is supported, plus a checklist of what isn't.

### 5.2 Data model (new migration `007_transfer_planning.sql`, local only until approved)

**Reference data** (institution-scoped; readable by signed-in users only when published; written only by the service role):

- `institutions` (from 005), extended with:
  - `ipeds_unit_id text unique`
  - `system_slug text` (for example `vccs`)
  - `can_hold_accounts boolean`, so adding NOVA for transfer doesn't make it selectable as an account school
  - `transfer_role text[]` (`sending`, `receiving`)
- `transfer_sources`:
  - `id`, `publisher_institution_id`, `kind` (`equivalency_guide | degree_requirements | policy | articulation_agreement`)
  - `title`, `url`, `edition_label`, `effective_start_term`, `effective_end_term`
  - `retrieved_at`, `last_checked_at`, `content_sha256`, `snapshot_path` (raw HTML/PDF in private storage), `parser_version`
  - `status` (`staged | reviewed | published | retired`), `reviewed_by`, `reviewed_at`
- `transfer_equivalency_rules`:
  - `id`, `source_id`, `sending_system_slug` or `sending_institution_id`, `receiving_institution_id`
  - `sending_courses jsonb` (an ordered list where all items are required; alternatives are stored as separate rules sharing an `alternative_group`)
  - `sending_credits_text`
  - `outcome` (`equivalent | elective | no_credit | review`)
  - `receiving_courses jsonb` (code, credits, and an `elective_scope` of `subject` or `general` for XXX placeholders)
  - `receiving_credits_min`, `receiving_credits_max`
  - `min_grade`, `min_grade_scope` (for example "chemistry degrees")
  - `pathway_designations jsonb`, with the condition `requires: ["passport_or_ucgs"]`
  - `conditions_text` (verbatim comments), `raw_row`, `anomaly_flags text[]`, `review_status`
- `degree_audit_specs` (from 005), extended with `source_id` and structured `residency`, `transfer_limits`, `major_rules`, and `allocation_rules` (which buckets may share a course).

**User-owned data** (RLS `auth.uid() = user_id`, plus the composite `(id, user_id)` foreign-key pattern from 004):

- `transfer_scenarios`:
  - `id`, `user_id`, `name`, `current_institution_id`, `destination_institution_id`, `destination_program_key`, `catalog_year`, `intended_transfer_term`
  - `declared_credentials jsonb` (for example "AS in General Studies", "UCGS", "Passport"; self-reported, with status `claimed` until a document supports it)
  - `archived_at`, timestamps
- `transfer_scenario_courses`:
  - `id`, `scenario_id`, `user_id`
  - `origin` (`transcript | in_progress | parsed_plan | scenario_plan`), `transcript_course_id` (nullable)
  - `school_institution_id`, `code`, `title`, `credits`, `grade`, `term`, `status` (`completed | in_progress | planned`)
  - Original values are stored exactly as recorded and never rewritten.
- `transfer_evaluations`:
  - `id`, `scenario_id`, `user_id`, `inputs_sha256`, `source_ids uuid[]`, `engine_version`, `evaluated_at`, `result jsonb`
  - Results are stale whenever the input hash or any source version changes, which forces a re-check when the student edits the destination, major, term, catalog year, or coursework.

No existing table is altered except to add columns to `institutions` and `degree_audit_specs` (both introduced by 005). `transcripts`, `transcript_courses`, `profiles.institution_id`, and `degree_audits` are untouched.

### 5.3 Evaluation engine (new edge function `transfer`, shared TypeScript module, plus a Python mirror for tests)

1. **Load inputs.** Load the scenario, its courses, and the published rules, spec, and policies for the destination and catalog year.
2. **Choose an edition per course** by term (assumption G1, flagged).
3. **Match rules.** Combination rules are tried first, and only when every sending course is present. Each sending course is consumed by at most one rule. A partial combination produces a "needs X to earn credit" note instead of credit.
4. **Check grades** per rule (`min_grade`, or the documented default). Failures become their own category, "below required grade," and are never folded into "nontransferable."
5. **Classify each sending course** as one of:
   - documented equivalency
   - elective-only (subject or general)
   - documented no credit
   - needs review (missing, anomalous, or department-review rule)
   - below minimum grade
   - conditional (in progress or planned; counted only in "if completed as planned" totals)
6. **Prevent duplicate credit.** The same receiving course is counted once; repeats are flagged.
7. **Allocate to destination requirements** using the spec's allocation rules. Each receiving credit fills at most one bucket unless the spec explicitly allows sharing, and every allocation is recorded. This is the no-double-counting guarantee.
8. **Apply Pathways designations** only when Passport/UCGS completion is documented. Otherwise mark them "would apply if Passport/UCGS is completed." An associate degree never waives general education unless a sourced agreement in `transfer_sources` says so.
9. **Check prerequisites** for remaining destination courses using equivalents, where structured prerequisite data exists (G10).
10. **Apply residency and transfer limits** when sourced (G3).
11. **Estimate remaining terms** only when residency is sourced, every remaining requirement has known courses, and the student supplies a credits-per-term assumption. The assumptions are shown next to the estimate.
12. **Build the output:** per-course outcomes with a source citation (title, edition, URL, checked date, verbatim comment); per-requirement status; checklist items (unresolved courses, missing data, flagged assumptions, admission "not assessed"); and totals for documented transferable credits, credits applying to the degree, remaining requirements, and unresolved courses.

**AI role:** the chat function may receive a stored evaluation, with citations, as context so it can explain it. A system rule forbids stating any equivalency or credit outcome not present in the evaluation, and answers link back to the source.

### 5.4 iOS experience (Agora design system; the account's school theme stays the app theme)

- **Entry point:** a "Plan a transfer" row on the Degree Progress tab (the existing academic planning screen), below the audit.
- **Setup flow** (one question per step; Dynamic Type and VoiceOver friendly):
  1. Current institution (supported sending institutions only; pilot: NOVA)
  2. Destination and intended major (supported pairs only; pilot: VT, Computer Science B.S.)
  3. Intended transfer term
  4. Catalog year (pre-filled from the VT rule that the catalog year is the entry term's year; editable, with an explanation)
  5. Associate degree or pathway (optional; self-reported and labeled as such)
- **Scenario screen:**
  - A header card names the destination as text with a neutral badge. Destination school colors aren't used, so the app keeps the student's own school theme.
  - **Before transfer — at NOVA:** each course shows its original code, credits, grade, and term exactly as recorded, plus an outcome chip (Equivalent / Elective credit / Needs review / No credit / Below required grade / If completed).
  - **After transfer — at Virginia Tech:** remaining requirements, each with "Why it's needed."
  - **"Why does this count?"** opens a disclosure sheet with the rule in plain language, the verbatim source comment, the source title, edition, checked date, and a link.
  - A **checklist** section lists unresolved items and assumptions.
  - A persistent **"Back to my plan"** button.
- **Scenarios list and comparison:** saved scenario cards, plus a compare view showing only evidence-supported figures. Any figure the data doesn't support shows "Not enough data" instead of a number.
- **Re-check:** editing any input marks results stale and re-runs the evaluation; a banner shows when sources were last checked.

### 5.5 Ingestion pipeline (manual, reviewed, no AI)

1. `backend/scripts/ingest_vt_vccs_equivalencies.py`: fetch one edition and store a raw snapshot with its SHA-256. A deterministic HTML-table parser writes staged rows, keeping verbatim text and anomaly flags. It never auto-corrects codes.
2. A review report: diff against the previous edition, list anomalies, and print the pilot's CS-relevant rows for a human spot check against the live page.
3. A publish step (service role) marks the source `published`. Hosted Supabase is never touched without approval.
4. The same pattern serves degree requirements: a modeled 2026–2027 CS spec, with a `transfer_sources` row pointing to the official checksheet and its checked date.

### 5.6 Privacy and permissions

- Scenarios, scenario courses, and evaluations are visible and editable only by their owner (RLS plus composite foreign keys).
- Reference data is read-only for clients. Staged or unreviewed data is never visible to clients.
- Account deletion cascades scenario data, matching existing tables. The Help & FAQ text that describes deletion needs a matching update.
- Raw source snapshots go in a private storage bucket, not a client-readable one.

---

## 6. Decisions needed before implementation

**Decision 1: How a NOVA student uses Agora in the pilot (G13).**

| Option | Description | Trade-off |
|---|---|---|
| A (recommended for the pilot) | Transfer scenarios are available to any signed-in student. The *scenario's* current institution is NOVA; the account institution is unchanged. NOVA coursework is entered in the scenario manually, or imported from a NOVA transcript into the scenario only (AI extraction, then student confirmation). | Smallest change, and it doesn't touch accounts. The account would still be themed VT for a NOVA student, which is inaccurate. |
| B | Make NOVA a supported **account** institution: theme, onboarding, transcript parsing, and the Agora home experience. | Correct long-term, but much larger, and it touches auth and onboarding. Better as a follow-up project. |

**Decision 2: Pilot catalog year.** I recommend the 2026–2027 catalog (VT entry Summer 2026 – Spring 2027) with the matching equivalency edition. This requires modeling the 2026–2027 CS checksheet (G4). A 2027–2028 target would need that catalog, which may not be published yet.

**Decision 3: Engine location.** I recommend a new Supabase edge function `transfer`, matching the production audit path. FastAPI would get only a test mirror if you want parity.

---

## 7. Phases (implemented versus future)

| Phase | Scope | Status after the phase |
|---|---|---|
| 0 | Resolve G2, G3, G4, G11; confirm G1 with VT; model the CS 2026–2027 spec; decide 1–3 | Data ready |
| 1 | Migration 007 (local only), ingestion script with snapshots and review report, `transfer` edge function with the engine and tests | Backend pilot, NOVA → VT CS, data-supported |
| 2 | iOS: entry point, setup flow, scenario screen, "Why does this count?", checklist, saved scenarios, compare view, "Back to my plan" | Pilot complete for one destination |
| Future | UVA (A&S analyzer plus the separate Engineering list) and JMU (equivalency database plus gen-ed limits) as additional `transfer_sources` and rules; other majors; NOVA as an account institution; Transfer Virginia guides after a terms review | Not in pilot. No hardcoded per-school flows: adding a destination is data plus review. |

Compare view in the pilot: comparing several destinations needs more than one destination. In the pilot it compares scenarios for the same destination with different terms, catalog years, or planned coursework. Comparing VT with UVA or JMU arrives with the future phase, and unsupported destinations are listed as "not yet available" rather than estimated.

---

## 8. Verification plan (after approval)

Engine unit tests (fixtures built from verbatim source rows):
- **Exact equivalency:** `CSC 221` (grade B) → `CS 1064`, 3 credits.
- **Split credit:** `CSC 222` → `CS 1114 + CS 1XXX` (3+1), with the Java condition surfaced, not decided.
- **Elective only:** `ACC 105` → `BUS 1XXX`; counts toward free electives only.
- **Documented no credit:** `ENG 100` → `VT XXXX`, 0 credits.
- **Missing mapping:** an unlisted course → needs review, never "won't transfer."
- **Minimum grade failure:** below the documented minimum → "below required grade"; the chemistry B/A rules apply only within their scope.
- **Combination:** `CSC 205 + CSC 215` both present → credit; only one present → no credit plus a "needs CSC 215" note; the "CSC 2505" anomaly → needs review.
- **Planned and in-progress courses:** conditional, excluded from documented totals, included in "if completed" totals.
- **No double counting:** one VT course can't satisfy two exclusive buckets; duplicate equivalents count once.
- **Pathways:** applied only with documented Passport/UCGS; an AAS doesn't count as a transfer degree.
- **Staleness:** changing the term, major, catalog year, or coursework changes the input hash and requires re-evaluation.

Isolation and security tests (local Supabase only):
- Before and after snapshots of `transcripts`, `transcript_courses`, `profiles.institution_id`, `profiles.major`, and `degree_audits` show no change from any scenario operation.
- User B can't select, insert, update, or delete user A's scenarios, scenario courses, or evaluations, including by forging `scenario_id` in child rows (composite foreign key).
- Clients can't read staged or unpublished reference data.

iOS:
- Build with normal signing; test on the isolated "Agora Design QA" simulator with sample data only.
- Light and dark mode, Dynamic Type, VoiceOver for the scenario and "Why does this count?" sheets.
- Confirm the existing Home, audit, Advisor, transcript, and login (Keychain) flows are unchanged.

Out of bounds throughout: deploying, applying migrations to hosted Supabase, pushing, and merging.

---

## 9. Unsupported in the pilot (documented as such in the app)

- Destinations other than VT, majors other than CS B.S., and catalog years other than the pilot year.
- Sending institutions other than NOVA. VCCS-wide rules would technically apply, but offerings aren't verified (G9).
- AP/IB/CLEP and military credit, dual enrollment taken outside VCCS, and courses from non-VCCS schools (VT's separate Transfer Equivalency Database).
- Admission predictions of any kind.
- Course availability or scheduling at either school.
