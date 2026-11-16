import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/clinical_approval/approval.dart';
import 'persistence_test.dart' as fixtures;

void main() {
  test('server A policy validates without optimum or portable proof', () {
    final snapshot = validateForApproval(fixtures.fixture().encode());
    expect(snapshot.hasTransition, false);
    expect(snapshot.optimalityProven, false);
  });
  test('server rejects incomplete, B, changed locks and portable proof', () {
    for (final payload in [
      fixtures.fixture(incomplete: true).encode(),
      fixtures.fixture(transition: true).encode(),
      jsonEncode({
        ...jsonDecode(fixtures.fixture().encode()) as Map,
        'proved': true,
      }),
      jsonEncode({
        ...jsonDecode(fixtures.fixture().encode()) as Map,
        'locks': {'0': 1},
      }),
      '{',
    ]) {
      expect(
        () => validateForApproval(payload),
        throwsA(isA<ApprovalRejected>()),
      );
    }
  });
}
