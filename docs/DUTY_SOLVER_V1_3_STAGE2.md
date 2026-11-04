# V1.3 Stage 2 — independent feasibility CSP

No repository/UI integration or production migration is performed. V1.2 remains
unchanged. Entry point: `FeasibilitySolver.solve`, with an immutable result and
optional cancellation token. No network service, credentials or external solver.

## Search and proof scope

- Input is cloned. Validator input contradictions are checked before search.
- MRV selects the remaining day with fewest legal combinations. Whole-month
  backtracking enumerates legal senior/junior positions, reserving future must
  duties and respecting count, rest, boundary and active-person restrictions.
- Every decision recomputes remaining domains; empty domains prune safely.
  Coverage pruning uses the number of remaining days with nonempty junior options.
- First search forbids substitution. Only exhaustive failure permits the second
  search, with juniors in rank order for the senior role. Budget exhaustion never
  permits that transition. Within the chosen phase, coverage is maximized.
- Third persons are generated only to satisfy two mandatory junior assignments.
  Optional thirds cannot improve feasibility or one-junior-per-day coverage;
  removing one preserves feasibility unless it is mandatory.
- Junior capacity (8 times active junior count, capped by days) is an admissible
  upper bound. Reaching it proves maximum coverage; otherwise exhaustive
  branch-and-bound is needed. This does not prove fairness or minimum promotions.
- Each vacant date gets its own forced-nonempty search over the applicable whole
  month phase. Exhaustive failure gives PROVEN_UNAVOIDABLE; witness or exhausted
  budget gives NOT_PROVEN. Global capacity shortage is not a date-specific proof.
- Complete assignments always pass the independent Stage 1 validator before
  becoming incumbents. Different roles count as one duty on a person's date.
- Deterministic variable ordering avoids assignment-order permutations in a search.
  Previously found filled-date witnesses skip redundant vacancy probes. No
  unbounded transposition cache is retained; separate proof probes may revisit
  states. All probes share the same finite node budget.

## Responsiveness and statuses

The recursive search explicitly yields to the event queue every bounded number of
nodes (`Future.delayed(Duration.zero)`), not merely an async method declaration.
Cancellation is checked before work and after yields. This is cooperative
scheduling on both Web and native, not a dedicated Web Worker. Candidate-domain
construction within one node is synchronous; very large personnel sets can
increase a single slice. Hard real-time frame latency is not guaranteed.

Result codes: FEASIBLE, INFEASIBLE, SEARCH_LIMIT_REACHED, ERROR. A search limit can
carry a valid incumbent. `optimalityProven` refers only to junior coverage within
the established senior phase. It may be true even if later individual vacancy
proofs hit the budget. Unproven incumbents remain data for later draft UI
integration; this module never persists or finalizes a month.

## Validation

18 new tests exercise 30/31-day schedules, five cannot dates, multiple unavailable
seniors, promotion ordering, saturated junior, vacancy proofs, must conflicts,
boundary rest, deterministic output, budget, cancellation, required triples and
cooperative responsiveness. Full native suite: 143 passed; subsequently added provisional-incumbent test: 1 passed. Analyze passes. Chromium: 17 passed, including the heartbeat benchmark.

Five-cannot benchmark (one development run, same input, different solver goals):
Linux Flutter test VM: V1.2 2531 ms; V1.3 136 ms, 241 visited states, coverage proven,
31 heartbeat callbacks, maximum observed callback gap 14 ms. Native VM is not an
Android device measurement. Chromium: V1.2 14017 ms; V1.3 312 ms, 241 states, 50 heartbeat callbacks, maximum callback gap 49 ms. Web release build passed. No physical Android performance claim is made.
