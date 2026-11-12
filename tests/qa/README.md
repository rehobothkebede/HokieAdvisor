# Local client regression checks

Run from the repository root on macOS with Xcode and Deno installed:

```sh
bash tests/qa/run_client_smoke.sh
deno test --no-lock --allow-read --allow-env backend/supabase/tests
```

The client runner starts two loopback servers, compiles the real Swift API service,
chat view model, course client, response models, graph parser/layout, and math text
parser, then executes assertions. Servers are stopped when the runner exits; its
temporary log directory is printed. Ports 8791 and 8792 must be free.

The course server applies local migrations to an ephemeral PGlite database and
uses the real course HTTP handler, with synthetic syllabus extraction recordings.
The chat server sends synthetic success, truncation, interruption, empty, and
rate-limit responses. The test uses fixture PDFs and two local test identities.

`ClientStubs.swift` replaces only authentication/configuration, chat persistence,
and the syllabus extractor's payload types. It contains no production secrets.
PDFKit reads the fixture PDF for the upload test. No hosted services, real student
records, or OpenAI calls are used by these runners.

These are macOS-hosted checks of shared Swift logic and wire compatibility, not
iOS UI tests. They do not prove on-device OCR, notification delivery, real model
answer quality, Keychain sign-in, or visual accessibility. Use an iOS simulator or
device for those acceptance checks.

The migrations test harness currently requires the locally present
`005_multi_institution.sql`; that file must be reviewed and included in source
control before these tests can reproduce from a clean clone.
