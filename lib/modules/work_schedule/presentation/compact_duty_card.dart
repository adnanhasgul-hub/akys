import 'package:flutter/material.dart';

import '../../../core/design/akys_design_system.dart';
import '../domain/models.dart';
import '../domain/duty_positions.dart';

/// Displays persisted/preview roles only. Legacy person order never implies role.
class CompactDutyCard extends StatelessWidget {
  const CompactDutyCard({
    required this.month,
    required this.day,
    this.position,
    this.positionsKnown = false,
    this.errors = const [],
    this.warnings = const [],
    this.actions = const [],
    this.onEdit,
    super.key,
  });
  final ScheduleMonth month;
  final int day;
  final DutyPositions? position;
  final bool positionsKnown;
  final List<String> errors, warnings;
  final List<Widget> actions;
  final VoidCallback? onEdit;
  String name(String? id) {
    for (final p in month.people) {
      if (p.personId == id) return p.displayName;
    }
    return 'Atanmamış / bilinmeyen personel';
  }

  @override
  Widget build(BuildContext context) {
    final date = month.date(day),
        holiday = month.difficulty.holiday(month.date(day));
    final ids = position != null
        ? [?position!.seniorDutyPersonId, ...position!.juniorDutyPersonIds]
        : month.duties[day] ?? <String>[];
    final known = positionsKnown || position != null;
    return Card(
      color: errors.isNotEmpty
          ? AkysTokens.errorSurface
          : date.weekday >= 6
          ? AkysTokens.background
          : AkysTokens.surface,
      child: ExpansionTile(
        key: PageStorageKey('${key ?? 'saved'}-duty-${month.id}-$day'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.all(12),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$day · ${dayNames[date.weekday - 1]}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    dateKey(date),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: 'Pozisyonları düzenle',
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (known) ...[
              Text(
                'Senior: ${name(position?.seniorDutyPersonId)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                position == null || position!.juniorDutyPersonIds.isEmpty
                    ? 'Junior: Boş pozisyon'
                    : 'Junior: ${position!.juniorDutyPersonIds.map(name).join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ] else ...[
              const Text('Pozisyon bilgisi kayıtlı değil'),
              Text(
                'Nöbetçiler: ${ids.map(name).join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            Text('Zorluk: ${month.difficultyScore(day)}'),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (holiday != null)
                  AkysStatusChip(
                    label:
                        '${holiday.name}${holiday.isHalfDay ? ' · Yarım gün' : ''}',
                    status: AkysStatus.info,
                  ),
                if (position?.seniorRoleIsSubstitution == true)
                  const AkysStatusChip(
                    label: 'Geçici senior',
                    status: AkysStatus.info,
                  ),
                if (errors.isNotEmpty)
                  AkysStatusChip(
                    label: '${errors.length} zorunlu kural hatası',
                    status: AkysStatus.error,
                  ),
                if (warnings.isNotEmpty)
                  AkysStatusChip(
                    label: '${warnings.length} uyarı',
                    status: AkysStatus.warning,
                  ),
              ],
            ),
          ],
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in ids)
                  Text(
                    '${name(id)} · ${known ? (id == position?.seniorDutyPersonId ? 'Senior pozisyonu' : 'Junior pozisyonu') : 'Pozisyon bilinmiyor'}${month.people.any((p) => p.personId == id) ? ' · K${month.person(id).seniorityRank} · Grup: ${dutyGroupLabel(month.person(id).dutySeniorityGroup)}' : ''}',
                  ),
                if (position?.seniorRoleIsSubstitution == true)
                  const Text(
                    'Geçici senior ataması; personelin kalıcı grubu değişmez.',
                  ),
                if (known && (position?.juniorDutyPersonIds.isEmpty ?? true))
                  Text(
                    'Boşluk gerekçesi: ${position?.juniorVacancyReason ?? 'Kayıtlı gerekçe yok; doğrulama gerekir.'}',
                  ),
                if (!known)
                  const Text(
                    'Eski kayıtların senior/junior pozisyonları tahmin edilmez.',
                  ),
                for (final e in errors)
                  Text(e, style: const TextStyle(color: AkysTokens.error)),
                for (final w in warnings) Text(w),
                ...actions,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
