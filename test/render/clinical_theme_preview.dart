// Local visual acceptance entrypoint ONLY. Production still builds lib/main.dart.
// All auth and Firestore state is in-memory; no Firebase initialization/credentials.
import 'package:flutter/material.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/app/akys_app.dart';
import 'package:akys/modules/work_schedule/engine/v13/fairness_optimizer.dart';
import 'package:akys/core/auth/auth_service.dart';
import 'package:akys/core/auth/auth_state.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';

class RenderAuth extends AuthService {
  RenderAuth(this.status);
  AuthStatus status;
  @override
  AuthState get state => AuthState(status);
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
  await repo.initialize();
  final people = await repo.watchPersonnel().firstWhere((p) => p.isNotEmpty);
  final m = ScheduleMonth(
    year: 2026,
    month: 11,
    people: [
      for (final p in people)
        PersonSnapshot(
          p.id,
          p.displayName,
          p.seniorityRank,
          dutySeniorityGroup: p.dutySeniorityGroup,
        ),
    ],
    createdAt: 'fixture',
    updatedAt: 'fixture',
    requiredDuties: 54,
    taskWorkdaySchemaVersion: 1,
  );
  m.boundaryConfirmed = true;
  final result = await const FairnessOptimizer(nodeLimit: 10000).optimize(m);
  m.dutyPositions = result.solver.positions;
  m.engineVersion = '1.3.0';
  for (final row in m.dutyPositions!) {
    m.duties[int.parse(row.date.substring(8))] = [
      row.seniorDutyPersonId!,
      ...row.juniorDutyPersonIds,
    ];
  }
  m.v13Diagnostics = {
    'status': result.solver.statusCode,
    'optimalityProven': false,
    'hierarchyProven': false,
  };
  for (final task in ClinicTask.values) {
    m.tasks[task] = TaskAssignment(people[0].id, people[1].id);
  }
  await repo.saveMonth(m, create: true);
  runApp(
    AkysApp(
      auth: RenderAuth(
        Uri.base.queryParameters.containsKey('login')
            ? AuthStatus.signedOut
            : AuthStatus.authorized,
      ),
      scheduleRepository: repo,
    ),
  );
}
