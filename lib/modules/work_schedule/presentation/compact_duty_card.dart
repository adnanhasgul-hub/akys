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

  Widget _role(String badge, String text, bool junior) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        label: junior ? 'Junior pozisyonu' : 'Senior pozisyonu',
        child: Container(
          width: 26,
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: junior ? AkysTokens.selected : AkysTokens.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            badge,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: junior ? AkysTokens.primary : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
      ),
    ],
  );
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
        dense: true,
        minTileHeight: 64,
        key: PageStorageKey('${key ?? 'saved'}-duty-${month.id}-$day'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        childrenPadding: const EdgeInsets.all(12),
        trailing: onEdit == null
            ? const Icon(Icons.chevron_right, size: 18)
            : IconButton(
                tooltip: 'Pozisyonları düzenle',
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: date.weekday == 4
                        ? AkysTokens.successSurface
                        : AkysTokens.selected.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Column(
                    children: [
                      Text(
                        day.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        const [
                          'Pzt',
                          'Sal',
                          'Çar',
                          'Per',
                          'Cum',
                          'Cmt',
                          'Paz',
                        ][date.weekday - 1],
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (known) ...[
                        _role('K', name(position?.seniorDutyPersonId), false),
                        const SizedBox(height: 3),
                        _role(
                          'Ç',
                          position == null ||
                                  position!.juniorDutyPersonIds.isEmpty
                              ? '— (Boş)'
                              : position!.juniorDutyPersonIds
                                    .map(name)
                                    .join(', '),
                          true,
                        ),
                      ] else ...[
                        Text(
                          ids.isEmpty
                              ? 'Nöbet atanmamış'
                              : ids.map(name).join('\n'),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Text(
                          'Pozisyon bilgisi kayıtlı değil',
                          style: TextStyle(
                            fontSize: 11,
                            color: AkysTokens.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Semantics(
                  label: 'Zorluk: ${month.difficultyScore(day)}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AkysTokens.infoSurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Z: ${month.difficultyScore(day)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
            if (holiday != null)
              Text(
                '${holiday.name}${holiday.isHalfDay ? ' · Yarım gün' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            if (position?.seniorRoleIsSubstitution == true)
              const Text(
                'Geçici senior · kalıcı grup Çömez',
                style: TextStyle(fontSize: 11, color: AkysTokens.info),
              ),
            if (errors.isNotEmpty)
              Text(
                '${errors.length} zorunlu kural hatası',
                style: const TextStyle(fontSize: 11, color: AkysTokens.error),
              ),
            if (warnings.isNotEmpty)
              Text(
                '${warnings.length} uyarı',
                style: const TextStyle(
                  fontSize: 11,
                  color: AkysTokens.warningText,
                ),
              ),
          ],
        ),
        children: [
          Text(dateKey(date)),
          Text('Zorluk: ${month.difficultyScore(day)}'),
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
