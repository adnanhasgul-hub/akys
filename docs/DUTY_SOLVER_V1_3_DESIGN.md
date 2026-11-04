# V1.3 implementation assessment (not implemented)

Baseline: 82ffb131edb3a0c0948abd6b92e0c1ca8d456d58.
Development branch: feat/v1.3-duty-solver.

## Confirmed gaps

- Current daily assignment is a list of person IDs, without explicit senior/junior positions. Temporary promotion cannot be represented unambiguously.
- validateDuties validates rest, maximum eight, personal constraints, boundaries and total demand, but does not require exactly one senior position.
- Composition is a soft objective. It cannot satisfy V1.3's hard daily composition requirement.
- Initial CSP explores deterministic staffing templates and person quotas, rather than freely optimizing monthly junior coverage.
- Current objective aggregates fairness across groups. It does not implement per-group ordered fairness or the monthly solo/pair hierarchy proof requirement.
- Current GenerationResult has a searchLimited boolean, not a proof-aware stage result.
- Flutter compute does not provide a separate worker on Web. Synchronous CSP and local optimization can therefore block the browser event loop. Five cannot dates must be benchmarked before claiming the reported freeze is resolved.

## Required implementation boundaries

1. Versioned position snapshot, preserving legacy month serialization and legacy interpretation. Position assignments must identify temporary promotions explicitly.
2. Independent input and final constraint validator; manual edits and finalization must use the matching schema version.
3. Deterministic bounded whole-month solver with incremental state, propagation and cooperative scheduling or an actual Web Worker; node budget rather than wall clock determines result.
4. Stage results record incumbent, lower bound, exhaustive proof and budget exhaustion separately. A lower-priority stage must not change a proven higher-priority optimum.
5. Hierarchy exception search is permitted only after exhaustive no-exception infeasibility proof under the fixed preceding stages. Search exhaustion is not that proof.
6. Preserve a feasible incumbent as provisional when earlier objective bounds remain open; do not silently finalize or present it as optimal.
7. Independent fairness reporting and explicit coverage/promotion/hierarchy diagnostics, recalculated after manual edits.
8. Preserve V1.2 difficulty and task-calendar snapshots and existing public privacy boundaries.

No production deployment is authorized by this task. Completion requires the requested scenario suite, analyze, Web and Android builds and emulator tests before committing the implementation for review.
