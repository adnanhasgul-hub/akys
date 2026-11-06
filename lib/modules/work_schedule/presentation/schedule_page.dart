import '../../../core/design/akys_design_system.dart';
import '../engine/v13/constraint_validator.dart';
import 'compact_duty_card.dart';
import 'reference_schedule_widgets.dart';
import '../engine/task_engine.dart';
import 'combined_day_cards.dart';
import 'v13_solver_panel.dart';

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/akys_colors.dart';
import '../../../core/platform/export_file.dart';
import '../application/schedule_controller.dart';
import '../application/schedule_export.dart';
import '../data/schedule_repository.dart';
import '../domain/models.dart';
import '../domain/difficulty.dart';
import 'difficulty_widgets.dart';
import '../engine/duty_engine.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({required this.repository, this.logout, super.key});
  final ScheduleRepository repository;
  final Widget? logout;
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final ScheduleController c;
  int section = 0;
  int dutyView = 0, personnelFilter = 0, taskDay = 1;
  static const sections = [
    'Genel Bakış',
    'Nöbet',
    'Görev Dağılımı',
    'Personel',
    'Geçmiş Aylar',
    'Birleşik Görünüm',
    'Ayarlar',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.calendar_month,
    Icons.assignment_outlined,
    Icons.groups_outlined,
    Icons.history,
    Icons.table_chart_outlined,
    Icons.settings_outlined,
  ];
  @override
  void initState() {
    super.initState();
    c = ScheduleController(widget.repository)..initialize();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Onayla'),
            ),
          ],
        ),
      ) ??
      false;
  Future<String?> textInput(
    String title, {
    String initial = '',
    String hint = 'Ad soyad',
    int max = 120,
  }) async {
    final controller = TextEditingController(text: initial);
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLength: max,
            decoration: InputDecoration(labelText: hint),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Bu alan zorunlu.' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    // Dialog route disposes its text field after the exit animation.
    return result;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final body = LayoutBuilder(
        builder: (context, bounds) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: bounds.maxHeight * .55),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (c.busy) const LinearProgressIndicator(),
                    if (c.error != null) _message(c.error!, true),
                    if (c.notice != null) _message(c.notice!, false),
                    if (section != 3 &&
                        section != 6 &&
                        !(section == 0 && c.month != null))
                      _monthBar(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: c.loading
                  ? const Center(
                      child: SingleChildScrollView(
                        child: AkysLoadingState(label: 'Çizelge yükleniyor'),
                      ),
                    )
                  : PrimaryScrollController.none(
                      child: IndexedStack(
                        key: const ValueKey('schedule-pages'),
                        index: section,
                        children: [
                          _overview(),
                          _duty(),
                          _tasks(),
                          _personnel(),
                          _history(),
                          _combined(),
                          DifficultySettingsPanel(
                            key: ValueKey(c.difficultySettings.revision),
                            settings: c.difficultySettings,
                            busy: c.busy,
                            onSave: c.saveDifficulty,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AkysTokens.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: section == 0 ? 72 : 58,
          leading: section == 0
              ? IconButton(
                  tooltip: 'Ana sayfa',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.medical_services_outlined, size: 30),
                )
              : null,
          title: section == 0
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AKYS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'A Klinik Yönetim Sistemi',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                )
              : Text(
                  section == 1 ? 'Nöbet Çizelgesi' : sections[section],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          actions: [
            if (section == 3)
              IconButton(
                tooltip: 'Personel ekle',
                icon: const Icon(Icons.add),
                onPressed: c.busy ? null : _addPerson,
              ),
            IconButton(
              tooltip: 'Ay ve işlemler',
              icon: Icon(
                section == 3 || section == 6
                    ? Icons.more_horiz
                    : Icons.calendar_month_outlined,
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListenableBuilder(
                          listenable: c,
                          builder: (_, _) => _monthBar(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.auto_awesome),
                          title: const Text('Nöbet Hazırla'),
                          onTap: c.busy
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _createMonth();
                                },
                        ),
                        ListTile(
                          leading: const Icon(Icons.refresh),
                          title: const Text('Yeniden yükle'),
                          onTap: c.busy
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  c.initialize();
                                },
                        ),
                        if (widget.logout != null) widget.logout!,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: AkysAdaptiveNavigation(
            destinations: [
              for (final i in [0, 1, 2, 3, 5, 4, 6])
                AkysDestination(
                  label: i == 2 ? 'Görevler' : sections[i],
                  icon: icons[i],
                ),
            ],
            selectedIndex: [0, 1, 2, 3, 5, 4, 6].indexOf(section),
            enabled: !c.busy,
            onSelected: (i) {
              if (!c.busy) setState(() => section = [0, 1, 2, 3, 5, 4, 6][i]);
            },
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AkysTokens.maxContent,
                ),
                child: body,
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _monthBar() {
    final ordered = [...c.months]..sort((a, b) => a.id.compareTo(b.id));
    final index = ordered.indexWhere((m) => m.id == c.selectedId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Önceki kayıtlı ay',
            onPressed: c.busy || index <= 0
                ? null
                : () => c.select(ordered[index - 1].id),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('month-${c.selectedId}'),
              initialValue: c.month?.id,
              isExpanded: true,
              alignment: Alignment.center,
              icon: const SizedBox.shrink(),
              decoration: const InputDecoration(
                hintText: 'Çalışılan ay',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
              ),
              selectedItemBuilder: (context) => [
                for (final m in ordered)
                  Center(
                    child: Text(
                      '${monthNames[m.month - 1]} ${m.year}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
              items: [
                for (final m in ordered)
                  DropdownMenuItem(
                    value: m.id,
                    child: Center(
                      child: Text(
                        '${m.title} · ${statusLabel(m.status)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
              onChanged: c.busy
                  ? null
                  : (id) {
                      if (id != null) c.select(id);
                    },
            ),
          ),
          IconButton(
            tooltip: 'Sonraki kayıtlı ay',
            onPressed: c.busy || index < 0 || index >= ordered.length - 1
                ? null
                : () => c.select(ordered[index + 1].id),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _message(String text, bool error) => Container(
    width: double.infinity,
    color: (error ? AkysColors.forbidden : AkysColors.brand).withValues(
      alpha: 0.10,
    ),
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Icon(
          error ? Icons.error_outline : Icons.check_circle_outline,
          color: error ? AkysColors.forbidden : AkysColors.brand,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
        IconButton(
          tooltip: 'Kapat',
          onPressed: () {
            c.error = null;
            c.notice = null;
            c.emit();
          },
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
  Widget empty(String text) => Center(
    child: SingleChildScrollView(
      child: AkysEmptyState(title: 'Henüz içerik yok', message: text),
    ),
  );
  List<String> _hardWarnings(ScheduleMonth m) => m.dutyPositions != null
      ? const ConstraintValidator()
            .validate(m, m.dutyPositions!)
            .map((e) => e.message)
            .toList()
      : m.duties.isEmpty
      ? []
      : validateDuties(m);
  Widget _overview() {
    final m = c.month;
    final stats = m == null ? null : statistics(m);
    final total = stats?.values.fold<int>(0, (n, p) => n + p.total) ?? 0;
    final points =
        stats?.values.fold<int>(0, (n, p) => n + p.totalDifficulty) ?? 0;
    final vacancies = m?.dutyPositions
        ?.where((p) => p.juniorDutyPersonIds.isEmpty)
        .length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Merhaba',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      m == null
                          ? 'Planlamaya başlamak için bir ay seçin.'
                          : '${monthNames[m.month - 1]} ${m.year} · ${statusLabel(m.status)}',
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/clinical_team.jpg',
                  width: 116,
                  height: 86,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AkysResponsiveTiles(
          maxColumns: 4,
          children: [
            ScheduleMetric(
              label: 'Aktif Personel',
              value: '${c.personnel.where((p) => p.active).length}',
              icon: Icons.groups,
            ),
            ScheduleMetric(
              label: 'Gün',
              value: m == null ? '—' : '${m.days}',
              icon: Icons.calendar_month_outlined,
            ),
            ScheduleMetric(
              label: 'Planlanan Nöbet',
              value: m == null
                  ? '—'
                  : '${m.duties.values.where((d) => d.isNotEmpty).length}',
              icon: Icons.bed_outlined,
            ),
            ScheduleMetric(
              label: 'Boş Çömez',
              value: vacancies == null ? '—' : '$vacancies',
              icon: Icons.warning_amber_rounded,
              warning: true,
            ),
          ],
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: c.busy ? null : _createMonth,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Nöbet Hazırla'),
        ),
        const SizedBox(height: 16),
        AkysCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ay Özeti',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              _summaryRow(Icons.groups_outlined, 'Toplam Nöbet', '$total'),
              _summaryRow(
                Icons.assignment_outlined,
                'Toplam Zorluk Puanı',
                '$points',
              ),
              _summaryRow(
                Icons.bar_chart,
                'Ortalama Puan',
                total == 0
                    ? '—'
                    : (points / total).toStringAsFixed(2).replaceAll('.', ','),
              ),
            ],
          ),
        ),
        if (m == null)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Ay seçilmedi. Takvim simgesinden kayıtlı bir ay seçin.',
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Planlama ayrıntıları'),
          children: [
            Text(
              '${c.months.length} kayıtlı ay · ${c.months.where((m) => !m.editable).length} kesin / paylaşılan ay',
            ),
            if (m != null) ...[
              Text('${_hardWarnings(m).length} zorunlu kural uyarısı'),
              if (vacancies == null)
                const Text(
                  'Eski ay: pozisyon bilgisi kayıtlı değil; boş junior sayısı tahmin edilmez.',
                ),
              TextButton(
                onPressed: () => setState(() => section = 1),
                child: const Text('Nöbet çizelgesini aç'),
              ),
            ],
          ],
        ),
        const ExpansionTile(
          title: Text('Planlama yardımı'),
          children: [
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Personeli ve ay snapshot’ını kontrol edin. Nöbet ekranındaki Planlama araçları üzerinden kısıtları, solver önizlemesini ve istatistikleri açın. V1.3 yalnız taslak kaydedilir; kesinleştirme ve paylaşım kapalıdır.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 19, color: AkysTokens.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(title)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Future<void> _addPerson() async {
    final name = await textInput('Personel Ekle');
    if (name != null) await c.addPerson(name);
  }

  Widget _personnel() {
    final people = c.personnel
        .where(
          (p) =>
              personnelFilter == 0 ||
              (personnelFilter == 1
                  ? p.dutySeniorityGroup == DutySeniorityGroup.senior
                  : p.dutySeniorityGroup == DutySeniorityGroup.junior),
        )
        .toList();
    return ReorderableListView.builder(
      header: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ScheduleSegments(
          labels: [
            'Tümü (${c.personnel.length})',
            'Kıdemli (${c.personnel.where((p) => p.dutySeniorityGroup == DutySeniorityGroup.senior).length})',
            'Çömez (${c.personnel.where((p) => p.dutySeniorityGroup == DutySeniorityGroup.junior).length})',
          ],
          selected: personnelFilter,
          onChanged: (i) => setState(() => personnelFilter = i),
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            const Text(
              'Sıralamak için tutamacı sürükleyin. K1 en kıdemlidir.',
              style: TextStyle(fontSize: 11),
            ),
            TextButton.icon(
              onPressed: c.busy ? null : _addPerson,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Personel Ekle'),
            ),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: people.length,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) async {
        if (c.busy || personnelFilter != 0) return;
        final after = [...c.personnel];
        after.insert(newIndex, after.removeAt(oldIndex));
        await c.updatePeople(after);
      },
      itemBuilder: (context, i) =>
          _personCard(people[i], c.personnel.indexOf(people[i])),
    );
  }

  Widget _personCard(Personnel p, int index) {
    final stat = c.month == null ? null : statistics(c.month!)[p.id];
    return Padding(
      key: ValueKey(p.id),
      padding: const EdgeInsets.only(bottom: 6),
      child: AkysCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: ValueKey('person-details-${p.id}'),
          dense: true,
          minTileHeight: 60,
          visualDensity: VisualDensity.compact,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.all(12),
          leading: rankBadge(p.seniorityRank),
          title: Text(
            p.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            '${dutyGroupLabel(p.dutySeniorityGroup)} · ${p.active ? (stat == null ? 'Aktif' : '${stat.total} nöbet · Ort. Puan: ${stat.total == 0 ? '—' : (stat.totalDifficulty / stat.total).toStringAsFixed(1)}') : 'Pasif'}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: ReorderableDragStartListener(
            index: index,
            enabled: !c.busy && personnelFilter == 0,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_indicator, size: 18),
            ),
          ),
          children: [
            TextButton.icon(
              onPressed: c.busy
                  ? null
                  : () async {
                      final name = await textInput(
                        'İsmi düzenle',
                        initial: p.displayName,
                      );
                      if (name != null) {
                        await c.updatePeople([
                          for (final x in c.personnel)
                            if (x.id == p.id) x.copy(name: name) else x,
                        ]);
                      }
                    },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('İsmi düzenle'),
            ),
            const Text(
              'Genel kıdem sırası tutamaçla değiştirilir. Nöbet kısıtları seçili ayın Nöbet ekranında düzenlenir.',
            ),
            Text(
              p.profession == 'resident_physician'
                  ? 'Asistan Hekim'
                  : p.profession,
            ),
            if (c.month != null &&
                c.month!.people.any((person) => person.personId == p.id)) ...[
              Text(
                'Seçili ay: ${c.month!.title} · Tutamaz: ${c.month!.constraints[p.id]?.cannot.length ?? 0} · Tutacak: ${c.month!.constraints[p.id]?.must.length ?? 0}',
              ),
              TextButton.icon(
                onPressed: c.busy ? null : () => setState(() => section = 1),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Ayın nöbet kısıtlarına git'),
              ),
            ],

            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: p.active,
                      onChanged: c.busy
                          ? null
                          : (active) async {
                              if (!active &&
                                  !await confirm(
                                    'Personeli pasifleştir',
                                    '${p.displayName} yeni aylara dahil edilmeyecek. Geçmiş aylar korunacak.',
                                  )) {
                                return;
                              }
                              await c.updatePeople([
                                for (final x in c.personnel)
                                  if (x.id == p.id)
                                    x.copy(active: active)
                                  else
                                    x,
                              ]);
                            },
                    ),
                    Text(p.active ? 'Aktif' : 'Pasif'),
                  ],
                ),
                SizedBox(
                  width: 180,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Nöbet Grubu',
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<DutySeniorityGroup>(
                        key: ValueKey('duty-group-${p.id}'),
                        value: p.dutySeniorityGroup,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          for (final group in DutySeniorityGroup.values)
                            DropdownMenuItem(
                              value: group,
                              child: Text(dutyGroupLabel(group)),
                            ),
                        ],
                        onChanged: c.busy
                            ? null
                            : (group) async {
                                if (group != null) {
                                  await c.updatePeople([
                                    for (final x in c.personnel)
                                      if (x.id == p.id)
                                        x.copy(dutySeniorityGroup: group)
                                      else
                                        x,
                                  ]);
                                }
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createMonth() async {
    if (c.personnel.where((p) => p.active).isEmpty) {
      c.error = 'Önce aktif personel ekleyin.';
      c.emit();
      return;
    }
    final now = DateTime.now();
    var year = now.year, month = now.month;
    final count = c.personnel.where((p) => p.active).length;
    final total = TextEditingController(
      text: '${min(count * 8, DateTime.utc(year, month + 1, 0).day * 2)}',
    );
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Nöbet Hazırla · Ay Seç'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: year,
                    decoration: const InputDecoration(labelText: 'Yıl'),
                    items: [
                      for (var y = 2020; y <= 2100; y++)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => update(() => year = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: month,
                    decoration: const InputDecoration(labelText: 'Ay'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(
                          value: m,
                          child: Text(monthNames[m - 1]),
                        ),
                    ],
                    onChanged: (v) => update(() => month = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: total,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Toplam aylık nöbet ihtiyacı',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      final days = DateTime.utc(year, month + 1, 0).day;
                      return n == null ||
                              n < days ||
                              n > min(count * 8, days * 3)
                          ? '$days–${min(count * 8, days * 3)} arasında olmalı.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$count aktif personelin isim ve kıdem snapshot’ı alınacak. Günlük 1–3 kişi dağılımını motor belirler.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Ayı oluştur'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    final snapshot = await c.prepareDifficulty(year, month);
    if (snapshot == null || !mounted) return;
    final holidays = snapshot.calendar.where((h) {
      final d = DateTime.parse(h.date);
      return d.year == year && d.month == month;
    }).toList();
    final overrides = await chooseHolidayScores(context, holidays);
    if (overrides == null || !mounted) return;
    final difficulty = DifficultySnapshot(
      settings: snapshot.settings,
      calendar: snapshot.calendar,
      overrides: overrides,
    );
    if (await c.createMonth(
          year,
          month,
          int.parse(total.text),
          difficulty: difficulty,
        ) &&
        mounted) {
      setState(() => section = 1);
    }
  }

  Widget _history() => c.months.isEmpty
      ? empty('Henüz ay yok. Nöbet Hazırla ile başlayın.')
      : ListView(
          padding: const EdgeInsets.all(AkysTokens.spaceMd),
          children: [
            for (final m in c.months)
              Padding(
                padding: const EdgeInsets.only(bottom: AkysTokens.spaceSm),
                child: AkysCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month),
                    title: Text(m.title),
                    subtitle: Text(
                      '${statusLabel(m.status)} · ${m.people.length} personel · revizyon ${m.revision}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      c.select(m.id);
                      setState(() => section = 1);
                    },
                  ),
                ),
              ),
          ],
        );
  Widget _duty() {
    final m = c.month;
    if (m == null) {
      return const SingleChildScrollView(
        child: AkysEmptyState(
          title: 'Nöbet ayı seçilmedi',
          message: 'Nöbet Hazırla ile ay oluşturun veya kayıtlı bir ay seçin.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ScheduleSegments(
          labels: const ['Liste', 'Takvim'],
          selected: dutyView,
          onChanged: (i) => setState(() => dutyView = i),
        ),
        const SizedBox(height: 12),
        if (m.duties.isNotEmpty) ...[
          if (dutyView == 0) _calendar(m) else DutyMonthGrid(month: m),
          const SizedBox(height: 16),
        ],
        ExpansionTile(
          key: const PageStorageKey('duty-tools'),
          maintainState: true,
          title: const Text('Planlama araçları'),
          subtitle: Text(statusLabel(m.status)),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _monthHeading(m),
                V13SolverPanel(
                  key: ValueKey('v13-${m.id}-${m.revision}'),
                  month: m,
                  onSave: (next) => c.save(next),
                ),
                if (m.difficultySchemaVersion == 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Eski ay: puan/tatil snapshot’ı yok. Puanlar başlangıç haftalık değerlerinden türetilir; geçmiş takvim sessizce değiştirilmez.',
                    ),
                  ),
                if (m.editable)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: c.busy ? null : () => _constraints(m),
                        icon: const Icon(Icons.event_busy),
                        label: const Text('Tutamaz / Tutacak'),
                      ),
                      OutlinedButton.icon(
                        onPressed: c.busy ? null : () => _boundary(m),
                        icon: const Icon(Icons.skip_previous),
                        label: Text(
                          m.boundarySource == 'previous_month'
                              ? 'Önceki ay sınırı · Otomatik'
                              : 'Önceki ay sınırı · Manuel',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: c.busy
                            ? null
                            : () async {
                                if (await confirm(
                                  'Ayın Gruplarını Güncelle',
                                  'Yalnızca bu taslak ayın nöbet grupları güncel personel listesinden alınacak. İsimler ve kıdem sırası korunur. Grup değişmişse mevcut nöbetler temizlenir; yeniden oluşturmanız gerekir.',
                                )) {
                                  await c.refreshMonthGroups();
                                }
                              },
                        icon: const Icon(Icons.sync),
                        label: const Text('Ayın Gruplarını Güncelle'),
                      ),
                      OutlinedButton.icon(
                        onPressed: c.busy ? null : () => _precheck(m),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Ön kontrol'),
                      ),
                      FilledButton.icon(
                        onPressed: c.busy
                            ? null
                            : () async {
                                if (m.duties.isNotEmpty &&
                                    !await confirm(
                                      'Yeniden oluştur',
                                      'Mevcut nöbetler ve manuel nöbet düzenlemeleri değiştirilecek.',
                                    )) {
                                  return;
                                }
                                await c.generate();
                              },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Listeyi Oluştur'),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  'En fazla 8 nöbet · Tarihler arası ≥3 gün · ${m.requiredDuties} toplam · ${statusLabel(m.status)}',
                ),
              ],
            ),
          ],
        ),
        if (m.duties.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Önce kişisel koşulları ve sınır nöbetlerini kontrol edin. Listeyi Oluştur ile başlayın.',
            ),
          )
        else ...[
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Canlı İstatistikler'),
            children: [
              const Text(
                'Tek: tek kişi · Eşli: en az iki kişi · Çömezli: yanında en az bir Çömez grubu hekim var.',
              ),
              _statistics(m),
            ],
          ),
        ],
      ],
    );
  }

  Widget _monthHeading(ScheduleMonth m) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(m.title, style: Theme.of(context).textTheme.headlineSmall),
        Chip(label: Text(statusLabel(m.status))),
        if (m.duties.isNotEmpty) ...[
          if (m.editable)
            FilledButton.icon(
              onPressed: c.busy
                  ? null
                  : () async {
                      if (await confirm(
                        'Kesinleştir',
                        'Hard kurallar doğrulanacak ve çizelge düzenlemeye kapatılacak. Görev uyarılarını Birleşik Görünüm’de kontrol edin.',
                      )) {
                        await c.changeStatus(MonthStatus.finalised);
                      }
                    },
              icon: const Icon(Icons.lock_outline),
              label: const Text('Kesinleştir'),
            )
          else
            OutlinedButton.icon(
              onPressed: c.busy
                  ? null
                  : () async {
                      if (await confirm(
                        'Düzenlemeye Aç',
                        'Mevcut paylaşım bağlantıları iptal edilecek. Sonraki değişiklikler yeniden kesinleştirilmelidir.',
                      )) {
                        await c.changeStatus(MonthStatus.draft);
                      }
                    },
              icon: const Icon(Icons.lock_open),
              label: const Text('Düzenlemeye Aç'),
            ),
          if (!m.editable) ...[
            OutlinedButton.icon(
              onPressed: c.busy ? null : () => _excel(m),
              icon: const Icon(Icons.download),
              label: const Text('Excel'),
            ),
            OutlinedButton.icon(
              onPressed: c.busy || m.status == MonthStatus.archived
                  ? null
                  : () => _share(m),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Paylaş'),
            ),
            if (m.status != MonthStatus.archived)
              IconButton(
                tooltip: 'Arşivle',
                onPressed: c.busy
                    ? null
                    : () async {
                        if (await confirm(
                          'Arşivle',
                          'Ay arşiv durumuna alınacak. Mevcut paylaşımlar geçerliliğini korur; isterseniz ayrıca iptal edin.',
                        )) {
                          await c.changeStatus(MonthStatus.archived);
                        }
                      },
                icon: const Icon(Icons.archive_outlined),
              ),
          ],
        ],
        if (m.shareTokens.isNotEmpty)
          OutlinedButton(
            onPressed: c.busy ? null : () => _shares(m),
            child: Text('Bağlantılar (${m.shareTokens.length})'),
          ),
      ],
    ),
  );
  Future<void> _constraints(ScheduleMonth m) async {
    if (m.duties.isNotEmpty &&
        !await confirm(
          'Koşulları düzenle',
          'Koşulları kaydetmek mevcut nöbetleri temizler. Yeniden oluşturmanız gerekir.',
        )) {
      return;
    }
    if (!mounted) return;
    final next = m.clone();
    var selected = next.people.first.personId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Kişisel Koşullar'),
          content: SizedBox(
            width: 600,
            height: 470,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  items: [
                    for (final p in next.people)
                      DropdownMenuItem(
                        value: p.personId,
                        child: Text('K${p.seniorityRank} · ${p.displayName}'),
                      ),
                  ],
                  onChanged: (id) => update(() => selected = id!),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Güne dokunun: Serbest → Tutamaz → Tutacak → Serbest',
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 100,
                          mainAxisExtent: 76,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: next.days,
                    itemBuilder: (context, index) {
                      final d = index + 1;
                      final constraint = next.constraints[selected]!;
                      final cannot = constraint.cannot.contains(d),
                          must = constraint.must.contains(d);
                      return OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: cannot
                              ? AkysColors.forbidden.withValues(alpha: 0.12)
                              : must
                              ? AkysColors.fixed.withValues(alpha: 0.12)
                              : AkysColors.weekdays[next.date(d).weekday - 1],
                        ),
                        onPressed: () => update(() {
                          if (cannot) {
                            constraint.cannot.remove(d);
                            constraint.must.add(d);
                          } else if (must) {
                            constraint.must.remove(d);
                          } else {
                            constraint.cannot.add(d);
                          }
                        }),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$d ${dayNames[next.date(d).weekday - 1].substring(0, 3)}',
                            ),
                            Text(
                              cannot
                                  ? '⊗ Tutamaz'
                                  : must
                                  ? '✓ Tutacak'
                                  : 'Serbest',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Koşulları kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      next.duties.clear();
      next.manuallyEdited.clear();
      await c.save(next);
    }
  }

  Future<void> _boundary(ScheduleMonth m) async {
    if (m.duties.isNotEmpty &&
        !await confirm(
          'Sınır nöbetlerini değiştir',
          'Kaydetmek mevcut nöbetleri temizler ve yeniden oluşturma gerektirir.',
        )) {
      return;
    }
    if (!mounted) return;
    final next = m.clone();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Önceki Ay Sınır Nöbetleri'),
          content: SizedBox(
            width: 540,
            height: 400,
            child: ListView(
              children: [
                Text(
                  m.boundarySource == 'previous_month'
                      ? 'Önceki kayıtlı aydan alındı. Değiştirirseniz kaynak manuel olur.'
                      : 'Önceki ay kayıtlı değil. Son nöbet tarihlerini girin; nöbet yoksa boş bırakın.',
                ),
                for (final p in next.people)
                  ListTile(
                    title: Text(p.displayName),
                    subtitle: Text(
                      (next.boundary[p.personId] ?? []).isEmpty
                          ? 'Önceki ay nöbeti yok'
                          : (next.boundary[p.personId]!..sort()).last,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Son nöbet tarihi',
                          icon: const Icon(Icons.edit_calendar),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: m
                                  .date(1)
                                  .subtract(const Duration(days: 1)),
                              firstDate: DateTime.utc(m.year, m.month - 1, 1),
                              lastDate: m
                                  .date(1)
                                  .subtract(const Duration(days: 1)),
                            );
                            if (date != null) {
                              update(() {
                                next.boundary[p.personId] = [dateKey(date)];
                                next.boundarySource = 'manual';
                              });
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Önceki ay nöbeti yok',
                          onPressed: () => update(() {
                            next.boundary.remove(p.personId);
                            next.boundarySource = 'manual';
                          }),
                          icon: const Icon(Icons.clear),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Doğrula ve kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      next.boundaryConfirmed = true;
      next.duties.clear();
      next.manuallyEdited.clear();
      await c.save(next);
    }
  }

  Future<void> _precheck(ScheduleMonth m) async {
    final check = m.clone()..duties.clear();
    for (final p in check.people) {
      for (final d in check.constraints[p.personId]?.must ?? <int>{}) {
        check.duties.putIfAbsent(d, () => []).add(p.personId);
      }
    }
    final errors = validateDuties(check, complete: false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          errors.isEmpty ? 'Ön Kontrol Başarılı' : 'Koşul Çakışmaları',
        ),
        content: SingleChildScrollView(
          child: Text(
            errors.isEmpty
                ? 'Sabit koşullarda doğrudan çelişki yok. Tam çözüm uygunluğu motor çalıştığında doğrulanır.'
                : errors.join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Widget _calendar(ScheduleMonth m) {
    final roleIssues = m.dutyPositions == null
        ? null
        : const ConstraintValidator().validate(m, m.dutyPositions!);
    final legacyErrors = m.dutyPositions == null
        ? _hardWarnings(m)
        : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (legacyErrors.isNotEmpty)
          ExpansionTile(
            title: AkysStatusChip(
              label: '${legacyErrors.length} zorunlu kural hatası',
              status: AkysStatus.error,
            ),
            children: [for (final e in legacyErrors) Text(e)],
          ),
        AkysResponsiveTiles(
          minimumWidth: 280,
          gap: 6,
          maxColumns: 3,
          children: [
            for (var d = 1; d <= m.days; d++)
              DragTarget<_DutyDrag>(
                onWillAcceptWithDetails: (details) =>
                    m.dutyPositions == null &&
                    m.editable &&
                    !c.busy &&
                    details.data.day != d,
                onAcceptWithDetails: (details) =>
                    _moveDialog(m, details.data.day, details.data.id, to: d),
                builder: (context, candidates, rejected) => CompactDutyCard(
                  month: m,
                  day: d,
                  position: m.dutyPositions
                      ?.where((r) => r.date == dateKey(m.date(d)))
                      .firstOrNull,
                  positionsKnown: m.dutyPositions != null,
                  errors: [
                    for (final e in roleIssues ?? [])
                      if (e.date == dateKey(m.date(d)) || e.date == null)
                        e.message,
                  ],
                  warnings: [
                    if (m.dutyPositions == null &&
                        compositionWarning(m, d) != null)
                      compositionWarning(m, d)!,
                    if (m.manuallyEdited.contains(d)) 'Manuel düzenlendi',
                  ],
                  actions: [
                    if (m.dutyPositions != null && m.editable)
                      const Text(
                        'Pozisyon düzenleme için V1.3 önizleme panelini kullanın.',
                      ),
                    if (m.dutyPositions == null)
                      for (final id in m.duties[d] ?? <String>[])
                        m.editable
                            ? LongPressDraggable<_DutyDrag>(
                                data: _DutyDrag(d, id),
                                feedback: Material(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(m.person(id).displayName),
                                  ),
                                ),
                                child: TextButton.icon(
                                  onPressed: c.busy
                                      ? null
                                      : () => _moveDialog(m, d, id),
                                  icon: const Icon(Icons.edit),
                                  label: Text(
                                    '${m.person(id).displayName} · Taşı / Değiştir',
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _moveDialog(
    ScheduleMonth m,
    int from,
    String id, {
    int? to,
  }) async {
    var target = to ?? (from % m.days + 1);
    String? swap;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Nöbet Taşı / Değiştir'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${m.person(id).displayName} · $from. gün'),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: target,
                  decoration: const InputDecoration(labelText: 'Hedef gün'),
                  items: [
                    for (var d = 1; d <= m.days; d++)
                      if (d != from)
                        DropdownMenuItem(
                          value: d,
                          child: Text('$d ${dayNames[m.date(d).weekday - 1]}'),
                        ),
                  ],
                  onChanged: (v) => update(() {
                    target = v!;
                    swap = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(target),
                  initialValue: swap,
                  decoration: const InputDecoration(
                    labelText: 'Değişim (isteğe bağlı)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Yalnızca taşı'),
                    ),
                    for (final p in m.duties[target] ?? <String>[])
                      if (p != id)
                        DropdownMenuItem(
                          value: p,
                          child: Text(m.person(p).displayName),
                        ),
                  ],
                  onChanged: (v) => update(() => swap = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hard kurallar bozulursa işlem engellenir; adalet puanı kötüleşirse uyarı gösterilir.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await c.move(from, target, id, swap: swap);
  }

  Widget _statistics(ScheduleMonth m) {
    final stats = statistics(m);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final label in [
            'Personel',
            'Nöbet Grubu',
            'Toplam',
            'Tek',
            'Eşli',
            'Çömezli',
            'Resmî Tatil',
            'Zorluk Puanı',
            'Pzt/Sal/Çar',
            'Perşembe',
            'Cuma',
            'Cumartesi',
            'Pazar',
          ])
            DataColumn(label: Text(label)),
        ],
        rows: [
          for (final p in m.people)
            DataRow(
              cells: [
                DataCell(personChip(p)),
                DataCell(Text(dutyGroupLabel(p.dutySeniorityGroup))),
                DataCell(Text('${stats[p.personId]!.total}')),
                DataCell(Text('${stats[p.personId]!.solo}')),
                DataCell(Text('${stats[p.personId]!.paired}')),
                DataCell(Text('${stats[p.personId]!.withJunior}')),
                DataCell(
                  Text(
                    m.difficultySchemaVersion == 0
                        ? 'Bilinmiyor'
                        : '${stats[p.personId]!.holidayDuties}',
                  ),
                ),
                DataCell(Text('${stats[p.personId]!.totalDifficulty}')),
                for (final n in stats[p.personId]!.categories)
                  DataCell(Text('$n')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tasks() {
    final m = c.month;
    if (m == null) return empty('Önce ay seçin.');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _dailyTaskPreview(m),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Aylık görev ayarları'),
          maintainState: true,
          children: [
            _monthHeading(m),
            const Text(
              'Aylık asıl ve yedekleri seçin. Asıl nöbet ertesi ise yedek görevi devralır. İkisi de uygun değilse görev karşılanamaz; otomatik üçüncü kişi atanmaz.',
            ),
            const SizedBox(height: 16),
            if (m.taskWorkdaySchemaVersion == 0) ...[
              const Text('Eski ay: mevcut görev davranışı korunuyor.'),
              if (m.editable)
                OutlinedButton(
                  onPressed: c.busy
                      ? null
                      : () async {
                          if (await confirm(
                            'Resmî iş günü kuralını uygula',
                            'Bu taslak ayın hafta sonu ve tam tatil görevleri pasif, yarım tatil görevleri 13.00 öncesi olacaktır. Nöbetler ve puanlar değişmez. Devam edilsin mi?',
                          )) {
                            await c.applyTaskWorkdays();
                          }
                        },
                  child: const Text(
                    'Görevleri Resmî İş Günlerine Göre Yeniden Hesapla',
                  ),
                ),
            ] else
              const Text(
                'Görevler yalnız resmî iş günlerinde; yarım tatillerde 13.00 öncesinde geçerlidir.',
              ),
            AkysResponsiveTiles(
              minimumWidth: 280,
              maxColumns: 3,
              children: [
                for (final task in ClinicTask.values)
                  AkysCard(
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.assignment, color: AkysTokens.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  taskLabel(task),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Asıl: ${_taskName(m, m.tasks[task]?.primary)}\nYedek: ${_taskName(m, m.tasks[task]?.backup)}',
                          ),
                          if (m.editable)
                            TextButton.icon(
                              onPressed: c.busy
                                  ? null
                                  : () => _editTask(m, task),
                              icon: const Icon(Icons.edit),
                              label: const Text('Asıl / Yedek Seç'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Günlük Sonuçlar ve Manuel Override'),
          children: [_combinedRows(m)],
        ),
      ],
    );
  }

  Widget _dailyTaskPreview(ScheduleMonth m) {
    final day = taskDay.clamp(1, m.days);
    final tasks = dailyTasks(m, day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 76 * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: m.days,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => SizedBox(
              width: 64 * MediaQuery.textScalerOf(context).scale(1),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: day == i + 1
                      ? AkysTokens.primary
                      : Colors.white,
                  foregroundColor: day == i + 1
                      ? Colors.white
                      : AkysTokens.navy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AkysTokens.softBorder),
                  ),
                ),
                onPressed: () => setState(() => taskDay = i + 1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${i + 1}'.padLeft(2, '0'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      shortWeekdays[m.date(i + 1).weekday - 1],
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AkysCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.nightlight_round, color: AkysTokens.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$day ${monthNames[m.month - 1]} ${m.year} · ${dayNames[m.date(day).weekday - 1]}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Nöbet: ${(m.duties[day] ?? []).map((id) => m.person(id).displayName).join(', ')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AkysCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final task in tasks)
                ExpansionTile(
                  dense: true,
                  minTileHeight: 48,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.all(12),
                  leading: Icon(
                    Icons.assignment,
                    size: 22,
                    color: AkysColors.task(task.task),
                  ),
                  title: Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        taskLabel(task.task),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        !task.active
                            ? '— (Kapalı)'
                            : '${task.personId == null ? 'Görev karşılanamıyor' : m.person(task.personId!).displayName}${task.halfDay ? ' · 13.00 öncesi' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  children: [
                    Text(task.workPeriodLabel),
                    if (task.active) ...[
                      Text(
                        'Asıl: ${_taskName(m, m.tasks[task.task]?.primary)} · Yedek: ${_taskName(m, m.tasks[task.task]?.backup)}',
                      ),
                      for (final w in task.warnings)
                        AkysStatusChip(label: w, status: AkysStatus.warning),
                      if (m.editable)
                        TextButton(
                          onPressed: c.busy
                              ? null
                              : () => _override(m, day, task.task),
                          child: const Text('Görevi düzenle'),
                        ),
                    ],
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AkysStatusChip(
          label: m.taskWorkdaySchemaVersion == 0
              ? 'Eski ay: mevcut görev davranışı korunuyor.'
              : 'Hafta sonu ve tam resmî tatillerde klinik görevler pasiftir. Yarım tatillerde 13.00 öncesi geçerlidir.',
          status: AkysStatus.info,
        ),
      ],
    );
  }

  String _taskName(ScheduleMonth m, String? id) =>
      id == null ? 'Seçilmedi' : m.person(id).displayName;
  Future<void> _editTask(ScheduleMonth m, ClinicTask task) async {
    String? primary = m.tasks[task]?.primary, backup = m.tasks[task]?.backup;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: Text(taskLabel(task)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _personDropdown(
                  m,
                  'Asıl',
                  primary,
                  (id) => update(() => primary = id),
                ),
                const SizedBox(height: 12),
                _personDropdown(
                  m,
                  'Yedek',
                  backup,
                  (id) => update(() => backup = id),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: AkysColors.forbidden),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (primary == null || backup == null || primary == backup) {
                  update(() => error = 'Farklı iki personel seçin.');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final next = m.clone();
      next.tasks[task] = TaskAssignment(primary!, backup!);
      await c.save(next);
    }
  }

  Widget _personDropdown(
    ScheduleMonth m,
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    itemHeight: null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final p in m.people)
        DropdownMenuItem(
          value: p.personId,
          child: Text('K${p.seniorityRank} ${p.displayName}'),
        ),
    ],
    onChanged: onChanged,
  );
  Widget _combined() {
    final m = c.month;
    if (m == null) return empty('Önce ay seçin.');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _monthHeading(m),
        const Text(
          'Nöbet değiştiğinde görevler otomatik yeniden hesaplanır. ⚠ işaretli görevlerde çakışma veya karşılanamayan görev vardır.',
        ),
        const SizedBox(height: 12),
        _combinedRows(m),
      ],
    );
  }

  Widget _combinedRows(ScheduleMonth m) => CombinedDayCards(
    month: m,
    hardErrors: _hardWarnings(m),
    onEdit: m.editable && !c.busy
        ? (day, task) => _override(m, day, task)
        : null,
  );
  Future<void> _override(ScheduleMonth m, int day, ClinicTask task) async {
    final key = '${dateKey(m.date(day))}|${task.name}';
    String? person = m.overrides[key]?.personId;
    final reason = TextEditingController(text: m.overrides[key]?.reason ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: Text('$day. gün · ${taskLabel(task)}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _personDropdown(
                  m,
                  'Manuel görevli',
                  person,
                  (id) => update(() => person = id),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Gerekçe (isteğe bağlı)',
                  ),
                ),
                const Text(
                  'Manuel atama nöbet ertesi ve görev çakışmalarını uyarı olarak gösterir.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            if (m.overrides.containsKey(key))
              TextButton(
                onPressed: () => Navigator.pop(context, 'remove'),
                child: const Text('Otomatiğe dön'),
              ),
            FilledButton(
              onPressed: person == null
                  ? null
                  : () => Navigator.pop(context, 'save'),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      final next = m.clone();
      if (result == 'remove') {
        next.overrides.remove(key);
      } else {
        next.overrides[key] = TaskOverride(
          dateKey(m.date(day)),
          task,
          person!,
          reason: reason.text.trim(),
        );
      }
      await c.save(next);
    }
  }

  Future<void> _excel(ScheduleMonth m) async {
    try {
      final box = context.findRenderObject() as RenderBox;
      await exportFile(
        exportExcel(m),
        'AKYS-${m.id}.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      c.error =
          'Excel dosyası hazırlanamadı veya paylaşım penceresi açılamadı.';
      c.emit();
    }
  }

  String _shareUrl(String token) => kIsWeb
      ? Uri.base
            .replace(path: '/shared/schedule/$token', fragment: '', query: '')
            .toString()
      : 'https://akys-d708a.web.app/shared/schedule/$token';

  Future<void> _share(ScheduleMonth m) async {
    if (!await confirm(
      'Salt okunur paylaşım oluştur',
      'Bağlantıya sahip kişiler isimleri, nöbetleri ve görevleri görebilir. Koşullar, özel personel kayıtları ve yönetim paneli paylaşılmaz. Bağlantı bir yıl geçerlidir ve iptal edilebilir.',
    )) {
      return;
    }
    final token = await c.share();
    if (token != null && mounted) await _linkDialog(token);
  }

  Future<void> _linkDialog(String token) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Paylaşım Bağlantısı'),
      content: SelectableText(_shareUrl(token)),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _shareUrl(token)));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Bağlantıyı kopyala'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
  Future<void> _shares(ScheduleMonth m) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Paylaşım Bağlantıları'),
      content: SizedBox(
        width: 500,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final token in m.shareTokens)
              ListTile(
                title: Text('${token.substring(0, 8)}…'),
                onTap: () => _linkDialog(token),
                trailing: TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    if (await confirm(
                      'Bağlantıyı iptal et',
                      'Bu bağlantı artık çizelgeyi açamayacak.',
                    )) {
                      await c.revoke(token);
                    }
                  },
                  child: const Text('İptal et'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
}

class _DutyDrag {
  const _DutyDrag(this.day, this.id);
  final int day;
  final String id;
}

Widget rankBadge(int rank) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
  decoration: BoxDecoration(
    color: AkysColors.rank(rank),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    'K$rank',
    style: TextStyle(
      color: [1, 6, 7].contains(rank) ? AkysTokens.navy : Colors.white,
      fontWeight: FontWeight.bold,
    ),
  ),
);
Widget personChip(PersonSnapshot p) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    rankBadge(p.seniorityRank),
    const SizedBox(width: 6),
    Flexible(
      child: Text(
        p.displayName,
        style: const TextStyle(fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
);
