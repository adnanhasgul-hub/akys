import 'package:flutter/material.dart';

import '../../../core/design/akys_design_system.dart';
import '../domain/models.dart';
import '../engine/task_engine.dart';
import 'compact_duty_card.dart';

/// Presentation only: work periods, substitutions and warnings come from the
/// existing monthly snapshot and task engine. No assignments are inferred.
class CombinedDayCards extends StatefulWidget {
  const CombinedDayCards({
    required this.month,
    this.onEdit,
    this.hardErrors = const [],
    super.key,
  });
  final ScheduleMonth month;
  final List<String> hardErrors;
  final void Function(int day, ClinicTask task)? onEdit;
  @override
  State<CombinedDayCards> createState() => _CombinedDayCardsState();
}

class _CombinedDayCardsState extends State<CombinedDayCards> {
  int? selectedDay;
  @override
  void didUpdateWidget(covariant CombinedDayCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.id != widget.month.id) selectedDay = null;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hardErrors.isNotEmpty)
          ExpansionTile(
            title: const Text('Nöbet kısıt ihlalleri'),
            children: [
              for (final e in widget.hardErrors)
                AkysStatusChip(label: e, status: AkysStatus.error),
            ],
          ),
        DropdownButtonFormField<int>(
          key: ValueKey('task-date-${m.id}'),
          initialValue: selectedDay ?? 0,
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(labelText: 'Gösterilecek tarih'),
          items: [
            const DropdownMenuItem(value: 0, child: Text('Bütün günler')),
            for (var d = 1; d <= m.days; d++)
              DropdownMenuItem(
                value: d,
                child: Text(
                  '${dateKey(m.date(d))} · ${dayNames[m.date(d).weekday - 1]}',
                ),
              ),
          ],
          onChanged: (d) => setState(() => selectedDay = d == 0 ? null : d),
        ),
        const SizedBox(height: 12),
        AkysResponsiveTiles(
          minimumWidth: 360,
          maxColumns: 3,
          children: [
            for (var d = 1; d <= m.days; d++)
              if (selectedDay == null || selectedDay == d) _day(m, d),
          ],
        ),
      ],
    );
  }

  Widget _day(ScheduleMonth m, int d) {
    final tasks = dailyTasks(m, d);
    final warnings = tasks
        .where((t) => t.active)
        .expand((t) => t.warnings)
        .toList();
    final positions = m.dutyPositions?.where(
      (p) => p.date == dateKey(m.date(d)),
    );
    final off = m.people
        .where((p) => postDuty(m, p.personId, d))
        .map((p) => p.displayName)
        .join(', ');
    return AkysCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey('combined-${m.id}-$d'),
        title: Text('$d · ${dayNames[m.date(d).weekday - 1]}'),
        subtitle: Text(
          '${dateKey(m.date(d))}\n${tasks.first.workPeriodLabel}${warnings.isEmpty ? '' : '\n⚠ ${warnings.length} görev uyarısı'}',
        ),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          const AkysSectionHeader(title: 'Nöbet'),
          CompactDutyCard(
            key: ValueKey('combined-duty-$d'),
            month: m,
            day: d,
            position: positions == null || positions.isEmpty
                ? null
                : positions.first,
            positionsKnown: m.dutyPositions != null,
          ),
          const SizedBox(height: 12),
          const AkysSectionHeader(title: 'Nöbet sonrası izin'),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(off.isEmpty ? 'Nöbet sonrası izinli yok.' : off),
          ),
          const SizedBox(height: 12),
          const AkysSectionHeader(title: 'Klinik görevler'),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    taskLabel(task.task),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (!task.active)
                    Text(task.workPeriodLabel)
                  else ...[
                    Text(
                      task.personId == null
                          ? 'Görev karşılanamıyor'
                          : m.person(task.personId!).displayName,
                    ),
                    Text(
                      '${task.manual
                          ? 'Manuel atama'
                          : task.backup
                          ? 'Yedek devraldı'
                          : 'Asıl'} · ${task.workPeriodLabel}',
                    ),
                    for (final warning in task.warnings)
                      AkysStatusChip(
                        label: warning,
                        status: AkysStatus.warning,
                      ),
                    if (widget.onEdit != null)
                      TextButton.icon(
                        onPressed: () => widget.onEdit!(d, task.task),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Görevi düzenle'),
                      ),
                  ],
                ],
              ),
            ),
          if (warnings.isNotEmpty)
            Text(
              '${warnings.length} görev uyarısı',
              style: const TextStyle(color: AkysTokens.warningText),
            ),
        ],
      ),
    );
  }
}
