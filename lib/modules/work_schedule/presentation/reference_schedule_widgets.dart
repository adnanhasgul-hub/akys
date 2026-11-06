import 'package:flutter/material.dart';

import '../../../core/design/akys_design_system.dart';
import '../domain/models.dart';
import 'compact_duty_card.dart';

const shortWeekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// Presentation-only choices. Values and mutations stay with the owner.
class ScheduleSegments extends StatelessWidget {
  const ScheduleSegments({
    required this.labels,
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AkysTokens.selected.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 42),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                backgroundColor: i == selected
                    ? AkysTokens.primary
                    : Colors.transparent,
                foregroundColor: i == selected ? Colors.white : AkysTokens.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => onChanged(i),
              child: Semantics(
                selected: i == selected,
                child: Text(labels[i], textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    ),
  );
}

class ScheduleMetric extends StatelessWidget {
  const ScheduleMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.warning = false,
    super.key,
  });
  final String label, value;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) => AkysCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        Icon(
          icon,
          size: 30,
          color: warning ? AkysTokens.warningText : AkysTokens.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Calendar is a read-only projection. Never infers roles for old records.
class DutyMonthGrid extends StatelessWidget {
  const DutyMonthGrid({required this.month, super.key});
  final ScheduleMonth month;
  @override
  Widget build(BuildContext context) {
    final offset = month.date(1).weekday - 1;
    final cells = ((offset + month.days) / 7).ceil() * 7;
    return Column(
      children: [
        Row(
          children: [
            for (final day in shortWeekdays)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              for (var row = 0; row < cells ~/ 7; row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _cell(context, row * 7 + col - offset + 1),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Legend('Kıdemli + Çömez', AkysTokens.primary),
            _Legend('Kıdemli (Tek)', AkysTokens.warning),
            _Legend('Pozisyon bilinmiyor', AkysTokens.muted),
          ],
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, int day) {
    final inMonth = day >= 1 && day <= month.days;
    final date = month.date(1).add(Duration(days: day - 1));
    final p = month.dutyPositions
        ?.where((p) => p.date == dateKey(date))
        .firstOrNull;
    final assigned = (month.duties[day] ?? []).isNotEmpty;
    final color = p == null
        ? AkysTokens.muted
        : p.juniorDutyPersonIds.isEmpty
        ? AkysTokens.warning
        : AkysTokens.primary;
    final holiday = inMonth ? month.difficulty.holiday(date) : null;
    final description = p == null
        ? 'Pozisyon bilinmiyor'
        : p.juniorDutyPersonIds.isEmpty
        ? 'Kıdemli tek, junior boş'
        : 'Kıdemli ve çömez';
    return Semantics(
      label:
          '${dateKey(date)}${inMonth ? ', $description${holiday == null ? '' : ', ${holiday.name}'}' : ', diğer ay'}',
      child: Material(
        color: !inMonth
            ? AkysTokens.background
            : holiday != null
            ? AkysTokens.infoSurface
            : date.weekday >= 6
            ? AkysTokens.warning.withValues(alpha: .09)
            : Colors.white,
        child: InkWell(
          onTap: !inMonth
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('${date.day} ${monthNames[date.month - 1]}'),
                    content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: CompactDutyCard(
                          month: month,
                          day: day,
                          position: p,
                          positionsKnown: month.dutyPositions != null,
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Kapat'),
                      ),
                    ],
                  ),
                ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            decoration: BoxDecoration(
              border: Border.all(color: AkysTokens.softBorder, width: .5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
            child: Column(
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontWeight: inMonth ? FontWeight.w600 : FontWeight.normal,
                    color: inMonth ? AkysTokens.navy : AkysTokens.muted,
                  ),
                ),
                const SizedBox(height: 4),
                if (inMonth && assigned)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (p != null && p.juniorDutyPersonIds.isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AkysTokens.selected,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 12, color: color),
      const SizedBox(width: 6),
      Flexible(child: Text(label, style: const TextStyle(fontSize: 11))),
    ],
  );
}
