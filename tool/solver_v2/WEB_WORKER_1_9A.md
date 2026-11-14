# AKYS V2 Stage 1.9A — real Web Worker execution

Base: `c77ea8dc0d3b05adcfbaf33fa7d2226d2dd02ea2`, branch
`feature/akys-v2-solver-core`. Verified clean at start. Baseline 214 V2 tests passed.
Flutter 3.47.9 / Dart 3.13.7; Chromium 154.0.8037.57; Linux x86_64 hosted AMD EPYC
9V74, five visible CPUs. No V1, solver DFS, clinical objectives, strategy defaults,
forward-checking defaults, production, Firebase or deployment configuration changed.

## Feasibility experiment first

`web/feasibility_probe.dart` compiled with `dart compile js -O2` and ran in a real
DedicatedWorker before the full adapter was implemented. It used the existing
6-open synthetic fixture and actual TransitionSession. Chromium observed:

* start at 3 visited nodes;
* extend acknowledged at 151 ms / 1,794 nodes;
* cancellation acknowledged at 702 ms / 21,375 nodes, beyond the original 500 ms
  deadline but within the extended deadline;
* the main page's 5 ms timer ticked 150 times.

Result: `results/stage_1_9a_probe.json`. A separate compiled Dart worker can retain
this pure Dart solver, and finite stepping allows commands to be serviced during
search. A single long synchronous run inside a worker would not provide that
command responsiveness. We did not substitute Flutter `compute` for a worker.

## Architecture and API

```dart
final controller = OptimizationController.web(
  // Trusted application asset, not user-controlled input; same origin required.
  workerUri: Uri.parse('/akys_v2_worker.js'),
);
await controller.start(problem, options: const OptimizationOptions());
controller.extend(const Duration(seconds: 30));
await controller.cancel();
await controller.dispose();
```

The existing VM `OptimizationController()` remains an isolate backend. The legacy
no-argument Web path remains disabled, preserving the old explicit refusal test
and avoiding a silent production behavior change. `webSupported` reports browser
adapter capability; it does not guarantee that the asset is packaged or CSP allows
it. A missing asset yields `failed`, never synchronous UI-thread DFS.

`WorkerEngine` extracts the previous VM engine's scheduling logic into shared pure
Dart code. Both transports use the unchanged TransitionSession. It performs
one-node calls within 5 ms slices and yields to its event queue between slices.
The Web backend uses `package:web`/`dart:js_interop`, isolated by conditional imports
so native Android compilation does not pull in Web libraries. There is one worker
per controller run. Worker state (frontier, phase, incumbent, budget) remains in
that worker, not in serialized result messages.

## Compilation / packaging

Run at repo root, with Flutter/Dart on PATH:

```sh
flutter build web --release --no-pub --no-web-resources-cdn -t tool/solver_v2/lifecycle_smoke.dart
bash tool/solver_v2/web/build_worker.sh build/web
flutter build apk --debug --no-pub -t tool/solver_v2/lifecycle_smoke.dart
```

The shell script compiles `web/worker_entry.dart` to a self-contained classic-worker
JS file beside the Flutter build. It must run AFTER Flutter's build, which can
replace the output directory. The worker has no Flutter/DOM/Firebase dependency.
Compiled output is ignored under `build/`; only sources and measured reports are
committed. No production workflow was changed. A future product build must package
matching app/worker versions, choose a stable asset URL for deep routes, allow
`worker-src 'self'` (and appropriate script policy), and handle worker asset caching.
Use content-versioned deployment URLs when integrating; this stage does not change
Hosting headers or CSP. Only JS release execution was tested, not Flutter Wasm,
Firefox, Safari or physical mobile browsers.

## Protocol, scheduling and cleanup

Version 1 JSON-string envelopes avoid cross-context Dart object transport and
preserve exact rational numerator/denominator strings without floating-point
conversion. Each command/event has a run ID; startup uses run 0. Commands:
`start`, `cancel`, `extendDeadline`, `dispose`; transport control uses `ping`/`pong`.
Events include `ready`, `started`, `progress`, `incumbentUpdated`, `completed`,
`cancelled`, `failed`, plus lifecycle state, increasing sequence, elapsed time,
nodes, pruning, A/B phase/verdict, first-solution time and best assignment/quality.
A `completed` notification can end the current budget: its explicit `timedOut`
state is resumable and is NOT an optimality claim. Controller proof level is
computed from state and incumbent. Generation and sequence checks reject stale
and duplicate events. Input snapshots are copied before posting.

Progress defaults to 100 ms; phase, incumbent and terminal events are immediate.
New `transportDelay` measures wall-clock send-to-main-receive time, excluding host
validation. Browser clocks have coarse resolution; measured zero does not imply
zero physical latency.

Cooperative cancellation is processed between slices. If it does not acknowledge
within the host grace period (default 500 ms), the browser worker is terminated;
only the last delivered validated incumbent is guaranteed. `grace: Duration.zero`
explicitly forces that path. Disposal sends a dispose command and terminates the
worker without relying on an acknowledgement, closes streams and cancels timers.

The browser has no reliable worker `onExit`. Script errors and message errors are
handled directly; silent `self.close()`/unresponsive workers are detected by a
heartbeat watchdog (default 1 s interval, 5 s silence). A plain `Event` rather
than `ErrorEvent` can occur for a missing script; the real test exposed this and
the handler now distinguishes them without an uncaught main-page exception.

Timeout retains the worker/frontier for extension. `extend` adds to the same
cumulative budget, including after timeout, preserving first-solution timestamp,
incumbent and increasing node count. No session restart is disguised as extension.
Waiting while timed out does not consume search budget. Call cancel/dispose when
not extending. Startup waits are bounded by the handshake timeout (default 10 s);
cancelling a pending launch can wait for that startup attempt to settle. A single
solver/validator call can exceed a nominal slice; latency is not a realtime
platform guarantee. Background-tab throttling/suspension may trigger conservative
watchdog failure and was not validated as a supported continuation scenario.

## Main-layer independent validation and A/B trust boundary

The worker still validates every incumbent with SolutionValidator and its genuine
in-process TransitionSession. The main controller now also checks transferred
assignments with the independent validator and recomputes the exact 19-component
quality before storing them. Wrong required slots, locks, rest/capacity/role rules
or quality are rejected, retaining the last good preview. A worse clinical or
reference-tie objective cannot overwrite the incumbent.

A/B evidence cannot be serialized into authority. To avoid conflating arithmetic
with authorization, a distinct `CandidateInspection` reports assignment-constraint
checks AND an explicit `requiresTransitionProof` obligation. It is not a
ValidationResult approval, has no evidence capability, and always forbids durable
approval. `inspectTransferredPreview` computes arithmetic only. Existing
`validate` and `evaluate` still reject B solutions without genuine local session
evidence; no `skipProof` or forged `proved=true` parameter was introduced. Existing
A/B search and role admission were not changed.

For B, the main thread verifies structure and quality but does NOT independently
re-run A's exhaustive proof. It observes A's result from its trusted application
worker, requires the B phase/proven-infeasible verdict, and keeps the result
preview-only. The mathematical proof remains inside the actual worker session.
Reported optimality is the worker execution's outcome, not a portable certificate
or independently verified server proof. Permanent approval remains false.

The worker URL is executable trusted application code, not a security sandbox for
arbitrary user-selected scripts. Same-origin enforcement alone does not make
hostile same-origin code trustworthy. Compromised app/worker code, server-signed
certificates and durable proof validation are outside this stage. Tests use
explicit same-origin fault-injection scripts to exercise rejection and cleanup;
those fixtures must never be packaged as production entrypoints.

## Real execution evidence

* VM suite: **218 PASS** = previous 214 + 4 structural-inspection/authority tests.
* Flutter Chromium suite: **24 PASS** = previous 20 + the same 4 inspection tests.
* Separate actual DedicatedWorker harness: **18/18 PASS**, 18 worker instances,
  no uncaught page errors. Covers startup, main-loop response, throttled progress,
  active extension, zero/nonempty-frontier timeout continuation, cooperative
  cancellation before/after solution, forced termination, blocked command queue,
  actual thrown worker error, silent close/watchdog, corrupt assignments/quality,
  stale/duplicate messages, fresh A/B proof, true infeasibility, exact 1/7 quality
  and missing script. The normal solver tests run compiled Dart worker code;
  they are not mock-worker tests.
* Real Flutter Web JS release: **PASS**, locally served CanvasKit/resources and
  separately compiled worker. Tiny fixture reaches validated optimal. A subsequent
  1.5 s 6-open search produced **77 rendered frames, 80 timer ticks, 136,492 nodes**.
  Playwright clicked the semantic button while search was active (at 5,481 nodes);
  the click was processed. It ended timedOut/feasibleUnproven then cancelled.
* Android debug smoke APK: **PASS**, 23.7 s final build. No device/emulator run;
  earlier toolchain XML/plugin and Web Cupertino-font warnings remain unrelated.
* Dart targeted analysis and full Flutter analysis: clean.

Evidence JSONs: `stage_1_9a_browser.json`, `stage_1_9a_flutter_web.json`,
`stage_1_9a_probe.json`. Artifact hashes are retained. Test-only smoke target does
not initialize Firebase or change production `main.dart`.

Reproduce after building the standalone harness:

```sh
bash tool/solver_v2/web/build_worker.sh build/v2-worker-test
dart compile js -O2 --no-source-maps -o build/v2-worker-test/acceptance.js tool/solver_v2/web/acceptance.dart
cp -r tool/solver_v2/web/fixtures build/v2-worker-test/
# index.html must load acceptance.js (the local harness setup used this one line)
printf '<html><body><script src="acceptance.js"></script></body></html>' > build/v2-worker-test/index.html
python3 tool/solver_v2/web/run_browser.py
python3 tool/solver_v2/web/run_flutter_smoke.py
flutter test --no-pub test/solver_v2 --reporter expanded
flutter test --no-pub --platform chrome test/solver_v2/reoptimization_test.dart test/solver_v2/lifecycle_web_test.dart test/solver_v2/transferred_candidate_test.dart --reporter expanded
```

## Performance (measured, short experiment)

Fixture `6-open`, seed 160600, 6 doctors/30 days; identical explicit combined,
two-phase and bounds settings, no change to defaults. Three sequential repeats per
platform, approximately one-second search windows, no concurrent benchmark/build.
VM direct stops on its 1 s budget. Isolate/Worker run with a 3 s safety budget and
receive cooperative cancel after a 1 s observation window. End status therefore
differs by stopping mechanism; all are valid/unproven, not clinical optima.

| Mode | Median first solution | Median nodes/s | Median delivery delay | Median active cancel | Main 5 ms timer |
|---|---:|---:|---:|---:|---|
| Dart VM direct | 0.766 ms | 667,368 | N/A | N/A (synchronous call) | 0 ticks during call |
| Dart VM isolate | 2.802 ms observed / 0.368 ms worker | 553,227 | 0.191 ms | 2.527 ms | 200–203 ticks |
| Chromium Worker | 44.500 ms observed / 12 ms worker | 116,627 | 0 ms at clock resolution | 2.900 ms | 205–207 ticks |

Observed time includes worker startup, serialization and host validation; worker
first time excludes startup. Direct first time uses its first-incumbent callback.
Cold JIT repeat is included (VM direct 37.484 ms; Worker observed 114.901 ms); there
was no warm-up exclusion. Largest main timer gaps: VM isolate 14.995 ms, Web Worker
46.600 ms (cold startup); warm Web repeats 8.299/7.100 ms. Web delivery delay rounded
to zero in these samples; do not treat it as exact zero latency. Browser timer
clamping and 5 ms slices reduce throughput; these runtimes are not hardware- or
compiler-equivalent. Three short runs do not establish clinical-scale guarantees.

Memory: VM RSS includes the entire Dart process/JIT/GC, with after-run values about
184–185 MB, not isolate-only allocations. Chromium's sampled sum of reported process
RSS peaks was **487,620,608 / 488,022,016 / 488,894,464 bytes**. This includes browser,
UI renderer, worker and GPU, can count shared pages more than once, and is NOT the
worker heap. Sampling CDP/process RSS every ~100 ms adds measurement overhead.
No reliable per-worker heap isolation claim is made. Raw vectors and metrics are
in `stage_1_9a_vm_benchmark.json` and `stage_1_9a_web_benchmark.json`.

Benchmark commands (sequential):

```sh
dart run tool/solver_v2/web/benchmark_vm.dart
mkdir -p build/v2-worker-benchmark
bash tool/solver_v2/web/build_worker.sh build/v2-worker-benchmark
dart compile js -O2 --no-source-maps -o build/v2-worker-benchmark/benchmark.js tool/solver_v2/web/benchmark_browser.dart
printf '<html><body><script src="benchmark.js"></script></body></html>' > build/v2-worker-benchmark/index.html
python3 tool/solver_v2/web/run_browser.py --directory build/v2-worker-benchmark --result tool/solver_v2/results/stage_1_9a_web_benchmark.json --measure-memory
```

## Changed files / remaining integration work

* Runtime: `worker_engine.dart` (shared slices), `worker_web.dart`, `web_stub.dart`,
  `worker_stub.dart` (explicit default refusal text), `worker_io.dart`, `lifecycle.dart`.
* Validation: `solution_validator.dart`, `clinical_quality.dart`; structural preview
  type/entrypoint only, no change to the 19 arithmetic definitions or search.
* Test: `transferred_candidate_test.dart`.
* Tools: `lifecycle_smoke.dart`; `web/feasibility_probe.dart`, `worker_entry.dart`,
  `acceptance.dart`, `benchmark_shared.dart`, `benchmark_vm.dart`,
  `benchmark_browser.dart`, `build_worker.sh`, `run_probe.py`, `run_browser.py`,
  `run_flutter_smoke.py`; six deliberate fault JS fixtures.
* This report and six result/source-manifest JSON files in `results/`.

Before product rollout: integrate trusted/versioned worker packaging into an
explicitly authorized build pipeline; define app UI disposal/extension UX; verify
production CSP/caching, hidden-tab behavior, target devices and other browsers.
No new backend, engine, V1 behavior, production feature toggle or Firebase setting
was added. No push/merge/deploy performed.
