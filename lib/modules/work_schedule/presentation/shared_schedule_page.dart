import 'package:flutter/material.dart';

import '../../../core/platform/export_file.dart';
import '../../../core/theme/akys_colors.dart';
import '../application/schedule_export.dart';
import '../data/schedule_repository.dart';
import '../domain/models.dart';

class SharedSchedulePage extends StatefulWidget {
  const SharedSchedulePage({
    required this.token,
    required this.repository,
    super.key,
  });
  final String token;
  final ScheduleRepository repository;
  @override
  State<SharedSchedulePage> createState() => _SharedSchedulePageState();
}

class _SharedSchedulePageState extends State<SharedSchedulePage> {
  late Stream<Map<String, dynamic>?> stream;
  String? selected, error;
  @override
  void initState() {
    super.initState();
    stream = widget.repository.watchShared(widget.token);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AKYS · Paylaşılan Çizelge'),
      automaticallyImplyLeading: false,
    ),
    body: StreamBuilder<Map<String, dynamic>?>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bu paylaşım kullanılamıyor. Bağlantı iptal edilmiş, süresi dolmuş veya erişim sağlanamıyor olabilir.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Bağlantı doğrulanıyor…'),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        if (data['revoked'] == true) {
          return const Center(child: Text('Bu paylaşım iptal edildi.'));
        }
        final people = (data['people'] as List).cast<Map>();
        String name(String? id) => id == null
            ? 'Görev karşılanamıyor'
            : people
                      .where((p) => p['personId'] == id)
                      .map((p) => p['displayName'] as String)
                      .firstOrNull ??
                  'Bilinmeyen personel';
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  data['title'] as String,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Text(
                  'Salt okunur çizelge · Kişisel koşullar ve yönetim verileri paylaşılmaz.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DropdownButtonFormField<String>(
                        initialValue: selected,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Kendi adınızı seçin',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Tüm personel'),
                          ),
                          for (final p in people)
                            DropdownMenuItem(
                              value: p['personId'] as String,
                              child: Text(p['displayName'] as String),
                            ),
                        ],
                        onChanged: (id) => setState(() => selected = id),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: selected == null
                          ? null
                          : () async {
                              try {
                                final box =
                                    context.findRenderObject() as RenderBox;
                                await exportFile(
                                  exportIcs(data, selected!),
                                  'AKYS-${data['monthId']}-kisisel.ics',
                                  'text/calendar',
                                  box.localToGlobal(Offset.zero) & box.size,
                                );
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => error = 'Takvim dosyası hazırlanamadı. Yeniden deneyin.',
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.event_available),
                      label: const Text('Takvimime Ekle (.ics)'),
                    ),
                  ],
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: AkysColors.forbidden),
                  ),
                const SizedBox(height: 16),
                for (var d = 1; d <= (data['days'] as int); d++)
                  ..._day(data, d, name),
              ],
            ),
          ),
        );
      },
    ),
  );
  List<Widget> _day(
    Map<String, dynamic> data,
    int day,
    String Function(String?) name,
  ) {
    final duties = List<String>.from(
      (data['duties'] as Map)['$day'] as List? ?? [],
    );
    final tasks = ((data['dailyTasks'] as Map)['$day'] as List? ?? [])
        .cast<Map>();
    final mine = tasks
        .where((t) => selected == null || t['personId'] == selected)
        .toList();
    if (selected != null && !duties.contains(selected) && mine.isEmpty) {
      return [];
    }
    final date = DateTime.utc(data['year'] as int, data['month'] as int, day);
    return [
      Card(
        color: AkysColors.weekdays[date.weekday - 1],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$day ${dayNames[date.weekday - 1]}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (selected == null || duties.contains(selected))
                Text(
                  'Nöbet: ${duties.map(name).join(', ')}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              for (final t in mine)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${taskLabel(ClinicTask.values.byName(t['task'] as String))}: ${name(t['personId'] as String?)}${t['manual'] == true ? ' (Manuel)' : ''}${(t['warnings'] as List).isNotEmpty ? ' ⚠' : ''}',
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }
}
