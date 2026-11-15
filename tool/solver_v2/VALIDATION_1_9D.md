# Stage 1.9D verification and performance

Linux x64; Flutter 3.47.9, Dart 3.13.7, Chromium 154.0.8037.57, Java 21.
No production application execution or production data operation. Main production-configured
Web/Android binaries were compiled only. Browser acceptance uses demo-akys loopback emulators.

## Results

- 268 native Flutter tests PASS. The previous 501 comprised 237 retired V1-only cases;
  all V2/core tests are retained and 4 new pagination/identity/late-save tests bring the total to 268.
- 60 Chromium package tests PASS plus the updated 5-test session suite (61 distinct tests) (responsive 414/768/1440, 200% text, editing, persistence,
  pagination, reoptimization, transferred-result authorization and lifecycle contract).
- 18 actual Worker scenarios PASS; four actual Flutter/Worker flows plus 30-day scrolling PASS.
- 47 V2 security assertions PASS; retained legacy data-boundary Rules tests PASS.
- Real standard-main Flutter + Auth/Firestore acceptance PASS: complete round trip, lock,
  offline failure/retry, revision, no-refresh account switch, grant/revoke admin claim,
  fresh per-user workspace. Zero external Firebase API requests in the final test.
- Flutter analyze and dart analyze clean. Standard Web release + Worker and Android debug
  APK succeed. No connected Android device/installed ready emulator; no device interaction claim.
- Solver files, core tests, hard constraints, quality vector, defaults and Firebase IDs unchanged.

An initial overly broad Chromium invocation selected five VM-only workspace tests. They
timed out because the package-test server does not provide the compiled worker asset. Those
same tests pass natively; real Web runtime behavior is covered by the dedicated browser
harness. No failing test was deleted, skipped or disabled to obtain the final platform results.
Initial lints in new benchmark helpers were fixed; final analysis is clean.

## Measured lifecycle performance

Seed 160600; 6 doctors / 30 days and 15 doctors / 31 days; three repetitions per fixture
and mode, on the same host. Each run starts with a 2-second budget, extends by 2 seconds
after 400 ms on the same run/frontier, then cancels after another 700 ms. This is a short
lifecycle measurement, NOT a 30/120-second optimization-quality benchmark. No optimum is
claimed for cancelled incumbents. The controller independently validates transferred
incumbents. Raw 19-component vectors and run/proof statuses remain in the JSON results.

The experimental switches are explicit benchmark inputs (ordering, early dead ends,
two-phase and clinical bounds); the application/default strategy was not changed.
Measurements are not a dedicated hardware throughput guarantee: ordinary test/build
processes could compete for host resources. Reported values below are medians in ms.

| Platform | Fixture | Mode | Worker ready | First observed valid incumbent | Cancel |
|---|---|---|---:|---:|---:|
| VM isolate | 6-open | unchanged default | 2.67 | none within window | 4.82 |
| VM isolate | 6-open | explicit experimental | 1.89 | 2.28 | 2.17 |
| VM isolate | 15-open | unchanged default | 2.98 | none within window | 2.36 |
| VM isolate | 15-open | explicit experimental | 1.52 | 3.20 | 1.99 |
| Chromium Worker | 6-open | unchanged default | 35.90 | none within window | 1.40 |
| Chromium Worker | 6-open | explicit experimental | 31.30 | 43.90 | 4.40 |
| Chromium Worker | 15-open | unchanged default | 29.40 | none within window | 1.70 |
| Chromium Worker | 15-open | explicit experimental | 27.80 | 43.20 | 1.30 |

The unchanged default found no incumbent within these ~1.1-second windows. This is neither
infeasibility nor a claim that a longer run cannot solve the month. Explicit experimental
strategy results must not be presented as default UI performance.

The isolated Worker heartbeat maximum gaps across the measured rows were <= 21 ms in
Chromium. Actual Flutter page/navigation measurement is different: two runs measured
~155/158 ms user-click-to-cancel feedback and 544/145 ms maximum heartbeat gaps while
switching rendered tabs. UI remained interactive; smooth 60 fps is NOT established.
The second run scrolled the 30-day table down/up in 741 ms including two deliberate
250 ms waits. This is a functional scroll turnaround, not a frame-time benchmark.
Future UI profiling/virtualization should investigate the transient layout/semantics gaps.
No clinical quality criterion was relaxed for performance.

## Firestore cost scope

Head list page: <=21 header documents, no version payload N+1 downloads. Selecting one
row fetches one immutable version. History page: <=21 version documents (payload bytes
still included by Firestore; no projection is claimed). One save: event/head reads plus
optional source-version read, three atomic writes, and one acknowledgement read. Retries
can add reads. These are source/query operation counts verified in emulator/fake fixtures,
NOT measured production billing. No production read/write traffic was generated.

## Remaining limits

Permanent A/B approval is CLOSED pending a trusted server service; see MIGRATION_1_9D.md.
The runtime can be hosted in Dart, but no verified server identity/approval/IAM boundary
was provisioned or deployed here. Production must deploy matching V2 Rules first. The
Hosting workflow now runs the existing read-only active-rules verifier before publication;
that verifier was not executed against production in this task.

History pagination bounds document count but still transfers payload bytes. Browse cursors
are live under concurrent edits, not collection snapshots. Browser tab-close unsaved recovery
is not guaranteed. The emulator bootstrap pins the Firebase JS version and must be kept in
sync with FlutterFire on dependency upgrades; it is not packaged in the production build.
Physical Android interaction and production Auth/persistence are unverified.
