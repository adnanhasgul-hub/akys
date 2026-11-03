import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/application/schedule_export.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';

import 'engine_test.dart' show sample;

void main() {
  test('Real XLSX contains print layout, duty rows, five primary/backup tasks and combined sheet', () {
    final m = sample(2026, 11)..status = MonthStatus.finalised;
    m.duties[7] = ['p1', 'p2', 'p3'];
    m.tasks[ClinicTask.outpatient] = const TaskAssignment('p1', 'p2');
    final bytes = exportExcel(m);
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.findFile('[Content_Types].xml'), isNotNull);
    final sheet = utf8.decode(
      zip.findFile('xl/worksheets/sheet1.xml')!.content,
    );
    expect(sheet, contains('2026 Kasım Ayı Asistan Doktor'));
    expect(sheet, contains('3. Nöbetçi'));
    expect(sheet, contains('Epikriz Düzenleme'));
    expect(sheet, contains('orientation="landscape"'));
    expect(sheet, contains('t="inlineStr"'));
    expect(zip.findFile('xl/worksheets/sheet2.xml'), isNotNull);
    expect(() => exportExcel(sample(2026, 11)), throwsStateError);
  });
  test('Public projection excludes conditions, overrides, registry, boundary and share tokens', () {
    final m = sample(2026, 11);
    m.boundary['p1'] = ['2026-10-31'];
    m.shareTokens.add('secret-capability');
    m.constraints['p1']!.cannot.add(1);
    final p = publicProjection(m);
    expect(
      p.keys.toSet().intersection({
        'constraints',
        'boundaryConditions',
        'shareTokens',
        'createdAt',
        'overrides',
      }),
      isEmpty,
    );
    expect(jsonEncode(p), isNot(contains('secret-capability')));
  });
  test('ICS is RFC-style UTF8 CRLF all-day with exclusive next day end and personal filter', () {
    final m = sample(2026, 12);
    m.duties[31] = ['p1'];
    m.tasks[ClinicTask.ward] = const TaskAssignment('p1', 'p2');
    final text = utf8.decode(personalIcs(m, 'p1'));
    expect(text, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0'));
    expect(text, contains('SUMMARY:KVC Nöbet'));
    expect(text, contains('DTSTART;VALUE=DATE:20261231'));
    expect(text, contains('DTEND;VALUE=DATE:20270101'));
    expect(text, contains('SUMMARY:KVC Servis'));
    for (final line in text.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }
    expect(() => personalIcs(m, 'missing'), throwsArgumentError);
  });
  test('Canonical Firestore comparisons ignore map key order', () {
    expect(
      canonical({
        'b': 2,
        'a': {'y': 2, 'x': 1},
      }),
      canonical({
        'a': {'x': 1, 'y': 2},
        'b': 2,
      }),
    );
  });
}
