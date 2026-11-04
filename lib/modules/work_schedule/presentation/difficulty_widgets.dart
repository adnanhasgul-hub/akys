import 'package:flutter/material.dart';

import '../../../core/design/akys_design_system.dart';

import '../domain/models.dart';
import '../domain/difficulty.dart';
import '../data/calendar/turkey_holidays.dart';

Future<Map<String, int>?> chooseHolidayScores(
  BuildContext context,
  List<HolidayDay> holidays,
) async {
  if (holidays.isEmpty) return <String, int>{};
  final selected = <String, int>{};
  return showDialog<Map<String, int>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Resmî Tatil Nöbet Puanları'),
        content: SizedBox(
          width: 560,
          height: 440,
          child: ListView(
            children: [
              const Text(
                'Her resmî tatil için ayrı 1–10 puan seçin. Puanlar yalnız bu ayda saklanır.',
              ),
              const SizedBox(height: 12),
              for (final h in holidays)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${h.date} · ${dayNames[DateTime.parse(h.date).weekday - 1]}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${h.name} · ${h.isHalfDay ? 'Yarım gün' : 'Tam gün'}',
                      ),
                      DropdownButtonFormField<int>(
                        key: ValueKey('holiday-score-${h.date}'),
                        initialValue: selected[h.date],
                        decoration: const InputDecoration(
                          labelText: 'Nöbet zorluk puanı',
                        ),
                        items: [
                          for (var i = 1; i <= 10; i++)
                            DropdownMenuItem(value: i, child: Text('$i')),
                        ],
                        onChanged: (n) => update(() => selected[h.date] = n!),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: selected.length != holidays.length
                ? null
                : () => Navigator.pop(context, Map<String, int>.from(selected)),
            child: const Text('Puanları Onayla ve Ayı Oluştur'),
          ),
        ],
      ),
    ),
  );
}

class DifficultySettingsPanel extends StatefulWidget {
  const DifficultySettingsPanel({
    required this.settings,
    required this.busy,
    required this.onSave,
    super.key,
  });
  final DifficultySettings settings;
  final bool busy;
  final Future<bool> Function(DifficultySettings) onSave;
  @override
  State<DifficultySettingsPanel> createState() =>
      _DifficultySettingsPanelState();
}

class _DifficultySettingsPanelState extends State<DifficultySettingsPanel> {
  String? feedback;
  bool saveFailed = false;
  late List<int> days;
  late int pre;
  late List<HolidayDay> custom;
  @override
  void initState() {
    super.initState();
    days = [...widget.settings.weekdayScores];
    pre = widget.settings.preHolidayDifficultyScore;
    custom = [...widget.settings.customHolidays];
  }

  Widget score(String label, int value, ValueChanged<int> change, String key) =>
      AkysCard(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<int>(
          key: ValueKey('$key-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (var n = 1; n <= 10; n++)
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: widget.busy ? null : (n) => setState(() => change(n!)),
        ),
      );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const AkysSectionHeader(title: 'Nöbet Puanlama Ayarları'),
      const SizedBox(height: 8),
      const Text(
        'Yalnızca yeni ayları etkiler. Mevcut ayların puan snapshot’ları değişmez. Tüm puanlar 1–10 arası tam sayıdır.',
      ),
      const SizedBox(height: 20),
      AkysResponsiveTiles(
        minimumWidth: 230,
        maxColumns: 3,
        children: [
          for (var i = 0; i < 7; i++)
            score(dayNames[i], days[i], (n) => days[i] = n, 'weekday-${i + 1}'),
          score('Tatil öncesi puanı', pre, (n) => pre = n, 'pre-holiday'),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Tatil öncesi Cumartesi daima güncel Cumartesi puanını kullanır. Yarım gün tatilinin bir önceki günü otomatik olarak tatil öncesi sayılmaz.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: widget.busy
                ? null
                : () async {
                    final ok = await widget.onSave(
                      DifficultySettings(
                        weekdayScores: days,
                        preHolidayDifficultyScore: pre,
                        revision: widget.settings.revision,
                        customHolidays: custom,
                      ),
                    );
                    if (mounted) {
                      setState(() {
                        saveFailed = !ok;
                        feedback = ok ? 'Puanlama ayarları kaydedildi.' : 'Ayarlar kaydedilemedi. Değişikliklerinizi kontrol edip yeniden deneyin.';
                      });
                    }
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Puanlama Ayarlarını Kaydet'),
          ),
          TextButton(
            onPressed: widget.busy
                ? null
                : () => setState(() {
                    days = [...widget.settings.weekdayScores];
                    pre = widget.settings.preHolidayDifficultyScore;
                    custom = [...widget.settings.customHolidays];
                    feedback = null;
                  }),
            child: const Text('Değişikliklerden Vazgeç'),
          ),
          OutlinedButton(
            onPressed: widget.busy
                ? null
                : () => setState(() {
                    final d = DifficultySettings.defaults();
                    days = [...d.weekdayScores];
                    pre = d.preHolidayDifficultyScore;
                  }),
            child: const Text('Varsayılanları Geri Yükle'),
          ),
        ],
      ),
      if (feedback != null)
        AkysStatusChip(
          label: feedback!,
          status: saveFailed ? AkysStatus.error : AkysStatus.success,
        ),
      const SizedBox(height: 28),
      Text(
        'Türkiye Resmî Tatil Takvimi',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        'Doğrulanmış yerel yıllar: ${TurkeyHolidayCalendar.supportedYears.join(', ')}. Kaynak: Türkiye Bankalar Birliği, Bankalar için Tatil Günleri. Çevrimdışı çalışır.',
      ),
      const SizedBox(height: 8),
      SelectableText(TurkeyHolidayCalendar.source),
      const SizedBox(height: 20),
      Text(
        'Kullanıcı Tarafından Doğrulanan Özel Günler',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Özel günler puanlama takvimine eklenir; ay oluştururken ayrıca puan seçilir. Resmî tatiller silinmez veya yarım güne düşürülmez.',
      ),
      for (final h in custom)
        Card(
          child: ListTile(
            title: Text('${h.date} · ${h.name}'),
            subtitle: Text(
              '${h.isHalfDay ? 'Yarım gün' : 'Tam gün'} · ${h.source}',
            ),
            trailing: IconButton(
              tooltip: 'Özel günü kaldır',
              onPressed: widget.busy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Özel Günü Kaldır'),
                          content: const Text(
                            'Kaydettikten sonra yeni aylara dahil edilmeyecek. Geçmiş aylar korunur.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Vazgeç'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Kaldır'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        setState(() => custom.remove(h));
                      }
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        ),
      TextButton.icon(
        onPressed: widget.busy ? null : _addCustom,
        icon: const Icon(Icons.event_available),
        label: const Text('Özel Gün Ekle'),
      ),
    ],
  );
  Future<void> _addCustom() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null || !mounted) return;
    final name = TextEditingController(), source = TextEditingController();
    var half = false;
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('${holidayDateKey(date)} Özel Gün'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Özel gün adı',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Ad zorunlu.' : null,
                  ),
                  TextFormField(
                    controller: source,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Doğrulama kaynağı / açıklama',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Kaynak zorunlu.' : null,
                  ),
                  CheckboxListTile(
                    title: const Text('Yarım gün'),
                    value: half,
                    onChanged: (v) => update(() => half = v!),
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
              child: const Text('Listeye Ekle'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        custom.removeWhere((h) => h.date == holidayDateKey(date));
        custom.add(
          HolidayDay(
            date: holidayDateKey(date),
            name: name.text.trim(),
            isHalfDay: half,
            source: 'Kullanıcı: ${source.text.trim()}',
            calendarYear: date.year,
            custom: true,
            triggersPreHoliday: !half,
          ),
        );
      });
    }
  }
}
