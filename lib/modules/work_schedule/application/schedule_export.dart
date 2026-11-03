import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/models.dart';
import '../data/schedule_repository.dart';
import '../engine/task_engine.dart';
import '../engine/duty_engine.dart';

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
String _column(int n) {
  var text = '';
  do {
    text = String.fromCharCode(65 + n % 26) + text;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return text;
}

String _sheet(List<List<String>> rows, {int? taskHeader}) {
  final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  final data = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    final style = i == 0
        ? 1
        : (i == 2 || i == taskHeader
              ? 2
              : (i > 2 &&
                        i < rows.length &&
                        rows[i].length > 1 &&
                        (rows[i][1] == 'Cumartesi' || rows[i][1] == 'Pazar')
                    ? 3
                    : 0));
    data.write('<row r="${i + 1}" ht="${i == 0 ? 32 : 24}" customHeight="1">');
    for (var j = 0; j < rows[i].length; j++) {
      data.write(
        '<c r="${_column(j)}${i + 1}" s="$style" t="inlineStr"><is><t xml:space="preserve">${_xml(rows[i][j])}</t></is></c>',
      );
    }
    data.write('</row>');
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="15" customWidth="1"/><col min="2" max="$cols" width="30" customWidth="1"/></cols><sheetData>$data</sheetData><mergeCells count="1"><mergeCell ref="A1:${_column(cols - 1)}1"/></mergeCells><printOptions horizontalCentered="1"/><pageMargins left="0.25" right="0.25" top="0.4" bottom="0.4" header="0.2" footer="0.2"/><pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="1"/><headerFooter><oddFooter>&amp;C AKYS · &amp;P / &amp;N</oddFooter></headerFooter></worksheet>';
}

Uint8List exportExcel(ScheduleMonth m) {
  if (m.editable) throw StateError('Excel için önce çizelgeyi kesinleştirin.');
  String names(List<String> ids) =>
      ids.map((id) => m.person(id).displayName).join(', ');
  final duties = <List<String>>[
    ['${m.title} Ayı Asistan Doktor Nöbet Çizelgesi'],
    ['AKYS · A Klinik Yönetim Sistemi · ${statusLabel(m.status)}'],
    [
      'Tarih',
      'Gün',
      '1. Nöbetçi',
      '2. Nöbetçi',
      '3. Nöbetçi',
      'Zorluk Puanı',
      'Tatil / Özel Gün',
    ],
  ];
  for (var d = 1; d <= m.days; d++) {
    final ids = m.duties[d] ?? [];
    duties.add([
      dateKey(m.date(d)),
      dayNames[m.date(d).weekday - 1],
      for (var i = 0; i < 3; i++)
        i < ids.length ? m.person(ids[i]).displayName : '',
      '${m.difficultyScore(d)}',
      m.difficulty.holiday(m.date(d)) == null
          ? (m.difficulty.isPreHoliday(m.date(d)) ? 'Tatil öncesi' : '')
          : '${m.difficulty.holiday(m.date(d))!.name} (${m.difficulty.holiday(m.date(d))!.isHalfDay ? 'Yarım gün' : 'Tam gün'})',
    ]);
  }
  duties.add([]);
  final taskHeader = duties.length;
  duties.add(['Görev', 'Asıl', 'Yedek']);
  for (final task in ClinicTask.values) {
    final a = m.tasks[task];
    duties.add([
      taskLabel(task),
      a == null ? 'Seçilmedi' : m.person(a.primary).displayName,
      a == null ? 'Seçilmedi' : m.person(a.backup).displayName,
    ]);
  }
  final combined = <List<String>>[
    ['${m.title} Birleşik Çizelge'],
    ['Nöbet ertesi yedekler ve manuel görevler dahil'],
    [
      'Tarih',
      'Gün',
      'Nöbetçiler',
      ...ClinicTask.values.map(taskLabel),
      'Zorluk Puanı',
      'Tatil / Özel Gün',
    ],
  ];
  for (var d = 1; d <= m.days; d++) {
    combined.add([
      dateKey(m.date(d)),
      dayNames[m.date(d).weekday - 1],
      names(m.duties[d] ?? []),
      for (final t in dailyTasks(m, d))
        t.personId == null
            ? 'Görev karşılanamıyor'
            : '${m.person(t.personId!).displayName}${t.manual ? ' (Manuel)' : ''}${t.warnings.isNotEmpty ? ' ⚠' : ''}',
      '${m.difficultyScore(d)}',
      m.difficulty.holiday(m.date(d))?.name ??
          (m.difficulty.isPreHoliday(m.date(d)) ? 'Tatil öncesi' : ''),
    ]);
  }
  duties.add([]);
  duties.add([
    'Personel',
    'Toplam',
    'Tek',
    'Eşli',
    'Resmî Tatil',
    'Zorluk Puanı',
  ]);
  final stats = statistics(m);
  for (final p in m.people) {
    final s = stats[p.personId]!;
    duties.add([
      p.displayName,
      '${s.total}',
      '${s.solo}',
      '${s.paired}',
      '${s.holidayDuties}',
      '${s.totalDifficulty}',
    ]);
  }
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add(
    '[Content_Types].xml',
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${[1, 2].map((i) => '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>',
  );
  add(
    '_rels/.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Nöbet Çizelgesi" sheetId="1" r:id="rId1"/><sheet name="Birleşik Çizelge" sheetId="2" r:id="rId2"/></sheets><definedNames><definedName name="_xlnm.Print_Titles" localSheetId="0">\'Nöbet Çizelgesi\'!\$1:\$3</definedName><definedName name="_xlnm.Print_Area" localSheetId="0">\'Nöbet Çizelgesi\'!\$A\$1:\$G\$${duties.length}</definedName></definedNames></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
  );
  add(
    'xl/styles.xml',
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="10"/><name val="Calibri"/></font><font><b/><sz val="16"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font><font><b/><sz val="10"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF176B65"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFF1F2"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left style="hair"/><right style="hair"/><top style="hair"/><bottom style="hair"/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf fontId="0" fillId="0" borderId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf fontId="1" fillId="2" borderId="0" applyFill="1" applyFont="1"/><xf fontId="2" fillId="2" borderId="0" applyFill="1" applyFont="1"/><xf fontId="0" fillId="3" borderId="0" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
  );
  add('xl/worksheets/sheet1.xml', _sheet(duties, taskHeader: taskHeader));
  add('xl/worksheets/sheet2.xml', _sheet(combined));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _icsEscape(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', r'\n')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r', '');
String _fold(String line) {
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (bytes + n > 75) {
      out.write('\r\n ');
      bytes = 1;
    }
    out.write(ch);
    bytes += n;
  }
  return out.toString();
}

Uint8List exportIcs(Map<String, dynamic> projection, String personId) {
  final people = projection['people'] as List;
  if (!people.any((p) => (p as Map)['personId'] == personId)) {
    throw ArgumentError('Personel bulunamadı.');
  }
  final year = projection['year'] as int,
      month = projection['month'] as int,
      days = projection['days'] as int;
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//AKYS//Calisma Cizelgesi V1//TR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
  ];
  for (var d = 1; d <= days; d++) {
    final labels = <String>[];
    if (((projection['duties'] as Map)['$d'] as List? ?? []).contains(
      personId,
    )) {
      labels.add('Nöbet');
    }
    for (final t in (projection['dailyTasks'] as Map)['$d'] as List? ?? []) {
      if ((t as Map)['personId'] == personId) {
        labels.add(taskLabel(ClinicTask.values.byName(t['task'] as String)));
      }
    }
    for (final label in labels) {
      final date = DateTime.utc(year, month, d);
      String stamp(DateTime v) => dateKey(v).replaceAll('-', '');
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${projection['monthId']}-$d-${ClinicTask.values.indexWhere((t) => taskLabel(t) == label)}-$personId@akys',
        'DTSTAMP:${stamp(DateTime.utc(year, month, 1))}T000000Z',
        'DTSTART;VALUE=DATE:${stamp(date)}',
        'DTEND;VALUE=DATE:${stamp(date.add(const Duration(days: 1)))}',
        'SUMMARY:${_icsEscape('KVC $label')}',
        'END:VEVENT',
      ]);
    }
  }
  lines.add('END:VCALENDAR');
  return Uint8List.fromList(
    utf8.encode('${lines.map(_fold).join('\r\n')}\r\n'),
  );
}

Uint8List personalIcs(ScheduleMonth m, String id) =>
    exportIcs(publicProjection(m), id);
