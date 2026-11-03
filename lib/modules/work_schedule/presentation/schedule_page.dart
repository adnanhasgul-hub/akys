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
import '../engine/task_engine.dart';

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
      final wide = MediaQuery.sizeOf(context).width >= 1000;
      final body = Column(
        children: [
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) _message(c.error!, true),
          if (c.notice != null) _message(c.notice!, false),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  sections[section],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('${c.selectedId}-${c.months.length}'),
                    initialValue: c.months.any((m) => m.id == c.selectedId)
                        ? c.selectedId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Çalışılan ay',
                      isDense: true,
                    ),
                    items: [
                      for (final m in c.months)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.title} · ${statusLabel(m.status)}'),
                        ),
                    ],
                    onChanged: c.busy
                        ? null
                        : (id) {
                            if (id != null) c.select(id);
                          },
                  ),
                ),
                FilledButton.icon(
                  onPressed: c.busy ? null : _createMonth,
                  icon: const Icon(Icons.add),
                  label: const Text('Nöbet Hazırla'),
                ),
                IconButton(
                  onPressed: c.busy ? null : c.initialize,
                  tooltip: 'Yeniden yükle',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: c.loading
                ? const Center(child: CircularProgressIndicator())
                : switch (section) {
                    0 => _overview(),
                    1 => _duty(),
                    2 => _tasks(),
                    3 => _personnel(),
                    4 => _history(),
                    5 => _combined(),
                    _ => DifficultySettingsPanel(
                      key: ValueKey(c.difficultySettings.revision),
                      settings: c.difficultySettings,
                      busy: c.busy,
                      onSave: c.saveDifficulty,
                    ),
                  },
          ),
        ],
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('Çalışma Çizelgesi'),
          actions: [?widget.logout],
        ),
        body: SafeArea(
          child: wide
              ? Row(
                  children: [
                    NavigationRail(
                      extended: true,
                      selectedIndex: section,
                      onDestinationSelected: c.busy
                          ? null
                          : (i) => setState(() => section = i),
                      destinations: [
                        for (var i = 0; i < sections.length; i++)
                          NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(sections[i]),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
        ),
        bottomNavigationBar: wide
            ? null
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: ChoiceChip(
                          avatar: Icon(icons[i], size: 18),
                          label: Text(sections[i]),
                          selected: i == section,
                          onSelected: c.busy
                              ? null
                              : (_) => setState(() => section = i),
                        ),
                      ),
                  ],
                ),
              ),
      );
    },
  );
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
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
  Widget _overview() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Güvenli, dengeli ve izlenebilir planlama',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          _metric(
            'Aktif personel',
            '${c.personnel.where((p) => p.active).length}',
            Icons.groups,
          ),
          _metric('Kayıtlı ay', '${c.months.length}', Icons.calendar_month),
          _metric(
            'Kesin / Paylaşılan',
            '${c.months.where((m) => m.status == MonthStatus.finalised || m.status == MonthStatus.published).length}',
            Icons.verified_outlined,
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        '1. Personeli ve kıdem sırasını kontrol edin.\n2. Ay oluşturun; personel snapshot’ı sabitlenir.\n3. Tutamaz / Tutacak ve önceki ay nöbetlerini kaydedin.\n4. Ön kontrol ve oluşturma sonrası çizelgeyi inceleyin.\n5. Görevleri seçin, kesinleştirin; Excel ve güvenli paylaşımı kullanın.',
      ),
      const SizedBox(height: 24),
      if (c.month != null) ...[
        Text(
          '${c.month!.title} · ${statusLabel(c.month!.status)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          '${c.month!.people.length} snapshot personeli · ${c.month!.requiredDuties} aylık nöbet · Motor ${c.month!.engineVersion}',
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => setState(() => section = 1),
          child: const Text('Nöbet çizelgesini aç'),
        ),
      ],
    ],
  );
  Widget _metric(String label, String value, IconData icon) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: AkysColors.brand),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(label),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _personnel() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              '${c.personnel.where((p) => p.active).length} aktif / ${c.personnel.length} personel',
            ),
            FilledButton.icon(
              onPressed: c.busy
                  ? null
                  : () async {
                      final name = await textInput('Personel Ekle');
                      if (name != null) await c.addPerson(name);
                    },
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Personel Ekle'),
            ),
            const Text('Sıralamak için tutamacı sürükleyin. K1 en kıdemlidir.'),
          ],
        ),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: c.personnel.length,
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) async {
            if (c.busy) return;
            final after = [...c.personnel];
            after.insert(newIndex, after.removeAt(oldIndex));
            await c.updatePeople(after);
          },
          itemBuilder: (context, i) => _personCard(c.personnel[i], i),
        ),
      ),
    ],
  );
  Widget _personCard(Personnel p, int index) => Card(
    key: ValueKey(p.id),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              rankBadge(p.seniorityRank),
              const SizedBox(width: 8),
              Expanded(child: Text(p.displayName)),
              IconButton(
                tooltip: 'İsmi düzenle',
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
              ),
              ReorderableDragStartListener(
                index: index,
                enabled: !c.busy,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                                if (x.id == p.id) x.copy(active: active) else x,
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
          padding: const EdgeInsets.all(16),
          children: [
            for (final m in c.months)
              Card(
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
          ],
        );
  Widget _duty() {
    final m = c.month;
    if (m == null) {
      return empty('Nöbet Hazırla ile ay oluşturun veya kayıtlı bir ay seçin.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _monthHeading(m),
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
        if (m.duties.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Önce kişisel koşulları ve sınır nöbetlerini kontrol edin. Listeyi Oluştur ile başlayın.',
            ),
          )
        else ...[
          const SizedBox(height: 16),
          _calendar(m),
          const SizedBox(height: 24),
          Text(
            'Canlı İstatistikler',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Tek: tek kişi · Eşli: en az iki kişi · Çömezli: yanında en az bir Çömez grubu hekim var.',
          ),
          _statistics(m),
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

  Widget _calendar(ScheduleMonth m) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 7
          : constraints.maxWidth >= 550
          ? 4
          : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: columns == 1 ? 174 : 235,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: m.days,
        itemBuilder: (context, index) {
          final d = index + 1;
          return DragTarget<_DutyDrag>(
            onWillAcceptWithDetails: (details) =>
                m.editable && !c.busy && details.data.day != d,
            onAcceptWithDetails: (details) =>
                _moveDialog(m, details.data.day, details.data.id, to: d),
            builder: (context, candidates, rejected) => Card(
              color: AkysColors.weekdays[m.date(d).weekday - 1],
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: candidates.isNotEmpty
                      ? AkysColors.brand
                      : Theme.of(context).dividerColor,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$d · ${dayNames[m.date(d).weekday - 1]}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Zorluk: ${m.difficultyScore(d)}${m.isHoliday(d)
                          ? ' · ${m.difficulty.holiday(m.date(d))!.name}'
                          : m.difficulty.isPreHoliday(m.date(d))
                          ? ' · Tatil öncesi'
                          : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (compositionWarning(m, d) != null)
                      Tooltip(
                        message: compositionWarning(m, d)!,
                        child: const Text(
                          '⚠ Kıdemli + Çömez eşleşmesi yok',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    if (m.manuallyEdited.contains(d))
                      const Text(
                        '✎ Manuel düzenlendi',
                        style: TextStyle(fontSize: 11),
                      ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final id in m.duties[d] ?? <String>[])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: m.editable
                                  ? LongPressDraggable<_DutyDrag>(
                                      data: _DutyDrag(d, id),
                                      feedback: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(m.person(id).displayName),
                                        ),
                                      ),
                                      child: InkWell(
                                        onTap: c.busy
                                            ? null
                                            : () => _moveDialog(m, d, id),
                                        child: personChip(m.person(id)),
                                      ),
                                    )
                                  : personChip(m.person(id)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
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
        _monthHeading(m),
        const Text(
          'Aylık asıl ve yedekleri seçin. Asıl nöbet ertesi ise yedek görevi devralır. İkisi de uygun değilse görev karşılanamaz; otomatik üçüncü kişi atanmaz.',
        ),
        const SizedBox(height: 16),
        for (final task in ClinicTask.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.assignment, color: AkysColors.task(task)),
                      const SizedBox(width: 8),
                      Text(
                        taskLabel(task),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Asıl: ${_taskName(m, m.tasks[task]?.primary)}\nYedek: ${_taskName(m, m.tasks[task]?.backup)}',
                  ),
                  if (m.editable)
                    TextButton.icon(
                      onPressed: c.busy ? null : () => _editTask(m, task),
                      icon: const Icon(Icons.edit),
                      label: const Text('Asıl / Yedek Seç'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Günlük Sonuçlar ve Manuel Override',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        _combinedRows(m),
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

  Widget _combinedRows(ScheduleMonth m) => LayoutBuilder(
    builder: (context, constraints) {
      Widget taskCell(int day, DailyTask task) => InkWell(
        onTap: m.editable && !c.busy
            ? () => _override(m, day, task.task)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${task.personId == null ? 'Görev karşılanamıyor' : m.person(task.personId!).displayName}${task.backup ? ' (Yedek)' : ''}${task.manual ? ' (Manuel)' : ''}${task.warnings.isEmpty ? '' : '\n⚠ ${task.warnings.join(' ')}'}',
            style: TextStyle(
              color: task.warnings.isEmpty ? null : AkysColors.forbidden,
            ),
          ),
        ),
      );
      if (constraints.maxWidth >= 900) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMinHeight: 64,
            dataRowMaxHeight: 150,
            columns: [
              const DataColumn(label: Text('Tarih / Gün')),
              const DataColumn(label: Text('Nöbetçiler')),
              for (final t in ClinicTask.values)
                DataColumn(label: Text(taskLabel(t))),
            ],
            rows: [
              for (var d = 1; d <= m.days; d++)
                DataRow(
                  color: WidgetStatePropertyAll(
                    AkysColors.weekdays[m.date(d).weekday - 1],
                  ),
                  cells: [
                    DataCell(Text('$d ${dayNames[m.date(d).weekday - 1]}')),
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          (m.duties[d] ?? [])
                              .map((id) => m.person(id).displayName)
                              .join('\n'),
                        ),
                      ),
                    ),
                    for (final task in dailyTasks(m, d))
                      DataCell(SizedBox(width: 190, child: taskCell(d, task))),
                  ],
                ),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (var d = 1; d <= m.days; d++)
            Card(
              color: AkysColors.weekdays[m.date(d).weekday - 1],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$d ${dayNames[m.date(d).weekday - 1]}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Nöbet: ${(m.duties[d] ?? []).map((id) => m.person(id).displayName).join(', ')}',
                    ),
                    for (final task in dailyTasks(m, d))
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 105,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                taskLabel(task.task),
                                style: TextStyle(
                                  color: AkysColors.task(task.task),
                                ),
                              ),
                            ),
                          ),
                          Expanded(child: taskCell(d, task)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  Future<void> _override(ScheduleMonth m, int day, ClinicTask task) async {
    final key = '${dateKey(m.date(day))}|${task.name}';
    String? person = m.overrides[key]?.personId;
    final reason = TextEditingController(text: m.overrides[key]?.reason ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
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
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
