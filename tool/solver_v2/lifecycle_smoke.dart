// Standalone Flutter target; synthetic data, no Firebase initialization or V1 edits.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';

import 'clinical_resilience.dart';

void main() => runApp(const MaterialApp(home: LifecycleSmoke()));

class LifecycleSmoke extends StatefulWidget {
  const LifecycleSmoke({super.key});
  @override
  State<LifecycleSmoke> createState() => _LifecycleSmokeState();
}

class _LifecycleSmokeState extends State<LifecycleSmoke> {
  final controller = OptimizationController.webSupported
      ? OptimizationController.web(workerUri: Uri.parse('akys_v2_worker.js'))
      : OptimizationController();
  StreamSubscription<OptimizationSnapshot>? observation;
  SemanticsHandle? semantics;
  Timer? repaint;
  var frames = 0, ticks = 0, taps = 0, measuring = false;
  @override
  void initState() {
    super.initState();
    semantics = WidgetsBinding.instance.ensureSemantics();
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (mounted && measuring) frames++;
    });
    observation = controller.events.listen((s) {
      debugPrint('AKYS_SMOKE:${s.state.name}:${s.proof.name}:${s.error ?? ""}');
    });
    unawaited(exercise());
  }

  Future<void> waitFor(OptimizationState state) async {
    if (controller.value.state != state) {
      await controller.events
          .firstWhere(
            (s) => s.state == state || s.state == OptimizationState.failed,
          )
          .timeout(const Duration(seconds: 15));
    }
    if (controller.value.state == OptimizationState.failed) {
      throw StateError(controller.value.error!);
    }
  }

  Future<void> exercise() async {
    try {
      await controller.start(
        Problem(
          startDate: DateTime.utc(2026, 11),
          doctors: [Doctor(id: 'synthetic', seniorityLevel: SeniorityLevel.k1)],
          slotsPerDay: [1],
          slotRoles: [DutyRole.senior],
          slotRequirements: [SlotRequirement.required],
          dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
        ),
      );
      await waitFor(OptimizationState.optimal);
      if (!mounted) return;
      measuring = true;
      repaint = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (mounted) setState(() => ticks++);
      });
      debugPrint('AKYS_SMOKE_BACKGROUND_START');
      await controller.start(
        resilienceProblem('6-open'),
        options: const OptimizationOptions(
          budget: Duration(milliseconds: 1500),
          candidateOrdering: true,
          earlyDeadEnds: true,
          experimentalTwoPhase: true,
          clinicalBounds: true,
        ),
      );
      await waitFor(OptimizationState.timedOut);
      measuring = false;
      repaint?.cancel();
      debugPrint(
        'AKYS_SMOKE_BACKGROUND:frames=$frames;ticks=$ticks;taps=$taps;nodes=${controller.value.nodes}',
      );
      await controller.cancel();
    } catch (e) {
      debugPrint('AKYS_SMOKE_FAILURE:$e');
    }
  }

  @override
  void dispose() {
    repaint?.cancel();
    semantics?.dispose();
    unawaited(observation?.cancel());
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
          child: Column(
            children: [
              Text(
                '${s.state.name} / ${s.proof.name}\nNodes: ${s.nodes}\nFrames: $frames / Ticks: $ticks\n${s.error ?? ""}',
              ),
              TextButton(
                onPressed: () {
                  setState(() => taps++);
                  debugPrint('AKYS_SMOKE_TAP:nodes=${controller.value.nodes}');
                },
                child: const Text('Responsiveness tap'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
