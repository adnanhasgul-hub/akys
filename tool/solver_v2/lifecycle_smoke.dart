// Standalone Flutter build target. Does not initialize Firebase or change main.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';

void main() => runApp(const MaterialApp(home: LifecycleSmoke()));

class LifecycleSmoke extends StatefulWidget {
  const LifecycleSmoke({super.key});
  @override
  State<LifecycleSmoke> createState() => _LifecycleSmokeState();
}

class _LifecycleSmokeState extends State<LifecycleSmoke> {
  final controller = OptimizationController();
  @override
  void initState() {
    super.initState();
    unawaited(
      controller.start(
        Problem(
          startDate: DateTime.utc(2026, 11),
          doctors: [Doctor(id: 'synthetic', seniorityLevel: SeniorityLevel.k1)],
          slotsPerDay: [1],
          slotRoles: [DutyRole.senior],
          slotRequirements: [SlotRequirement.required],
          dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AKYS V2 lifecycle smoke')),
    body: StreamBuilder<OptimizationSnapshot>(
      stream: controller.events,
      initialData: controller.value,
      builder: (context, snapshot) {
        final s = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${OptimizationController.platform}\n${s.state.name} / ${s.proof.name}\nNodes: ${s.nodes}\n${s.error ?? ""}',
          ),
        );
      },
    ),
  );
}
