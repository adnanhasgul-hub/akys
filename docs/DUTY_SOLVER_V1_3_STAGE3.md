# V1.3 Stage 3: lexicographic fairness

Independent API: FairnessOptimizer.optimize(month, cancellation: token).
Production/V1.2, Firestore, repository and UI are unchanged.

## Review of Stage 2

A global junior capacity shortage is not a proof that a particular day must be
vacant. Existing Stage 2 forced-day probes exhaust the applicable senior phase
before marking PROVEN_UNAVOIDABLE. Existing regression checks both a date blocked
for every junior and the 30-day/24-capacity case where dates remain NOT_PROVEN.
Stage 3 does not reuse stale vacancy certificates: generated vacancies retain
NOT_PROVEN. Real-senior infeasibility must still be proven before substitutions.

## Objective and proof

The existing MRV CSP now optionally accepts a full lexicographic objective. The
legacy Stage 2 coverage-only path remains the default. Stage 3 enumerates optional
third juniors too: excluding them could invalidate a fairness optimality claim.
Every complete candidate passes the independent validator.

Priority: substitutions; vacancies; hierarchy vector by descending seniority;
real-senior solo vector; separate group count spread and ordered counts; separate
Saturday, Friday, Sunday spreads and ordered counts; easy-Thursday spread and
reverse ordered counts; group average difficulty spread; group total difficulty
spread; Mon/Tue/Wed spread; holiday spread. No weighted aggregate is used.

Candidate comparison stops at the first unequal component. Thus a lower priority
improvement can never worsen any higher component. This is a single exact
lexicographic enumeration, mathematically equivalent to fixing each proven
prefix before optimizing the next stage; it is not a series of separate solver
runs. During incomplete enumeration ALL lower-stage improvements are provisional.
Proof flags are conservative: all components are proven after exhaustive search;
zero substitutions can independently be proven by its nonnegative lower bound.
There are no unsupported per-stage optimality claims from local search.

Monthly hierarchy counts ordered solo-day/paired-day inversions. All real seniors
precede substituted juniors in role order; original group membership is retained.
An exception is accepted only when exhaustive search proves the hierarchy vector
optimal. A budget-limited incumbent with violations is not an accepted exception.

Report includes role counts, solos/pairs, five weekday categories, additional
holiday counts, total and mean points, per-stage values/proofs. Points come only
from current-month dates. Easy Thursday is conservatively defined as an ordinary
nonholiday, non-preholiday Thursday. All holiday Thursdays still count in the
actual Thursday category and holiday totals.

## Limits

This is an exact, bounded exhaustive reference optimizer, not a scalable claim of
global optimality for unconstrained 7/11-person months. Such cases commonly return
SEARCH_LIMIT_REACHED with a valid provisional incumbent. Full prefix-aware lower
bounds and incremental scoring remain performance work for later stages. The
initial feasible incumbent is preserved, cancellation and shared node budgets
remain active, and event-loop yields remain in the CSP. There is no external
service, worker dependency or production persistence. Average comparisons use
Dart double arithmetic (counts at most eight), not symbolic rational arithmetic.

Tests include independent enumeration of all feasible assignments in a strongly
constrained 28-day fixture, zero/inevitable hierarchy violations, ordered count
advantages, separate hard-day categories, Thursday/holiday distinction, total vs
average points, boundaries, budget/cancellation, and deterministic 7/11-person
incumbents. Stage 2 vacancy-proof tests remain unchanged and pass in Chromium.

## Measured validation

Analyze: clean. Native suite: 158 passed. Chromium combined Stage 2/3: 31
passed; final Stage 3 timing run: 14 passed. For a 150-state budget, 7/11-person
native runs took 138/315 ms; Chromium took 194/755 ms. These are single-run
measurements and both sizes returned SEARCH_LIMIT_REACHED with validated
incumbents, not optimal schedules. Physical Android was not measured.
