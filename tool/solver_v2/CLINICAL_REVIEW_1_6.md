# AKYS V2 1.6 — clinical quality, risks and next steps

## Measured findings

At 30 seconds the two-phase variants tie for best on 6 doctors; deadends wins
on 10/15; the two-phase variants tie on 20. At 120 seconds deadends joins the
6-doctor tie, remains best on 10/15, and bounded is best on 20. All comparisons
are exact and within the same snapshot. The unmodified combined strategy is
worse than the leaders on coverage in all four open fixtures.

|120s selected result|Junior-covered days|Two-junior days|Filled OPTIONAL|Senior duty counts|Junior duty counts|
|---|---:|---:|---:|---|---|
|6 / bounded (three-way tie)|13|0|13|7,8,7,8|6,7|
|10 / deadends|24|0|24|7,7,7,6,3|7,8,2,3,4|
|15 / deadends|28|17|45|7,7,7,5,3,2|8,2,3,4,5,6,7,8,2|
|20 / bounded|31|0|31|4,4,4,4,4,4,5,2|3,3,2,3,3,3,2,2,2,2,3,3|

In the 6-doctor selected result all seniors have one Saturday, but their Sunday
counts are 1,0,1,3. Their total difficulty is 32,41,33,42; junior totals are 27,34.
In the 10-doctor selected result junior duties exactly reach their unequal caps
7,8,2,3,4: their normalized load is identical (1), while total difficulty is
38,38,9,15,29. These are different notions of fairness, not arithmetic errors.
In the 15-doctor case the three leading strategies all fill 45 OPTIONAL slots,
but deadends covers 28 days versus 27 for the others; Q2 decides before any
improvement in Q3, hierarchy or difficulty. In the 20-doctor case all three
leaders cover all days, and bounded improves Saturday fairness over twophase
at equal higher-priority components. Full per-person weekdays, loads and points
are included in the raw result archive.

The blocked-last-day fixture produced no solution and no solver infeasibility
proof even after 120 seconds. Deadends visited 815,353,380 nodes; the other
strategies visited about 45–48 million. All remained in A with pending verdict.
This is an observed proof-latency failure, not an incorrect proof. The problem
is independently impossible because every doctor is forbidden on its last day.

## Interpretation and clinical questions (not newly implemented rules)

- No single strategy dominates this expanded sample. The 1.5F bounded candidate
  recommendation does not establish a universal default. Keep the default
  unchanged and retain deadends and bounded for further controlled comparison.
- Faster first feasibility and more incumbent replacements do not imply better
  final clinical quality. Combined reaches feasibility quickly but leaves many
  junior slots empty within budget.
- The Sunday imbalance above is observable; its mathematical necessity has NOT
  been proved. Do not label it an unavoidable exception or an acceptable clinical
  distribution merely because all hard constraints pass.
- Unequal personal caps make equal normalized load compatible with unequal duty
  counts and total points. A clinician should review whether that reflects the
  intended capacity policy. This study does not change Q6 or Q7.
- Current Q4 counts days with exactly one actual senior regardless of how many
  juniors accompany them. It is not a count of a doctor being entirely alone.
  Q2/Q3 count actual junior-group doctors even when one fills the senior role:
  the forced-transition case has eight Q2-covered days with zero filled OPTIONAL
  slots. This matches current definitions but must be explained in clinical
  reporting to avoid confusing group coverage with junior-position occupancy.
- Zero-cap doctors in tight fixtures are excluded from normalized Q6 comparison,
  while group membership still influences other range metrics. A large difference
  involving an unavailable zero-cap doctor need not represent repairable inequity.
- K1/K4 concentration and missing K2/K3 are deliberate stress conditions. These
  repeated levels are not a validated model of individual rank fairness.

## Code inspection and technical next steps

Inspection of `_missedMandatoryDay` and `_prune` shows checks for already missed
must days and aggregate remaining capacity. They do not scan every future
required slot for a nonempty eligible domain. `_cannotBeatIncumbentPrefix`
returns immediately without an incumbent, so Q1–Q3 bounds cannot help prove
this blocked-day case. This explains a plausible structural cause; no profiler
was used to attribute exact CPU percentages.

Next phase proposals, not changes in this stage:
1. Independently prove and oracle-test a role-aware future REQUIRED-domain
   emptiness check, preserving the distinction between A impossibility and
   whole-problem impossibility after junior substitution is allowed.
2. Expand matched randomized scenario families and repeated timing trials;
   vary one factor at a time rather than infer causality from composite fixtures.
3. Investigate coverage stagnation without changing lexicographic priorities;
   preserve exact oracle equivalence before considering any search improvement.
4. Obtain clinical acceptance of the Q4, Q2/Q3 role/group and normalized-capacity
   interpretations before integrating UI or declaring production readiness.

## Evidence limits and acceptance

48 measurements cover 11 searchable scenario identifiers (with the blocked one
at two budgets), plus a separately tested invalid-input scenario and small
boundary/coverage cases. All fixtures are synthetic. Holidays are explicitly
synthetic stress scores, not verification of the Turkish holiday calendar.
Four open monthly fixtures are not a representative clinical population. Tight
fixtures have effectively forced assignments and deliberately unavailable extra
doctors; their fast exact proofs must not be generalized to open clinics.
There is one measurement per strategy/cell; fixed ordering, shared host, JIT,
reference-check overhead and no CPU pinning limit performance conclusions.
The 30-second checkpoint shares the 120-second trajectory. No Web Worker,
Android, Firebase or clinical user acceptance test is claimed.

The planned validation matrix completed with no detected false optimum,
false infeasibility, hard-constraint violation, unsafe A/B transition, or quality
mismatch. All 136 tests passed. This is acceptance of the validation work, not
certification of clinical-scale optimality or production readiness. No solver,
objective order, pruning, default, V1 code or Firebase behavior was changed.
