# V1.3 Stage 1

The independent DutyPositions DTO serializes explicit daily roles. The optional
`dutyPositions` list is read by PositionReadResult; missing legacy position data
produces LEGACY_POSITIONS_UNKNOWN. No roles are inferred, no source map is mutated,
and no persistence adapter writes these fields yet. Existing ScheduleMonth and
V1.2 solver/repository behavior are untouched.

ConstraintValidator accepts the existing immutable personnel snapshot context and
explicit positions. Issues contain code, rule, Turkish message, applicable date
and person ID. Global errors may have no date/person. It checks complete calendar
coverage, role composition and substitution metadata, unique daily positions,
max eight, three-calendar-day rest, must/cannot and boundary rest. Counts use
unique dates irrespective of role. Candidate ordering uses active junior snapshot
members sorted by seniorityRank, with personId as deterministic tie-break.

A vacancy requires a non-empty reason, but this stage does not prove monthly
capacity exhaustion. It does not choose substitutions or prove that earlier
junior candidates are unavailable. Those proofs belong to feasibility and staged
optimization. No hierarchy/fairness optimization is implemented.

Next stages must integrate explicit versioned persistence, UI/manual-edit/finalize
validation and proof-aware solver results. Existing V1.2 writes must not be used to
round-trip future position documents until that integration is implemented. Legacy
role/group verification must be explicit before opting an old month into V1.3.
