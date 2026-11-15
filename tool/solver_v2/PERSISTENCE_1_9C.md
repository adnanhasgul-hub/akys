# AKYS V2 — Stage 1.9C: emulator persistence and authorization

Base: `2e44edb78ef408eca6e968ab466d913199d15505`, branch `feature/akys-v2-solver-core`.
No production reads/writes, Firebase deployment, push or merge. The existing V1 entry,
Auth service, solver, 19-component quality model, strategies and A/B protocol are unchanged.

## Data and authorization

The existing `FirebaseAuthService`/`AuthGate` and boolean `admin` custom claim are reused.
UI authorization is supplemented by authorization at every repository operation and
Firestore Rules. A transient claim refresh hides, but retains, the unsaved workspace;
sign-out or denied authorization disposes private state. No new identity system exists.

New namespace (no overlap with V1):

- `v2_schedules/{id}`: schema, calendar year/month, latest version, draft/archived status,
  actor, server timestamp, operation ID, summary, original creator/time, source ID/version.
- `versions/{version}`: immutable copy of the header plus the complete JSON `payload`.
- `events/{operationId}`: action, actor, server timestamp, version, operation ID.

Payload contains the immutable Problem message, stable doctor IDs/names, roles,
REQUIRED/OPTIONAL requirements, clinical/personal caps, must/cannot dates, previous
month dates, manual holidays, exact difficulty data, assignments (-1 for empty),
locks, deterministic date/role/ordinal slot IDs, and exact rational clinical quality.
Dates use existing UTC calendar serialization. Round trip checks slot identity and
header/month agreement. Unknown root fields (including proof flags) are rejected.
Stored quality is independently recomputed; a mismatch is a warning, never authority.
Incomplete REQUIRED drafts can be saved. Clinical-invalid or transition drafts remain
unapproved; locked invalid/transition restores are read-only previews, with reoptimization
requiring a new A/B evaluation. Proof/session objects are never persisted or revived.

`DraftSnapshot`, `FirestoreDraftRepository`, `DraftSession` separate serialization,
transactions and local editing state. One save atomically creates the immutable version,
updates the head and appends its matching event. Rules require all three writes.
Expected-version checking rejects stale writers. The same operation ID is retained after
an uncertain failure; retry verifies the already committed payload/actor/status/summary
rather than creating duplicate versions. Local changes survive failures and late save
acknowledgments. A month change creates a new schedule; existing month headers are immutable.

Client payload budget: 650,000 UTF-8 bytes, below Firestore's 1 MiB document limit.
Rules additionally cap payload string size. Payload is opaque draft data to Rules: Rules
cannot validate clinical semantics. All permanent approval writes are therefore denied.
Lists and version history currently load the last 100 entries; each loaded version includes
its payload. This is bounded but not a production pagination/index-cost solution.

## UI and revision behavior

V2 gains Save/retry, saved drafts, new draft, last acknowledged save/version, revision,
version history, archive and disabled approval controls. Unsaved-data confirmation protects
opening another draft, new draft and logout; route back navigation warns. Browser tab close,
OS termination and reload do not promise unsaved recovery or a browser beforeunload dialog.
Saved drafts reopen after browser reload from the emulator server (not only a local cache).

Revision creates a separate draft ID/version 1 linked to the source ID/version. Original
versions cannot be overwritten or deleted by any client, including an admin. Archived or
server-seeded approved heads cannot be updated. Source relationships remain immutable.
There is no delete operation; archive is the supported equivalent. Editing/reoptimization
never reuses an old optimality proof. A newly computed result remains subject to the existing
explicit accept/reject workflow.

## Approval and audit trust boundary

**Permanent approval is closed for both A and B results**, including otherwise valid A
schedules, until trusted server-side clinical validation exists. B previews can be saved;
serialized proof flags do not authorize B or approval. Client `approved`, `proved`, forged
admin fields and fabricated transition authorization cannot enable approval.

Draft creation/update/revision/archive events must accompany their transaction. Actor is
bound to `request.auth.uid`, timestamp to `request.time`; event update/delete is denied.
The UI's approval explanation records `approvalAttempt` and `approvalRejected`. These are
client-reported attempts, not independently observed server approval decisions. A malicious
client can omit reporting an attempted denied write, or report an attempt it did not make.
No trusted comprehensive audit trail or successful-approval service is claimed. Admin SDK
or project-owner access is outside client Rules, as usual. Successful approval events are
not accepted from clients. There is no production server approval component in this change.

## Local operation

`lib/main_v2.dart` remains the existing offline V2 entry. New
`lib/main_v2_firebase.dart` explicitly requires loopback emulator configuration and uses
`demo-akys`; without it the application refuses to connect. No production configuration
is silently reused. Existing `akys-d708a` deployment configuration is unchanged.

From repository root, with Flutter/Dart, Java, firebase-tools and test dependencies installed:

```sh
bash tool/solver_v2/start_v2_emulators.sh
bash tool/solver_v2/build_v2_firebase_web.sh
# In a separate process, against already running LOCAL emulators:
node tool/solver_v2/web/seed_auth_emulator.cjs
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 python3 tool/solver_v2/web/run_v2_firebase.py
```

The start script imports/exports emulator data outside the repository by default, to
`../akys-v2-emulator-data`; use graceful emulator shutdown for export. Export/import across
emulator restarts is supplied by Firebase CLI, not a tested custom backup implementation.
The seed script creates only demo emulator accounts (not production credentials).
Android emulator build uses `AKYS_V2_EMULATOR_HOST=10.0.2.2` with the same connected entry.

## Verification and observed limitations

Environment: Linux x64, Flutter 3.47.9, Dart 3.13.7, Java 21, Chromium 154.0.8037.57.
Web is a release JS build with actual compiled solver Worker; Android is a debug APK.

- Full Flutter regression suite: final result recorded in `results/stage_1_9c_validation.json`.
- New persistence/widget tests: 21 PASS (serialization, invalid draft, locks, month transition,
  idempotency, lost acknowledgment, version conflict, revision, archive, authorization,
  rejected approval, AuthGate refresh and UI save/open flows).
- Chromium regression suite: 57 PASS, including existing 36 and new 21.
- Real Worker acceptance: 18/18 PASS; see `results/stage_1_9c_worker.json`.
- V2 Firestore Emulator security assertions: 45 PASS, including actual SDK concurrent
  transactions (one winner), rollback, nonadmin/anonymous access, fake claim types,
  fake approval/proof, immutable versions/events, month tampering and seeded approved data.
- Existing V1 Rules regression: PASS, including public-share capability restrictions,
  projection allowlist, settings reads and complete month-create transaction.
- Real Flutter/Auth/Firestore Chromium flows: save incomplete draft with doctor+lock,
  reload/list/open, offline transaction failure and online idempotent retry, revision/history,
  disabled approval/rejected audit, and nonadmin rejection. See `stage_1_9c_browser.json`.

A browser account-switch limitation was observed: immediately signing into a different
account after the offline/reconnect/logout sequence produced a generic Auth error. Reloading
then signing in correctly reached the denied screen. The successful acceptance test explicitly
reloads between accounts; seamless same-document account switching after that sequence is
NOT claimed verified. The existing shared V1 Auth implementation was not modified to mask it.

Physical Android device interaction was not performed. APK compilation is not device-level
Firebase/runtime validation. No production persistence, production Rules deployment, cloud
approval or production audit validation was performed. Pre-existing Cupertino font/Kotlin/
SDK metadata build warnings are separate from successful compilation. Future work should add
trusted server approval/audit, production pagination/index planning, tab-close draft recovery,
and investigate the emulator account-switch behavior before a production rollout.
