# AKYS V2 1.9D — migration, approval and rollout boundary

Base e6d88210b3e3bfc8f6a6fddef716bb39d1718ff9; local feature branch only.

## Dependency-led retirement

V2 imports only solver_v2, core/auth and core/design. The import scan found no dependency
on V1 application, modules/work_schedule, operative_notes, old theme/module registry or
export platform helpers. Those V1-only paths and exclusively V1 UI/solver tests were
removed. Independent shared design tests were retained. archive/share_plus and their
unused transitive dependencies were removed. Historical reports/benchmark results and
existing production configuration, Android package ID and Firebase app IDs are retained.
Legacy Rules tests are retained as data-protection regression checks, not V1 application
support. No stored collections, shared projections or Firebase users were deleted.

## Standard application

lib/main.dart now starts the authenticated V2 application and FirestoreDraftRepository.
Default compilation uses the existing DefaultFirebaseOptions for akys-d708a. No production
instance was run or accessed during this work. Explicit AKYS_V2_EMULATOR_HOST selects the
isolated demo-akys backend. Invalid nonempty hosts fail closed. Firestore disk persistence
is disabled; repository reads require server access. lib/main_v2.dart is retained solely
as an offline UI/Worker acceptance harness. The redundant connected entry was removed.
The Hosting workflow packages the separate compiled Dart Worker after the normal build;
no workflow was triggered and nothing was deployed.

## Session isolation and Auth emulator startup

AuthState carries authenticated UID. The private V2 owner disposes DraftSession,
ScheduleWorkspace and its OptimizationController when UID changes, on sign-out or denial.
A new user cannot inherit the prior user's editor, undo/redo, locks, pending save or Worker
results. Late futures see the disposed session; runtime run IDs also reject stale messages.
Same-user token refresh hides private content while retaining the unsaved workspace and mounted page state. A single idTokenChanges subscription avoids duplicate resolutions. Per-workspace widget keys prevent State reuse across users; private dialogs are closed on UID change/denial. A pending save does not prevent explicit confirmed logout; an already server-accepted write cannot be rolled back, but its late acknowledgment cannot modify the next session.
Explicit authorization refresh supports claim grant/revocation without a document reload.

The 1.9C account-switch reproduction exposed a release-mode emulator startup problem:
Firebase.initializeApp waits for Auth's persisted-user restoration BEFORE Dart can call
useAuthEmulator. On reload, accounts:lookup could go to the remote Auth endpoint with a
demo key; the emulator connection could then fail to take effect for subsequent login.
The emulator release build now bootstraps the same pinned Firebase JS SDK and connects
Auth to loopback BEFORE Flutter/plugin restoration. This shim is ONLY copied into
build/v2-firebase and is never part of production web/index.html or build/web.
Production Auth uses its normal trusted configuration, with no emulator shim.
Playwright additionally blocks and records external Firebase API requests. Test typing
waits for Flutter focus and asserts input content to avoid losing the first character.

## Cursor pagination and costs

Draft browsing reads 20 headers plus one lookahead, ordered by server timestamp descending
then document ID descending. It no longer downloads a payload for every head. Selecting a
row reads exactly its selected immutable version. History uses numeric version descending
plus document ID, 20 + 1 per page; it has no 100-version ceiling. Version documents contain
payloads, so history still transfers up to 21 payloads per page; Firestore client SDK has
no field projection. A future metadata index could reduce bytes, but is not falsely claimed
implemented here. Header listing does not do N+1 reads. No new composite index is required
beyond the existing single-field plus document-ID order.

Pagination is live, not an immutable collection snapshot: concurrent head updates can
move rows. UI deduplicates id/version; refresh to see newly inserted/moved rows. Immutable
version history does not have that moving-row problem. Unit fixtures exercise 125 heads
and 125 versions with tied timestamps. Save still writes three documents atomically;
normal transaction reads event + head (plus source on revision), followed by acknowledgment
read of version; SDK contention retries may add reads. Cost numbers are document-operation
bounds, not production billing measurements.

## Trustworthy clinical approval — remains closed

Dart VM is technically suitable for a trusted container running the existing validator;
there is no need to translate the solver to JS or introduce another solver. However this
repository has no authenticated approval service, deployed trusted Dart execution endpoint,
IAM/service-account separation, Firebase ID-token verification boundary or server-side
idempotent approval transaction. A client cannot provision that trust by setting a flag.
No unverified server prototype is exposed as a secure approval implementation.

A future approval service must verify signed Firebase ID tokens and admin claims, fetch an
immutable version by ID server-side, run the SAME Dart validator against that payload,
reject transitions (B remains closed), bind validation to the exact version/hash, and commit
approval + immutable server audit atomically with optimistic version/idempotency checks.
No client-supplied proof is authority. Even a valid A draft stays unapproved until that
trusted deployment is independently tested. Current Rules deny all client approval writes.

## Production data migration plan (not executed)

1. Back up production via an authorized owner-managed export; inventory V1 collections,
   users and existing share links. Do not delete or automatically rewrite them.
2. Independently review/deploy V2 Rules BEFORE any V2 production rollout. Older broad-admin
   Rules alone do not provide the new immutable-version/closed-approval boundaries.
3. Verify admin claims and indexes in a controlled rollout. Main build and Worker must be
   published together. No source V1 record is silently interpreted as a V2 snapshot.
4. Legacy shared links/UI will no longer be served by the retired V1 router. Agree archival
   access and retention separately; no automatic data migration is included.
5. Only after verified retention/backup and separate explicit authorization consider V1
   collection cleanup. This task neither migrates nor deletes records or accounts.

The Hosting workflow now invokes the existing read-only active-rules verifier before
publication, failing if production Rules differ from the repository-tested source. This
future CI guard was added but was NOT run against production here. V2 anonymous list/version
probes were added to that verifier. Detailed measured results are in VALIDATION_1_9D.md.
