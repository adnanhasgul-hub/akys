// Test-only preconfigured workspace. Same application page and real transport.
import 'package:flutter/material.dart';
import 'package:akys/modules/schedule_v2/v2_app.dart';
import 'package:akys/modules/schedule_v2/workspace.dart';
import 'package:akys/solver_v2/solver.dart';

import 'clinical_resilience.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  final long = Uri.base.queryParameters['fixture'] == 'long';
  final transition = Uri.base.queryParameters['fixture'] == 'transition';
  final p = long
      ? resilienceProblem('6-open')
      : Problem(
          doctors: [
            Doctor(
              id: 'senior',
              seniorityLevel: SeniorityLevel.k4,
              unavailable: transition ? {0} : {},
            ),
            Doctor(id: 'junior', group: DutyGroup.junior),
          ],
          startDate: DateTime.utc(2026, 11),
          slotsPerDay: [for (var d = 0; d < 30; d++) d == 0 || d == 3 ? 2 : 0],
          slotRoles: [
            DutyRole.senior,
            DutyRole.junior,
            DutyRole.senior,
            DutyRole.junior,
          ],
          slotRequirements: [
            SlotRequirement.required,
            SlotRequirement.optional,
            SlotRequirement.required,
            SlotRequirement.optional,
          ],
          dayDifficulties: List.filled(
            30,
            const DayDifficulty(weekdayScore: 3),
          ),
        );
  final w = ScheduleWorkspace(initial: p);
  for (var i = 0; i < p.doctors.length; i++) {
    w.names[p.doctors[i].id] = 'Test Hekimi ${i + 1}';
  }
  runApp(V2App(workspace: w));
}
