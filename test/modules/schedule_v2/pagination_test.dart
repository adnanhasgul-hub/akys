import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/schedule_v2/data/draft_repository.dart';

import 'persistence_test.dart' as fixtures;

void main() {
  test('125 headers with tied timestamps paginate deterministically without payloads', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreDraftRepository(db, fixtures.Authorization());
    final at = Timestamp.fromDate(DateTime.utc(2026));
    for (var i = 0; i < 125; i++) {
      await db
          .collection('v2_schedules')
          .doc('id${i.toString().padLeft(3, '0')}')
          .set({
            'version': 1,
            'year': 2026,
            'month': 11,
            'status': 'draft',
            'actor': 'admin',
            'summary': 'Test',
            'at': at,
          });
    }
    final ids = <String>[];
    DraftPage? page;
    do {
      page = await repo.page(after: page?.cursor);
      ids.addAll(page.items.map((e) => e.id));
    } while (page.hasMore);
    expect(ids.length, 125);
    expect(ids.toSet().length, 125);
    expect(ids, [...ids]..sort((a, b) => b.compareTo(a)));
    // No version documents exist: a list implementation doing N+1 opens fails.
    expect((await repo.page(after: page.cursor)).items, isEmpty);
  });
  test(
    'history beyond 100 keeps numeric version order and bounded pages',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreDraftRepository(db, fixtures.Authorization());
      for (var i = 1; i <= 125; i++) {
        await db.collection('v2_schedules/x/versions').doc('$i').set({
          'version': i,
          'year': 2026,
          'month': 11,
          'status': 'draft',
          'actor': 'admin',
          'summary': 'Test',
          'at': Timestamp.now(),
        });
      }
      final versions = <int>[];
      DraftPage? page;
      do {
        page = await repo.page(
          scheduleId: 'x',
          after: page?.cursor,
          pageSize: 13,
        );
        expect(page.items.length, lessThanOrEqualTo(13));
        versions.addAll(page.items.map((e) => e.version));
      } while (page.hasMore);
      expect(versions, List.generate(125, (i) => 125 - i));
      await expectLater(repo.page(pageSize: 51), throwsArgumentError);
    },
  );
}
