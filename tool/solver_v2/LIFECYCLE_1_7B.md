# Stage 1.7B — optimization lifecycle

Base: `88d58615089dde22391497b8f0d56d188c924e00`, branch
`feature/akys-v2-solver-core`. Measured 2026-11-14. No existing solver,
V1, Flutter production entrypoint, Firebase configuration or defaults changed.

## Architecture and supported behavior

`OptimizationController` is a pure Dart host API. `value` is the latest immutable
observation; `events` is a broadcast stream. Subscribe before `start`, or read
`value` after subscribing. Each start owns a fresh generation and private worker
channel. Generation IDs and increasing worker sequence numbers reject delayed
events from previous runs. Starting a new problem deliberately starts a new run;
it is not time extension. Retain an earlier snapshot separately if needed.

The IO backend creates a real Dart isolate containing the unchanged
`TransitionSession`. It advances that same session one node per call within
5 ms scheduling slices, yielding to its command port between slices. This is
not execution of DFS on the Flutter UI isolate. Each new incumbent is checked
with `SolutionValidator` and the actual worker's session evidence before sending.
The host uses the exact clinical comparison, retains equal incumbents, and treats
a worse incoming incumbent as a protocol failure while preserving the old best.
All 19 exact quality components travel through the existing message format.

Regular progress defaults to 100 ms; incumbent, phase and terminal events are
sent immediately. No per-node progress messages. Metrics include total A+B
nodes, pruning counters, worker elapsed time, phase, restricted verdict, first
validated incumbent observation time, best solution and proof level. First time
includes validation; it is not instrumented inside the DFS leaf evaluator.

All strategy switches remain false by default, including forward checking.
No DFS or mathematical search change was required.

## States, time extension and cleanup

| State | Meaning / next steps |
|---|---|
| idle | No run; `start` enters preparing. |
| preparing | Snapshot copy, options and isolate startup; running, failed or cancelled follows. |
| running | Search active without incumbent; progress may repeat this state. |
| feasible | Valid incumbent, no optimality proof; search continues. |
| optimal | Core reports complete optimality proof and an incumbent. Terminal. |
| infeasible | Core reports proven infeasibility, no incumbent. Terminal. |
| timedOut | Budget exhausted; may have a valid incumbent. Resumable. |
| cancelled | Cancel acknowledged or forced; delivered incumbent retained. Terminal. |
| failed | Input/startup/worker/protocol/host failure; delivered incumbent retained. Terminal. |

`extend(extra)` adds positive duration to the active run's cumulative budget,
including after timeout. It resumes the **same** session, DFS frontier, A/B
phase and incumbent. Waiting between timeout and extension is excluded from
worker elapsed search time. It does not recreate a search or reuse serialized
proof. A timeout deliberately retains the isolate; callers must cancel/dispose
if they will not extend it. There is no public manual pause API in this stage.

`cancel()` requests cooperative cancellation at the next scheduling checkpoint.
The default 500 ms host fallback kills the isolate if it has not acknowledged.
`grace: Duration.zero` explicitly forces termination. `forcedTermination` marks
that path; only the last already delivered validated solution is guaranteed.
One solver/validator call can exceed a nominal slice: this is not a hard realtime
latency guarantee. Normal terminal states, abort, cancel and dispose close ports,
subscriptions and timers. Pending and overlapping isolate startups are also
tracked and terminated. `abort(reason)` records a host-detected failure without
discarding the best solution. OS-level fatal crashes were not deliberately injected.

## A/B trust boundary

Only the unchanged `TransitionSession` opens B after A's proven infeasibility.
The worker retains the actual in-process evidence and independently validates
each candidate with that evidence. No public proof bypass or event injection API
is provided. The host receives an observation from its privately spawned worker;
it does **not** gain a transferable mathematical certificate from the serialized
`restrictedVerdict` field. Arbitrarily constructed `OptimizationSnapshot` objects
are not accepted back into the controller as evidence.

`permanentApprovalAllowed` is always false. In particular, transferring a B
solution does not grant persistent approval, server verification or Firestore
authorization. Restarting the process starts a new search/proof context. Timeout,
cancellation and failure with an incumbent report feasible-unproven, never proof.

## Platform evidence

* Dart VM: real-isolate lifecycle tests and short sequential benchmark executed.
* Android: standalone Flutter debug APK built with the IO backend. `adb devices`
  reported no device/emulator, so Android execution, physical UI responsiveness,
  memory pressure and lifecycle suspension are **not verified**.
* Web: standalone release build and Chromium test executed. There is **no Web
  Worker backend**. Conditional import returns an explicit unsupported failure;
  it never runs synchronous DFS on the browser UI thread. Chromium verifies zero
  searched nodes and a live browser event loop on this refusal path, not successful
  browser optimization. Flutter `compute` is not used as a parallelism substitute.

Next Web work requires a separately compiled worker entrypoint, message transport,
worker disposal, exact-number serialization checks and real Chromium optimization,
heartbeat, cancellation and extension tests. The existing transport interface is
only a starting point; it is not evidence of Web support.

`tool/solver_v2/lifecycle_smoke.dart` is an isolated build target with synthetic
data and no Firebase initialization. Production `main.dart` is unchanged.

## Verification

Commands (after sourcing `/workspace/akys-toolchain/activate.sh`):

```sh
dart analyze lib/solver_v2 test/solver_v2 tool/solver_v2
flutter analyze --no-pub
flutter test --no-pub test/solver_v2 --reporter expanded
flutter test --no-pub --platform chrome test/solver_v2/lifecycle_web_test.dart --reporter expanded
flutter build web --release --no-pub -t tool/solver_v2/lifecycle_smoke.dart
flutter build apk --debug --no-pub -t tool/solver_v2/lifecycle_smoke.dart
dart run tool/solver_v2/lifecycle_benchmark.dart
```

Both analyses are clean. VM suite: **169 PASS** (152 existing + 17 lifecycle).
The existing oracle, independent quality, proof and pause/resume regressions are
included. New tests cover states, A/B, timeout with/without solution, extension
while running and after timeout, cancellation before/after first solution,
forced termination, cleanup, stale/overlapping runs, host failure, progress order
and throttling, and main-isolate responsiveness. Chromium: **1 PASS**.

Web release and Android debug builds use the standalone target above. Existing
Cupertino font/Android toolchain-plugin warnings are outside this change. No
device installation, production build publication or deployment was performed.

## Short overhead experiment (not a clinical benchmark)

Raw rows and runtime source fingerprints:
`results/stage_1_7b_lifecycle.json`. Linux x86_64, kernel 6.18.57, hosted AMD EPYC
9V74 / 5 visible CPUs, Dart 3.13.7 JIT. One process, sequential runs, no concurrent
benchmark/build/test job; 3 repeats of `6-open`, seed 160600, 300 ms each. Explicit
two-phase + bounds options were identical across direct and isolate cases;
these are benchmark selections, not new defaults. No warm-up exclusion; JIT and
shared-host variability are visible, particularly in the first repeat.

| Mode | Median nodes / 300 ms | Median wall time | Progress events |
|---|---:|---:|---:|
| Direct bulk session | 211,795 | 300.051 ms | none |
| Isolate, 100 ms progress | 161,048 | 302.645 ms | 10 per run, including state/best/cancel |
| Isolate, 10,000 ms progress | 164,222 | 302.139 ms | 8 per run, including state/best/cancel |

At 100 ms progress, median node throughput was about **24% lower** than bulk.
This combines per-node session calls, validation, scheduling, serialization and
isolate effects; it does not isolate their individual costs. Lower progress rate
did not remove that overhead. First validated solution observations were
0.289–8.976 ms, excluding startup. Main-isolate 5 ms timer kept ticking (60–62
ticks); largest observed gap was 6.779 ms. Cancellation acknowledgement measured
**after timeout** was 0.288–2.026 ms; this is not a loaded-device guarantee.

Every isolate run timed out with a retained valid solution and no optimality
claim. Direct runs also ended feasible-not-proven. Timed searches can process
different node counts and end at different incumbents across machines; this API
does not claim time-budget determinism. No long-run or Android performance,
frame-rendering or memory guarantee follows from these short VM measurements.

## Changed scope and remaining work

New runtime files: `lifecycle.dart`, `transport.dart`, `worker_io.dart`,
`worker_stub.dart`. New tests: `lifecycle_vm_test.dart`, `lifecycle_web_test.dart`.
New tools: standalone smoke entrypoint, benchmark, raw JSON and this report.

Before product integration: implement/verify the Web worker; run Android device
tests (including app suspension); measure sustained CPU/memory and UI frames;
design explicit UI disposal/timeout handling. No production UI integration,
persistence, checkpoint serialization or server proof validation was added.
