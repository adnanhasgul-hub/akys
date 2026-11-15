import 'package:flutter/material.dart';

import '../../core/design/clinical_teal_theme.dart';
import '../../solver_v2/solver.dart';
import '../../solver_v2/clinical_quality.dart';
import '../../solver_v2/runtime/lifecycle.dart';
import 'workspace.dart';

class V2SchedulePage extends StatefulWidget {
  const V2SchedulePage({super.key, this.workspace});
  final ScheduleWorkspace? workspace;
  @override
  State<V2SchedulePage> createState() => _V2SchedulePageState();
}

class _V2SchedulePageState extends State<V2SchedulePage> {
  late final ScheduleWorkspace w = widget.workspace ?? ScheduleWorkspace();
  int tab = 0;
  int nextId = 0;
  final weekdays = const [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  @override
  void initState() {
    super.initState();
    w.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    w.removeListener(refresh);
    if (widget.workspace == null) w.dispose();
    super.dispose();
  }

  String date(int day) {
    final d = w.problem.dateForDay(day);
    return '${d.day}.${d.month}.${d.year} • ${weekdays[d.weekday - 1]}';
  }

  String slotName(int slot) =>
      '${date(w.problem.slotDays[slot])} / ${w.problem.slotRoles![slot] == DutyRole.senior ? 'Kıdemli' : 'Kıdemsiz'} #${slot + 1}';
  Future<bool> confirmReset() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Taslağı yeniden oluştur'),
          content: const Text(
            'Yapılandırma değişince atamalar, kilitler ve geri alma geçmişi temizlenir. Ay değişiminde tarih kısıtları, önceki nöbetler, tatiller ve günlük pozisyon ayarları da sıfırlanır. Devam edilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Yeni taslak'),
            ),
          ],
        ),
      ) ??
      false;
  void message(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> replace(Problem p) async {
    if (await confirmReset()) {
      try {
        w.replace(p);
      } catch (e) {
        message(e);
      }
    }
  }

  Problem copy({
    List<Doctor>? doctors,
    List<int>? counts,
    List<DutyRole>? roles,
    List<SlotRequirement>? requirements,
    List<DayDifficulty>? difficulties,
  }) => Problem(
    doctors: doctors ?? w.problem.doctors,
    clinicMaxDuties: w.problem.clinicMaxDuties,
    startDate: w.problem.startDate,
    slotsPerDay: counts ?? w.problem.slotsPerDay,
    slotRoles: roles ?? w.problem.slotRoles,
    slotRequirements: requirements ?? w.problem.slotRequirements,
    dayDifficulties: difficulties ?? w.problem.dayDifficulties,
  );
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AKYS V2 • Nöbet Çizelgesi')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const Key('month'),
                    onPressed: w.pending ? null : chooseMonth,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      '${w.problem.startDate!.month} / ${w.problem.startDate!.year}',
                    ),
                  ),
                  IconButton.filled(
                    key: const Key('start'),
                    tooltip: 'Nöbet oluştur',
                    onPressed: w.pending
                        ? null
                        : () {
                            setState(() => tab = 2);
                            w.start();
                          },
                    icon: const Icon(Icons.auto_awesome),
                  ),
                  IconButton.outlined(
                    key: const Key('reoptimize'),
                    tooltip: 'Kilitlerle yeniden optimize et',
                    onPressed: w.pending
                        ? null
                        : () {
                            setState(() => tab = 2);
                            w.start(reoptimize: true);
                          },
                    icon: const Icon(Icons.lock_reset),
                  ),
                  IconButton(
                    tooltip: 'Yerel çalışma alanı hakkında',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Yerel çalışma alanı'),
                        content: const Text(
                          'Kalıcı kayıt ve yayın yoktur. Uygulama kapanırsa taslak kaybolabilir. Web üzerinde Worker, Android üzerinde isolate kullanılır.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('Kapat'),
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
            ),
            if (w.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  w.error!,
                  style: const TextStyle(color: AkysTokens.error),
                ),
              ),
            Expanded(
              child: switch (tab) {
                0 => schedule(),
                1 => doctors(),
                _ => quality(),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_view_month),
            label: 'Çizelge',
          ),
          NavigationDestination(icon: Icon(Icons.people), label: 'Hekimler'),
          NavigationDestination(
            icon: Icon(Icons.insights),
            label: 'Kalite / Arama',
          ),
        ],
      ),
    );
  }

  Future<void> chooseMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: w.problem.startDate!,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    // Date-relative constraints cannot silently migrate to a different month.
    final empty = ScheduleWorkspace.emptyMonth(picked.year, picked.month);
    await replace(
      Problem(
        doctors: [
          for (final d in w.problem.doctors)
            Doctor(
              id: d.id,
              maxDuties: d.maxDuties,
              group: d.group,
              seniorityRank: d.seniorityRank,
              seniorityLevel: d.seniorityLevel,
              eligibleRoles: d.eligibleRoles,
            ),
        ],
        clinicMaxDuties: w.problem.clinicMaxDuties,
        startDate: empty.startDate,
        slotsPerDay: empty.slotsPerDay,
        slotRoles: empty.slotRoles,
        slotRequirements: empty.slotRequirements,
        dayDifficulties: empty.dayDifficulties,
      ),
    );
  }

  Widget schedule() {
    final state = w.editor.current;
    return ListView(
      key: PageStorageKey('v2-tab-$tab'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            Text(
              state.canApprove
                  ? 'Geçerli taslak • Optimumluk iddiası yok'
                  : 'Eksik veya geçersiz taslak',
            ),
            IconButton(
              tooltip: 'Geri al',
              key: const Key('undo'),
              onPressed: w.pending || !w.editor.canUndo
                  ? null
                  : () => w.edit((e) => e.undo()),
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Yinele',
              key: const Key('redo'),
              onPressed: w.pending || !w.editor.canRedo
                  ? null
                  : () => w.edit((e) => e.redo()),
              icon: const Icon(Icons.redo),
            ),
          ],
        ),
        if (state.issues.isNotEmpty)
          ExpansionTile(
            title: Text('${state.issues.length} doğrulama bildirimi'),
            children: [
              for (final i in state.issues)
                ListTile(
                  leading: Icon(
                    i.isIncomplete ? Icons.info_outline : Icons.error_outline,
                  ),
                  title: Text(i.message),
                  subtitle: Text(
                    '${i.personId ?? ''} ${i.date?.toIso8601String().split('T').first ?? ''}',
                  ),
                ),
            ],
          ),
        if (MediaQuery.sizeOf(context).width >= AkysTokens.desktop)
          Table(
            columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(3)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(color: AkysTokens.softBorder),
            children: [
              const TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Tarih / Gün'),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Nöbet pozisyonları • Uzun basıp taşıyın veya düzenleme menüsünü açın',
                    ),
                  ),
                ],
              ),
              for (var day = 0; day < w.problem.slotsPerDay.length; day++)
                TableRow(
                  decoration: BoxDecoration(
                    color: w.problem.dateForDay(day).weekday >= 6
                        ? AkysTokens.selected
                        : AkysTokens.surface,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(date(day)),
                    ),
                    dayCard(day),
                  ],
                ),
            ],
          )
        else
          for (var day = 0; day < w.problem.slotsPerDay.length; day++)
            dayCard(day),
      ],
    );
  }

  Widget dayCard(int day) {
    final p = w.problem;
    final slots = [
      for (var s = 0; s < p.slotDays.length; s++)
        if (p.slotDays[s] == day) s,
    ];
    final filled = slots
        .where((s) => w.editor.current.assignments[s] >= 0)
        .length;
    return Card(
      color: p.dateForDay(day).weekday >= 6
          ? AkysTokens.selected
          : AkysTokens.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(date(day), style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '$filled / ${slots.length} hekim • Z: ${p.dayDifficulties![day].effectiveScore}',
                ),
                IconButton(
                  tooltip: 'Gün pozisyonları ve tatil',
                  onPressed: w.pending ? null : () => configureDay(day),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            if (p.dayDifficulties![day].holidayName != null)
              Text('⚑ Manuel tatil: ${p.dayDifficulties![day].holidayName}'),
            LayoutBuilder(
              builder: (c, b) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in slots)
                    SizedBox(
                      width: b.maxWidth > 800
                          ? (b.maxWidth - 16) / 3
                          : b.maxWidth,
                      child: slot(s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget slot(int s) {
    final state = w.editor.current;
    final d = state.assignments[s];
    final locked = state.locks.containsKey(s);
    final required = w.problem.slotRequirements[s] == SlotRequirement.required;
    final child = OutlinedButton(
      key: Key('slot-$s'),
      onPressed: w.pending ? null : () => editSlot(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${w.problem.slotRoles![s] == DutyRole.senior ? 'Kıdemli' : 'Kıdemsiz'} • ${required ? 'REQUIRED / Zorunlu' : 'OPTIONAL / İsteğe bağlı'}',
            ),
            Text(
              '${locked ? '🔒 ' : ''}${w.name(d)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (d >= 0)
              Text(
                '${w.problem.doctors[d].group == DutyGroup.senior ? 'Kıdemli' : 'Kıdemsiz'} • Sıra ${w.problem.doctors[d].seniorityRank} ${w.problem.doctors[d].seniorityLevel?.name.toUpperCase() ?? ''}',
              ),
            if (d < 0)
              Text(required ? 'Zorunlu pozisyon eksik' : 'Boş bırakılabilir'),
          ],
        ),
      ),
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (x) => !w.pending && x.data != s,
      onAcceptWithDetails: (x) =>
          w.edit((e) => d < 0 ? e.move(x.data, s) : e.swap(x.data, s)),
      builder: (c, a, r) => LongPressDraggable<int>(
        data: s,
        maxSimultaneousDrags: w.pending || locked || d < 0 ? 0 : 1,
        feedback: Material(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(w.name(d)),
          ),
        ),
        child: child,
      ),
    );
  }

  Future<void> editSlot(int s) async {
    final action = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(slotName(s)),
        children: [
          for (final a in [
            'Ata',
            'Kaldır',
            'Taşı',
            'Takas',
            w.editor.current.locks.containsKey(s) ? 'Kilidi kaldır' : 'Kilitle',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, a),
              child: Text(a),
            ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'Kaldır') {
      w.edit((e) => e.remove(s));
      return;
    }
    if (action == 'Kilitle') {
      w.edit((e) => e.lock(s));
      return;
    }
    if (action == 'Kilidi kaldır') {
      w.edit((e) => e.unlock(s));
      return;
    }
    if (action == 'Ata') {
      final d = await showDialog<int>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Hekim seç'),
          children: [
            for (var i = 0; i < w.problem.doctors.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, i),
                child: Text(w.name(i)),
              ),
          ],
        ),
      );
      if (d != null) w.edit((e) => e.assign(s, d));
    } else {
      final to = await showDialog<int>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text('$action • Hedef pozisyon'),
          children: [
            for (var i = 0; i < w.problem.slotDays.length; i++)
              if (i != s)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, i),
                  child: Text(
                    '${slotName(i)}: ${w.name(w.editor.current.assignments[i])}',
                  ),
                ),
          ],
        ),
      );
      if (to != null) {
        w.edit((e) => action == 'Taşı' ? e.move(s, to) : e.swap(s, to));
      }
    }
  }

  Widget doctors() => ListView(
    key: const PageStorageKey('v2-doctors'),
    padding: const EdgeInsets.all(16),
    children: [
      FilledButton.icon(
        key: const Key('add-doctor'),
        onPressed: w.pending ? null : () => doctorForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Hekim ekle'),
      ),
      if (w.problem.doctors.isEmpty)
        const ListTile(
          title: Text('Henüz hekim yok. Önce klinik personelini ekleyin.'),
        ),
      for (var i = 0; i < w.problem.doctors.length; i++)
        Card(
          child: ListTile(
            title: Text(w.name(i)),
            subtitle: Text(
              '${w.problem.doctors[i].group == DutyGroup.senior ? 'Kıdemli' : 'Kıdemsiz'} • Sıra ${w.problem.doctors[i].seniorityRank} • Üst sınır ${w.problem.doctors[i].maxDuties}',
            ),
            trailing: IconButton(
              tooltip: 'Hekim düzenle',
              onPressed: w.pending ? null : () => doctorForm(i),
              icon: const Icon(Icons.edit),
            ),
          ),
        ),
    ],
  );
  Future<void> chooseDays(TextEditingController controller) async {
    final selected = {
      for (final text in controller.text.split(','))
        if (int.tryParse(text.trim()) != null) int.parse(text.trim()),
    };
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Günleri seç'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var day = 1; day <= w.problem.slotsPerDay.length; day++)
                    FilterChip(
                      label: Text('$day'),
                      selected: selected.contains(day),
                      onSelected: (value) => set(
                        () => value ? selected.add(day) : selected.remove(day),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Günleri uygula'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final days = selected.toList()..sort();
      controller.text = days.join(',');
    }
  }

  Future<void> doctorForm([int? index]) async {
    final old = index == null ? null : w.problem.doctors[index];
    final name = TextEditingController(
      text: index == null ? '' : w.name(index),
    );
    final rank = TextEditingController(
      text: '${old?.seniorityRank ?? w.problem.doctors.length + 1}',
    );
    final cap = TextEditingController(
      text: '${old?.maxDuties ?? w.problem.clinicMaxDuties}',
    );
    final must = TextEditingController(
      text: old?.must.map((d) => d + 1).join(',') ?? '',
    );
    final cannot = TextEditingController(
      text: old?.unavailable.map((d) => d + 1).join(',') ?? '',
    );
    final previous = TextEditingController(
      text:
          old?.previousDuties
              .map((d) => d.toIso8601String().split('T').first)
              .join(',') ??
          '',
    );
    var group = old?.group ?? DutyGroup.senior;
    var level = old?.seniorityLevel ?? SeniorityLevel.k1;
    final roles = {...old?.eligibleRoles ?? DutyRole.values};
    String? error;
    Doctor? result;
    bool remove = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(old == null ? 'Yeni hekim' : 'Hekim ve kısıtlar'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Ad soyad'),
                  ),
                  DropdownButtonFormField<DutyGroup>(
                    initialValue: group,
                    decoration: const InputDecoration(labelText: 'Grup'),
                    items: [
                      for (final g in DutyGroup.values)
                        DropdownMenuItem(
                          value: g,
                          child: Text(
                            g == DutyGroup.senior ? 'Kıdemli' : 'Kıdemsiz',
                          ),
                        ),
                    ],
                    onChanged: (v) => set(() => group = v!),
                  ),
                  if (group == DutyGroup.senior)
                    DropdownButtonFormField<SeniorityLevel>(
                      initialValue: level,
                      decoration: const InputDecoration(
                        labelText: 'Kıdem seviyesi',
                      ),
                      items: [
                        for (final l in SeniorityLevel.values)
                          DropdownMenuItem(
                            value: l,
                            child: Text(l.name.toUpperCase()),
                          ),
                      ],
                      onChanged: (v) => set(() => level = v!),
                    ),
                  TextField(
                    controller: rank,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Genel kıdem sırası',
                    ),
                  ),
                  TextField(
                    controller: cap,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Aylık üst sınır (0–8)',
                    ),
                  ),
                  for (final role in DutyRole.values)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${role == DutyRole.senior ? 'Kıdemli' : 'Kıdemsiz'} pozisyon yetkinliği',
                      ),
                      value: roles.contains(role),
                      onChanged: (v) =>
                          set(() => v! ? roles.add(role) : roles.remove(role)),
                    ),
                  TextField(
                    controller: must,
                    decoration: InputDecoration(
                      labelText: 'Tutacak günler (1,4,7)',
                      suffixIcon: IconButton(
                        tooltip: 'Tutacak günlerini seç',
                        onPressed: () => chooseDays(must),
                        icon: const Icon(Icons.calendar_month),
                      ),
                    ),
                  ),
                  TextField(
                    controller: cannot,
                    decoration: InputDecoration(
                      labelText: 'Tutamaz günler (2,5)',
                      suffixIcon: IconButton(
                        tooltip: 'Tutamaz günlerini seç',
                        onPressed: () => chooseDays(cannot),
                        icon: const Icon(Icons.calendar_month),
                      ),
                    ),
                  ),
                  TextField(
                    controller: previous,
                    decoration: const InputDecoration(
                      labelText: 'Önceki nöbetler (YYYY-MM-DD,...)',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: AkysTokens.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (old != null)
              TextButton(
                onPressed: () {
                  remove = true;
                  Navigator.pop(c);
                },
                child: const Text('Hekimi çıkar'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Set<int> days(String t) {
                    if (t.trim().isEmpty) return {};
                    final values = t
                        .split(',')
                        .map((s) => int.parse(s.trim()) - 1)
                        .toSet();
                    if (values.any(
                      (d) => d < 0 || d >= w.problem.slotsPerDay.length,
                    )) {
                      throw const FormatException('Gün ay sınırları dışında');
                    }
                    return values;
                  }

                  final max = int.parse(cap.text);
                  if (max < 0 ||
                      max > w.problem.clinicMaxDuties ||
                      name.text.trim().isEmpty) {
                    throw const FormatException(
                      'Ad ve 0–8 arasında üst sınır gerekli',
                    );
                  }
                  final before = previous.text.trim().isEmpty
                      ? <DateTime>[]
                      : previous.text.split(',').map((s) {
                          final text = s.trim();
                          final d = DateTime.parse('${text}T00:00:00Z');
                          if (d.toIso8601String().split('T').first != text ||
                              !d.isBefore(w.problem.startDate!)) {
                            throw const FormatException(
                              'Önceki nöbet tarihi ay başlangıcından önce olmalı',
                            );
                          }
                          return d;
                        }).toList();
                  result = Doctor(
                    id:
                        old?.id ??
                        'local-${DateTime.now().microsecondsSinceEpoch}-${nextId++}',
                    maxDuties: max,
                    group: group,
                    seniorityRank: int.parse(rank.text),
                    seniorityLevel: group == DutyGroup.senior ? level : null,
                    eligibleRoles: roles,
                    must: days(must.text),
                    unavailable: days(cannot.text),
                    previousDuties: before,
                  );
                  final ordered = result!.must.toList()..sort();
                  if (ordered.length > result!.maxDuties ||
                      [
                        for (var i = 1; i < ordered.length; i++)
                          ordered[i] - ordered[i - 1],
                      ].any((gap) => gap < 3) ||
                      ordered.any(
                        (day) => result!.previousDuties.any(
                          (d) =>
                              w.problem.dateForDay(day).difference(d).inDays <
                              3,
                        ),
                      )) {
                    result = null;
                    throw const FormatException(
                      'Tutacak günleri kapasite veya üç günlük dinlenme kuralıyla çelişiyor',
                    );
                  }
                  Navigator.pop(c);
                } catch (e) {
                  set(
                    () => error =
                        'Girdi geçersiz. Tutacak/Tutamaz çakışmasını, günleri, sıralamayı ve tarihleri kontrol edin. $e',
                  );
                }
              },
              child: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (result != null || remove) {
      final docs = [...w.problem.doctors];
      if (remove) {
        docs.removeAt(index!);
      } else if (index == null) {
        docs.add(result!);
      } else {
        docs[index] = result!;
      }
      if (await confirmReset()) {
        try {
          w.replace(copy(doctors: docs));
          if (result != null) w.names[result!.id] = name.text.trim();
          refresh();
        } catch (e) {
          message(e);
        }
      }
    }
    for (final controller in [name, rank, cap, must, cannot, previous]) {
      controller.dispose();
    }
  }

  Future<void> configureDay(int day) async {
    final indices = [
      for (var i = 0; i < w.problem.slotDays.length; i++)
        if (w.problem.slotDays[i] == day) i,
    ];
    final roles = [for (final i in indices) w.problem.slotRoles![i]];
    final requirements = [
      for (final i in indices) w.problem.slotRequirements[i],
    ];
    final holiday = TextEditingController(
      text: w.problem.dayDifficulties![day].holidayName ?? '',
    );
    final score = TextEditingController(
      text: '${w.problem.dayDifficulties![day].holidayScore ?? 6}',
    );
    bool all = false;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(date(day)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < roles.length; i++)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        DropdownButton<DutyRole>(
                          value: roles[i],
                          items: [
                            for (final r in DutyRole.values)
                              DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r == DutyRole.senior ? 'Kıdemli' : 'Kıdemsiz',
                                ),
                              ),
                          ],
                          onChanged: (v) => set(() => roles[i] = v!),
                        ),
                        DropdownButton<SlotRequirement>(
                          value: requirements[i],
                          items: [
                            for (final r in SlotRequirement.values)
                              DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r == SlotRequirement.required
                                      ? 'Zorunlu'
                                      : 'Opsiyonel',
                                ),
                              ),
                          ],
                          onChanged: (v) => set(() => requirements[i] = v!),
                        ),
                        IconButton(
                          tooltip: 'Pozisyonu kaldır',
                          onPressed: () => set(() {
                            roles.removeAt(i);
                            requirements.removeAt(i);
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  TextButton.icon(
                    onPressed: () => set(() {
                      roles.add(DutyRole.junior);
                      requirements.add(SlotRequirement.optional);
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Pozisyon ekle'),
                  ),
                  CheckboxListTile(
                    title: const Text('Pozisyonları ayın tamamına uygula'),
                    value: all,
                    onChanged: (v) => set(() => all = v!),
                  ),
                  const Text(
                    'Tatil takvimi bu yerel alanda otomatik yüklenmez. Tatili ilgili tarih için girin.',
                  ),
                  TextField(
                    controller: holiday,
                    decoration: const InputDecoration(
                      labelText: 'Manuel tatil adı (boş = tatil yok)',
                    ),
                  ),
                  TextField(
                    controller: score,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tatil puanı 1–10 (hafta günü ile maksimum)',
                    ),
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(score.text);
                if (n == null || n < 1 || n > 10) {
                  set(() => error = 'Puan 1–10 tam sayı olmalı.');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final counts = <int>[],
          newRoles = <DutyRole>[],
          newRequirements = <SlotRequirement>[];
      for (var d = 0; d < w.problem.slotsPerDay.length; d++) {
        if (d == day || all) {
          counts.add(roles.length);
          newRoles.addAll(roles);
          newRequirements.addAll(requirements);
        } else {
          counts.add(w.problem.slotsPerDay[d]);
          for (var s = 0; s < w.problem.slotDays.length; s++) {
            if (w.problem.slotDays[s] == d) {
              newRoles.add(w.problem.slotRoles![s]);
              newRequirements.add(w.problem.slotRequirements[s]);
            }
          }
        }
      }
      final difficulties = [...w.problem.dayDifficulties!];
      difficulties[day] = DayDifficulty(
        weekdayScore: difficulties[day].weekdayScore,
        holidayName: holiday.text.trim().isEmpty ? null : holiday.text.trim(),
        holidayScore: holiday.text.trim().isEmpty
            ? null
            : int.parse(score.text),
      );
      await replace(
        copy(
          counts: counts,
          roles: newRoles,
          requirements: newRequirements,
          difficulties: difficulties,
        ),
      );
    }
    holiday.dispose();
    score.dispose();
  }

  String phaseLabel(TransitionPhase phase) => switch (phase) {
    TransitionPhase.restricted => 'A — geçişsiz',
    TransitionPhase.substitution => 'B — kanıt sonrası geçiş',
    TransitionPhase.done => 'Tamamlandı',
  };

  String get status {
    if (!w.pending) return 'Yerel taslak • Optimumluk kanıtı yok';
    final s = w.progress;
    return switch (s.state) {
      OptimizationState.idle => 'Hesaplama başlamadı',
      OptimizationState.preparing => 'Çalışma ortamı hazırlanıyor',
      OptimizationState.running => 'Aranıyor • Henüz geçerli çizelge yok',
      OptimizationState.feasible =>
        'Geçerli çizelge bulundu • Optimumluk kanıtlanmadı',
      OptimizationState.optimal => 'Optimumluk kanıtlandı (arama sonucu)',
      OptimizationState.infeasible => 'İmkânsızlık kanıtlandı',
      OptimizationState.timedOut =>
        s.best == null
            ? 'Süre doldu • Geçerli çizelge yok'
            : 'Süre doldu • Geçerli çizelge var, optimumluk kanıtlanmadı',
      OptimizationState.cancelled =>
        'Kullanıcı iptal etti • ${s.best == null ? 'Geçerli sonuç yok' : 'Son geçerli sonuç korundu'}',
      OptimizationState.failed => 'Teknik hata: ${s.error}',
    };
  }

  static const qualityLabels = [
    'Kıdemsiz geçişi',
    'Kıdemsiz kapsaması (negatif)',
    'İkinci kıdemsiz günleri (negatif)',
    'K4 tek kıdemli günleri (negatif)',
    'K3 tek kıdemli günleri (negatif)',
    'K2 tek kıdemli günleri (negatif)',
    'K1 tek kıdemli günleri (negatif)',
    'Cumartesi: en kötü grup farkı',
    'Cumartesi: grup farkları toplamı',
    'Cuma: en kötü grup farkı',
    'Cuma: grup farkları toplamı',
    'Pazar: en kötü grup farkı',
    'Pazar: grup farkları toplamı',
    'Perşembe: en kötü grup farkı',
    'Perşembe: grup farkları toplamı',
    'Normalize yük: en kötü grup farkı',
    'Normalize yük: grup farkları toplamı',
    'Zorluk: en kötü grup içi fark',
    'En yüksek bireysel zorluk',
  ];
  String vector(ClinicalQuality? q) => q == null
      ? 'Tam ve doğrulanmış çizelge gerekli'
      : q.components.join(', ');
  Widget quality() {
    final s = w.progress;
    final best = w.pending ? s.best : null;
    final assignments = best?.assignments ?? w.editor.current.assignments;
    final current = w.editor.current.quality;
    final filled = assignments.where((d) => d >= 0).length;
    final optional = [
      for (var i = 0; i < assignments.length; i++)
        if (w.problem.slotRequirements[i] == SlotRequirement.optional) i,
    ];
    return ListView(
      key: PageStorageKey('v2-tab-$tab'),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  key: const Key('status'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${s.elapsed.inMilliseconds} ms • ${s.nodes} düğüm • ${s.pruned} budama • A/B: ${phaseLabel(s.phase)}',
                ),
                Text(
                  'İlk çözüm: ${s.firstFeasible?.inMilliseconds.toString() ?? "—"} ms',
                ),
                if (w.pending)
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        key: const Key('cancel'),
                        onPressed: w.busy ? () => w.runtime.cancel() : null,
                        child: const Text('İptal et'),
                      ),
                      OutlinedButton(
                        key: const Key('extend'),
                        onPressed: s.canExtend
                            ? () =>
                                  w.runtime.extend(const Duration(seconds: 30))
                            : null,
                        child: const Text('30 saniye uzat'),
                      ),
                    ],
                  ),
                if (w.pending && best != null) ...[
                  Text(
                    w.previewOnly
                        ? 'B sonucu yalnız önizleme: süreç içi geçiş kanıtı bu arayüzde kalıcı onay yetkisi sağlamaz.'
                        : 'Sonuç önizlemesi • Taslak henüz değiştirilmedi.',
                  ),
                  if (w.difference != null)
                    Text(
                      '${w.difference!.changedPositions} değişen pozisyon • ${w.difference!.preservedLocks.length} korunan kilit',
                    ),
                  Text('Önceki kalite: ${vector(current)}'),
                  Text('Yeni kalite: ${vector(best.clinicalQuality)}'),
                  if (current != null)
                    Text(
                      'Leksikografik karşılaştırma: ${best.clinicalQuality!.compareTo(current) < 0
                          ? 'İyileşme'
                          : best.clinicalQuality!.compareTo(current) > 0
                          ? 'Kötüleşme'
                          : 'Eşit'}',
                    ),
                  FilledButton(
                    key: const Key('accept'),
                    onPressed: w.previewOnly ? null : () => w.accept(),
                    child: const Text('Yerel taslağa kabul et'),
                  ),
                  ExpansionTile(
                    title: const Text('Önce / sonra atamalar'),
                    children: [
                      for (var i = 0; i < assignments.length; i++)
                        ListTile(
                          title: Text(slotName(i)),
                          subtitle: Text(
                            '${w.name(w.editor.current.assignments[i])} → ${w.name(assignments[i])}',
                          ),
                        ),
                    ],
                  ),
                ],
                if (w.pending)
                  TextButton(
                    key: const Key('reject'),
                    onPressed: () => w.reject(),
                    child: const Text('Sonucu reddet / Taslağa dön'),
                  ),
                const Text(
                  'Kalıcı onay ve yayın bu modülde kapalıdır. Manuel taslak optimumluk kanıtı taşımaz.',
                ),
              ],
            ),
          ),
        ),
        if (!w.pending && w.lastEdit != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Son manuel işlem • Önce / sonra kalite'),
                  Text(vector(w.lastEdit!.before.quality)),
                  Text(vector(w.lastEdit!.after.quality)),
                  Text(
                    w.lastEdit!.qualityComparison == null
                        ? 'Eksik taslakta kalite karşılaştırması yapılamaz'
                        : w.lastEdit!.qualityComparison! < 0
                        ? 'İyileşme'
                        : w.lastEdit!.qualityComparison! > 0
                        ? 'Kötüleşme'
                        : 'Eşit',
                  ),
                ],
              ),
            ),
          ),
        Text(
          'Doluluk: $filled / ${assignments.length} • OPTIONAL ${optional.where((i) => assignments[i] >= 0).length} / ${optional.length} • REQUIRED ${filled - optional.where((i) => assignments[i] >= 0).length} / ${assignments.length - optional.length}',
        ),
        for (final group in DutyGroup.values)
          Text(
            '${group == DutyGroup.senior ? 'Kıdemli' : 'Kıdemsiz'} grubu: ${[for (final d in assignments)
              if (d >= 0 && w.problem.doctors[d].group == group) d].length} nöbet • ${w.problem.doctors.where((d) => d.group == group).length} hekim',
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final h in [
                'Hekim / Grup',
                'Nöbet',
                'Per',
                'Cum',
                'Cmt',
                'Paz',
                'Zorluk',
              ])
                DataColumn(label: Text(h)),
            ],
            rows: [
              for (var d = 0; d < w.problem.doctors.length; d++)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        '${w.name(d)} / ${w.problem.doctors[d].group == DutyGroup.senior ? 'Kıdemli' : 'Kıdemsiz'}',
                      ),
                    ),
                    DataCell(
                      Text(
                        '${assignments.where((v) => v == d).length} / ${w.problem.doctors[d].maxDuties}',
                      ),
                    ),
                    for (final weekday in [4, 5, 6, 7])
                      DataCell(
                        Text(
                          '${[for (var i = 0; i < assignments.length; i++)
                            if (assignments[i] == d && w.problem.dateForDay(w.problem.slotDays[i]).weekday == weekday) i].length}',
                        ),
                      ),
                    DataCell(
                      Text(
                        '${[for (var i = 0; i < assignments.length; i++)
                          if (assignments[i] == d) w.problem.dayDifficulties![w.problem.slotDays[i]].effectiveScore].fold<int>(0, (a, b) => a + b)}',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        ExpansionTile(
          title: const Text(
            '19 bileşenli klinik kalite (kesin minimizasyon sırası)',
          ),
          children: [
            if ((best?.clinicalQuality ?? current) != null)
              for (var i = 0; i < 19; i++)
                ListTile(
                  dense: true,
                  title: Text('${i + 1}. ${qualityLabels[i]}'),
                  subtitle: SelectableText(
                    '${(best?.clinicalQuality ?? current)!.components[i]}',
                  ),
                )
            else
              const Text('Tam ve doğrulanmış çizelge gerekli'),
          ],
        ),
      ],
    );
  }
}
