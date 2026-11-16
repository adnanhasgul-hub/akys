import 'dart:convert';
import 'dart:io';

import 'package:akys/modules/schedule_v2/data/draft_repository.dart';
import 'package:akys/modules/schedule_v2/data/draft_session.dart';
import 'package:akys/modules/schedule_v2/workspace.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../clinical_resilience.dart';

class _Auth implements DraftAuthorization {
  @override
  Future<String> requireAdmin() async => 'synthetic-admin';
}

void main() {
  test('saved draft dirty-check profile (no search or Firebase)', () async {
    final rows = <Object>[];
    for (final fixture in ['6-open', '15-open']) {
      final workspace = ScheduleWorkspace(initial: resilienceProblem(fixture));
      final session = DraftSession(
        workspace,
        FirestoreDraftRepository(FakeFirebaseFirestore(), _Auth()),
      );
      await session.save();
      expect(session.error, isNull);
      for (var repeat = 0; repeat < 3; repeat++) {
        final watch = Stopwatch()..start();
        for (var i = 0; i < 1000; i++) {
          expect(session.dirty, false);
        }
        watch.stop();
        rows.add({
          'fixture': fixture,
          'repeat': repeat,
          'reads': 1000,
          'microseconds': watch.elapsedMicroseconds,
        });
      }
      session.dispose();
      workspace.dispose();
    }
    final output = Platform.environment['AKYS_PROFILE_OUTPUT'];
    if (output != null) File(output).writeAsStringSync('${jsonEncode(rows)}\n');
    // ignore: avoid_print
    print(jsonEncode(rows));
  });
}
