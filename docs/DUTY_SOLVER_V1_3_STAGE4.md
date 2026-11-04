# V1.3 Stage 4 acceptance measurements

Development-only feature: `--dart-define=AKYS_V13_SOLVER=true`. Default is false. No production data or deployment was used. Timings are single test runs, not latency guarantees.

## Scenario results

| Platform | Scenario | States | ms | First valid ms | Max timer gap ms | Valid | Status | Hierarchy inversions | Vacancies | Substitutions | Optimal |
|---|---|---:|---:|---:|---:|---|---|---:|---:|---:|---|
| vm | 7-28 | 500 | 440 | 91 | 41 | true | SEARCH_LIMIT_REACHED | 36 | 4 | 0 | false |
| vm | 7-30 | 500 | 197 | 20 | 17 | true | SEARCH_LIMIT_REACHED | 66 | 6 | 0 | false |
| vm | 7-31 | 500 | 127 | 12 | 8 | true | SEARCH_LIMIT_REACHED | 72 | 7 | 0 | false |
| vm | 11-30 | 500 | 289 | 24 | 64 | true | SEARCH_LIMIT_REACHED | 0 | 0 | 0 | false |
| vm | five-cannot | 500 | 117 | 8 | 6 | true | SEARCH_LIMIT_REACHED | 66 | 6 | 0 | false |
| vm | overlap | 500 | 114 | 7 | 4 | true | SEARCH_LIMIT_REACHED | 44 | 6 | 0 | false |
| vm | boundary | 500 | 139 | 16 | 10 | true | SEARCH_LIMIT_REACHED | 66 | 6 | 0 | false |
| vm | holiday | 500 | 110 | 8 | 6 | true | SEARCH_LIMIT_REACHED | 72 | 7 | 0 | false |
| vm | must-conflict | 0 | 1 | null | 0 | false | INFEASIBLE | null | null | null | false |
| vm | senior-shortage | 500 | 146 | 15 | 7 | true | SEARCH_LIMIT_REACHED | 17 | 10 | 4 | false |
| vm | junior-shortage | 500 | 108 | 6 | 4 | true | SEARCH_LIMIT_REACHED | 92 | 14 | 0 | false |
| vm | promotion | 500 | 116 | 11 | 8 | true | SEARCH_LIMIT_REACHED | 50 | 7 | 1 | false |
| vm | hard-month | 500 | 149 | 7 | 6 | true | SEARCH_LIMIT_REACHED | 44 | 6 | 0 | false |
| web | 7-28 | 500 | 693 | 93 | 61 | true | SEARCH_LIMIT_REACHED | 36 | 4 | 0 | false |
| web | 7-30 | 500 | 490 | 46 | 33 | true | SEARCH_LIMIT_REACHED | 66 | 6 | 0 | false |
| web | 7-31 | 500 | 436 | 24 | 18 | true | SEARCH_LIMIT_REACHED | 72 | 7 | 0 | false |
| web | 11-30 | 500 | 848 | 83 | 189 | true | SEARCH_LIMIT_REACHED | 0 | 0 | 0 | false |
| web | five-cannot | 500 | 464 | 27 | 26 | true | SEARCH_LIMIT_REACHED | 66 | 6 | 0 | false |
| web | overlap | 500 | 410 | 20 | 16 | true | SEARCH_LIMIT_REACHED | 44 | 6 | 0 | false |
| web | boundary | 500 | 444 | 29 | 28 | true | SEARCH_LIMIT_REACHED | 66 | 6 | 0 | false |
| web | holiday | 500 | 403 | 24 | 21 | true | SEARCH_LIMIT_REACHED | 72 | 7 | 0 | false |
| web | must-conflict | 0 | 0 | null | 0 | false | INFEASIBLE | null | null | null | false |
| web | senior-shortage | 500 | 492 | 30 | 20 | true | SEARCH_LIMIT_REACHED | 17 | 10 | 4 | false |
| web | junior-shortage | 500 | 443 | 22 | 16 | true | SEARCH_LIMIT_REACHED | 92 | 14 | 0 | false |
| web | promotion | 500 | 545 | 40 | 34 | true | SEARCH_LIMIT_REACHED | 50 | 7 | 1 | false |
| web | hard-month | 500 | 470 | 26 | 20 | true | SEARCH_LIMIT_REACHED | 44 | 6 | 0 | false |

All valid scenarios passed the independent hard validator. None of these bounded general-month runs proved the full hierarchy/optimization optimum; proof time is therefore unavailable, not zero. Must/Cannot contradiction was proven before search. A zero observed hierarchy inversion count is not a full lexicographic optimum proof.

## Larger budget cancellation profiles

- `BUDGET vm budget=2000 nodes=1000 ms=550 first=24 cancelLatency=2`
- `BUDGET vm budget=10000 nodes=5000 ms=1810 first=23 cancelLatency=1`
- `BUDGET web budget=2000 nodes=1000 ms=1556 first=82 cancelLatency=9`
- `BUDGET web budget=10000 nodes=5000 ms=5432 first=60 cancelLatency=5`

Profiles request cancellation at half the configured 2,000/10,000 node budget. They measure 1,000/5,000 processed nodes, not full-budget completion. UI default is 2,000; choices are 500/2,000/10,000.

## Architecture and bottlenecks

Candidate domains are recomputed per remaining day at every CSP node; optional triples increase branching, and full candidate reports/validation cost work at leaves. The measured improvement defers optional triples during the first-feasible search (required triples remain), preserving all combinations during exhaustive optimization. Fairness reporting now reuses one difficulty snapshot per report. No constraint or objective was relaxed.

Cooperative yielding remains every eight nodes in the UI. Chromium showed timer gaps up to 189 ms in the 11-person scenario. This avoids a single uninterrupted full search but is not a 60-fps responsiveness guarantee. Before production rollout for larger cases, use a dedicated Web Worker compiled from a pure solver entry point; send only serialized monthly snapshots, progress and cancellation messages, never Firebase credentials. Cancellation must remain cooperative inside the worker or terminate it after retaining the last validated incumbent. On Android an isolate with progress/control ports is suitable. A remote service is unnecessary and would introduce data-access/security/cost obligations. Worker bundle/CSP hosting and isolate lifecycle integration remain future work; not falsely claimed implemented.

## Persistence and UI safeguards

Optional dutyPositions/v13Diagnostics fields round-trip through ScheduleMonth and the repository; absent fields stay absent. Legacy roles are never guessed. Compatibility duties are explicitly derived from preview positions and checked on save. Snapshot/personnel identity guards remain. Save is draft-only, validates hard constraints, checks revision and confirmed month boundary, blocks role deletion, and invalidates proof on role/constraint/boundary edits. Public sharing/finalization of V1.3 is intentionally blocked in this stage. Rules and production workflows are unchanged.

Flag panel provides budgets, progress, cancellation, separate hard/hierarchy/optimization status, named daily role preview, substitutions/vacancies, fairness report, role editing and confirmed draft save. Invalid manual previews cannot be saved. Reopening recomputes fairness; saved proof metadata is displayed only for the corresponding unedited preview. Role/constraint edits invalidate certificates and vacancy labels. The legacy move operation is not used to infer V1.3 positions; use the dedicated editor. Constraints which would invalidate a saved V1.3 draft are rejected until a consistent whole update is prepared.

## Validation

Full native suite: 184 passed. Chromium scenario/UI suite: 26 passed. Additional final display-name UI checks and both feature-off/feature-on Web builds are reported at completion. Android debug build is compile validation, not physical-device performance testing. Firestore emulator tests target demo-akys only. No main merge, push or deploy.

Final validation: analyze clean; full native suite 184/184; final display-name UI
checks 11/11 native and 11/11 Chromium; combined Chromium acceptance 26/26;
Web release PASS with feature flag off, separate Web release PASS with flag on;
Android debug build PASS; Firestore emulator/security suite PASS. The optional
feature-on bundle was built under /tmp and was not served against production.
