import '../domain/models.dart';

class DutyStatistics {
  DutyStatistics(this.total, this.categories);
  final int total;
  final List<int> categories;
}

int dayCategory(DateTime date) => date.weekday <= 3 ? 0 : date.weekday - 3;
Map<String, DutyStatistics> statistics(ScheduleMonth m) => {
  for (final p in m.people)
    p.personId: DutyStatistics(
      m.duties.values.where((ids) => ids.contains(p.personId)).length,
      [
        for (var c = 0; c < 5; c++)
          m.duties.entries
              .where(
                (e) =>
                    dayCategory(m.date(e.key)) == c &&
                    e.value.contains(p.personId),
              )
              .length,
      ],
    ),
};

/// Independent invariant checker, used by generation, manual edits and finalization.
List<String> validateDuties(ScheduleMonth m, {bool complete = true}) {
  final errors = <String>[];
  final ids = m.people.map((p) => p.personId).toSet();
  if (m.people.isEmpty) errors.add('Aktif personel yok.');
  if (m.requiredDuties < m.days ||
      m.requiredDuties > m.days * 3 ||
      m.requiredDuties > m.people.length * 8) {
    errors.add(
      'Aylık ihtiyaç günlük 1–3 kişi ve kişi başı en fazla 8 nöbet kapasitesiyle uyumsuz.',
    );
  }
  for (final e in m.duties.entries) {
    if (e.key < 1 || e.key > m.days) errors.add('Ay dışında nöbet tarihi.');
    if (e.value.toSet().length != e.value.length ||
        e.value.any((id) => !ids.contains(id))) {
      errors.add('Geçersiz veya yinelenen personel.');
    }
    if (e.value.length > 3) {
      errors.add('${e.key}. gün en fazla üç nöbetçi olabilir.');
    }
  }
  for (final p in m.people) {
    final c = m.constraints[p.personId] ?? PersonalConstraints();
    if (c.cannot.intersection(c.must).isNotEmpty) {
      errors.add('${p.displayName}: Tutamaz/Tutacak çakışması.');
    }
    if ({...c.cannot, ...c.must}.any((d) => d < 1 || d > m.days)) {
      errors.add('${p.displayName}: Ay dışında koşul.');
    }
    if (c.must.length > 8) {
      errors.add('${p.displayName}: Sekizden fazla sabit nöbet.');
    }
    final fixed = c.must.toList()..sort();
    for (var i = 1; i < fixed.length; i++) {
      if (fixed[i] - fixed[i - 1] < 3) {
        errors.add(
          '${p.displayName}: Sabit nöbetler arası en az üç gün olmalı.',
        );
      }
    }
    final days =
        m.duties.entries
            .where((e) => e.value.contains(p.personId))
            .map((e) => e.key)
            .toList()
          ..sort();
    if (days.length > 8) errors.add('${p.displayName}: En fazla sekiz nöbet.');
    for (var i = 1; i < days.length; i++) {
      if (days[i] - days[i - 1] < 3) {
        errors.add('${p.displayName}: Nöbetler arası en az üç gün olmalı.');
      }
    }
    for (final day in days) {
      if (c.cannot.contains(day)) {
        errors.add('${p.displayName}: $day. gün Tutamaz.');
      }
    }
    for (final day in fixed) {
      if (complete && !days.contains(day)) {
        errors.add('${p.displayName}: $day. gün sabit nöbet eksik.');
      }
    }
    for (final b in m.boundary[p.personId] ?? <String>[]) {
      final before = calendarDate(b);
      if (!before.isBefore(m.date(1))) {
        errors.add('${p.displayName}: Sınır nöbeti önceki ayda olmalı.');
      }
      for (final day in {...days, ...fixed}) {
        if (m.date(day).difference(before).inDays < 3) {
          errors.add('${p.displayName}: Önceki ay sınır nöbetiyle çakışma.');
        }
      }
    }
  }
  if (complete) {
    if (m.duties.values.fold<int>(0, (n, ids) => n + ids.length) !=
        m.requiredDuties) {
      errors.add('Aylık toplam nöbet ihtiyacı karşılanmıyor.');
    }
    for (var day = 1; day <= m.days; day++) {
      if ((m.duties[day] ?? []).isEmpty) errors.add('$day. gün nöbetçi yok.');
    }
  }
  return errors.toSet().toList();
}

class GenerationResult {
  const GenerationResult({
    this.month,
    this.errors = const [],
    this.searchLimited = false,
  });
  final ScheduleMonth? month;
  final List<String> errors;
  final bool searchLimited;
}

/// Lexicographic objective: hard feasibility is never traded for any score.
List<int> objective(ScheduleMonth m) {
  final s = statistics(m);
  final people = [...m.people]
    ..sort((a, b) => a.seniorityRank.compareTo(b.seniorityRank));
  int totals = 0,
      seniority = 0,
      categories = 0,
      thuSun = 0,
      pairing = 0,
      third = 0,
      staffing = 0;
  final categoryPreference = List<int>.filled(4, 0);
  for (var i = 0; i < people.length; i++) {
    final p = people[i], stats = s[people[i].personId]!;
    totals += stats.total * stats.total;
    // A larger load on an earlier rank is penalised.
    seniority += (people.length - i) * stats.total;
    for (var c = 0; c < 5; c++) {
      final n = stats.categories[c];
      categories += n * n;
      if (c > 0) {
        categoryPreference[c - 1] += (c == 1 ? i : people.length - i) * n;
      }
    }
    for (var d = 1; d + 3 <= m.days; d++) {
      if (m.date(d).weekday == 4 &&
          (m.duties[d] ?? []).contains(p.personId) &&
          (m.duties[d + 3] ?? []).contains(p.personId)) {
        thuSun++;
      }
    }
  }
  for (final ids in m.duties.values) {
    staffing += ids.length * ids.length;
    final ranks =
        ids.map((id) => people.indexWhere((p) => p.personId == id) + 1).toList()
          ..sort();
    if (ranks.length >= 2) {
      if (ranks.first > 4) pairing += ranks.last;
      pairing += ranks.first;
    }
    if (ranks.length == 3) third += ranks[1];
  }
  return [
    totals,
    seniority,
    categories,
    thuSun,
    ...categoryPreference,
    staffing,
    pairing,
    third,
  ];
}

int compareScore(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

class DutyEngine {
  const DutyEngine({this.nodeLimit = 350000, this.optimizationPasses = 4});
  final int nodeLimit, optimizationPasses;
  GenerationResult generate(ScheduleMonth input) {
    final m = input.clone()
      ..duties.clear()
      ..manuallyEdited.clear();
    for (final p in m.people) {
      for (final d in m.constraints[p.personId]?.must ?? <int>{}) {
        m.duties.putIfAbsent(d, () => []).add(p.personId);
      }
    }
    final pre = validateDuties(m, complete: false);
    if (pre.isNotEmpty) return GenerationResult(errors: pre);
    final people = [...m.people]
      ..sort((a, b) => a.seniorityRank.compareTo(b.seniorityRank));
    var nodes = 0;
    bool limited = false;
    bool feasible(String id, int day, int cap) {
      if ((m.duties[day] ?? []).contains(id) ||
          (m.constraints[id]?.cannot.contains(day) ?? false)) {
        return false;
      }
      var count = 0;
      for (final e in m.duties.entries) {
        if (e.value.contains(id)) {
          count++;
          if ((e.key - day).abs() < 3) return false;
        }
      }
      if (count >= cap) return false;
      return !(m.boundary[id] ?? []).any(
        (b) => m.date(day).difference(calendarDate(b)).inDays < 3,
      );
    }

    // Balanced staffing templates are constraints for the initial CSP only.
    // Different deterministic phases and then flexible person capacities repair dead ends.
    for (final balancedQuotas in [true, false]) {
      for (var phase = 0; phase < m.days; phase++) {
        final target = [
          for (var d = 0; d < m.days; d++)
            m.requiredDuties ~/ m.days +
                (((d + phase) * (m.requiredDuties % m.days)) % m.days <
                        m.requiredDuties % m.days
                    ? 1
                    : 0),
        ];
        // The mechanical pattern above can alias when gcd(days,remainder)>1.
        for (var d = 0; d < m.days; d++) {
          target[d] =
              m.requiredDuties ~/ m.days +
              (((d + 1) * (m.requiredDuties % m.days) + phase) ~/ m.days -
                  (d * (m.requiredDuties % m.days) + phase) ~/ m.days);
        }
        for (var d = 1; d <= m.days; d++) {
          final fixed = (m.duties[d] ?? []).length;
          while (target[d - 1] < fixed) {
            final donor =
                List.generate(m.days, (i) => i)
                    .where(
                      (i) =>
                          i != d - 1 &&
                          target[i] > (m.duties[i + 1] ?? []).length &&
                          target[i] > 1,
                    )
                    .toList()
                  ..sort((a, b) => target[b].compareTo(target[a]));
            if (donor.isEmpty) break;
            target[donor.first]--;
            target[d - 1]++;
          }
        }
        final caps = {
          for (var i = 0; i < people.length; i++)
            people[i].personId: balancedQuotas
                ? m.requiredDuties ~/ people.length +
                      (i >= people.length - m.requiredDuties % people.length
                          ? 1
                          : 0)
                : 8,
        };
        if (m.duties.entries.any((e) => e.value.length > target[e.key - 1])) {
          continue;
        }
        final initial = {
          for (final e in m.duties.entries) e.key: [...e.value],
        };
        bool solve() {
          nodes++;
          if (nodes > nodeLimit) {
            limited = true;
            return false;
          }
          int? day;
          List<String> candidates = [];
          var bestSlack = 999;
          for (var d = 1; d <= m.days; d++) {
            final left = target[d - 1] - (m.duties[d]?.length ?? 0);
            if (left == 0) continue;
            final pool = people
                .where((p) => feasible(p.personId, d, caps[p.personId]!))
                .map((p) => p.personId)
                .toList();
            if (pool.length < left) return false;
            final slack = pool.length - left;
            if (slack < bestSlack) {
              day = d;
              candidates = pool;
              bestSlack = slack;
            }
          }
          if (day == null) return true;
          // Forward checking on each person's achievable remaining capacity.
          if (balancedQuotas) {
            for (final p in people) {
              final count = m.duties.values
                  .where((v) => v.contains(p.personId))
                  .length;
              final possible = [
                for (var d = 1; d <= m.days; d++)
                  if ((m.duties[d]?.length ?? 0) < target[d - 1] &&
                      feasible(p.personId, d, caps[p.personId]!))
                    d,
              ];
              var canAdd = 0, last = -10;
              for (final d in possible) {
                if (d - last >= 3) {
                  canAdd++;
                  last = d;
                }
              }
              if (count + canAdd < caps[p.personId]!) return false;
            }
          }
          final stats = statistics(m);
          final cat = dayCategory(m.date(day));
          candidates.sort((a, b) {
            int cost(String id) {
              final p = m.person(id);
              final s = stats[id]!;
              return s.total * 2000 +
                  s.categories[cat] * 300 +
                  (m.date(day!).weekday == 7 &&
                          (m.duties[day - 3] ?? []).contains(id)
                      ? 800
                      : 0) +
                  (cat == 1 ? -p.seniorityRank : p.seniorityRank);
            }

            final c = cost(a).compareTo(cost(b));
            return c != 0 ? c : a.compareTo(b);
          });
          for (final id in candidates) {
            m.duties.putIfAbsent(day, () => []).add(id);
            if (solve()) return true;
            m.duties[day]!.remove(id);
            if (limited) return false;
          }
          return false;
        }

        if (solve()) {
          _optimize(m);
          for (final ids in m.duties.values) {
            ids.sort(
              (a, b) => m
                  .person(a)
                  .seniorityRank
                  .compareTo(m.person(b).seniorityRank),
            );
          }
          final errors = validateDuties(m);
          return errors.isEmpty
              ? GenerationResult(month: m)
              : GenerationResult(errors: errors);
        }
        m.duties
          ..clear()
          ..addAll(initial);
        if (limited) break;
      }
      if (limited) break;
    }
    // A balanced day template is a soft objective, never an extra hard rule.
    // Repair with a flexible-day CSP before reporting failure.
    final flexible = _flexible(input);
    if (flexible.month != null) return flexible;
    limited = limited || flexible.searchLimited;
    return GenerationResult(
      errors: [
        limited
            ? 'Arama sınırına ulaşıldı; çözüm bulunamadı. Bu sonuç matematiksel imkânsızlık kanıtı değildir. Koşulları veya aylık ihtiyacı gözden geçirin.'
            : 'Çizelge oluşturulamadı: uygun gün kapasitesi, sabit nöbetler, sınır ve maksimum nöbet sınırı birlikte karşılanamıyor.',
      ],
      searchLimited: limited,
    );
  }

  GenerationResult _flexible(ScheduleMonth input) {
    var anyLimited = false;
    for (final balanced in [true, false]) {
      final m = input.clone()
        ..duties.clear()
        ..manuallyEdited.clear();
      final people = [...m.people]
        ..sort((a, b) => a.seniorityRank.compareTo(b.seniorityRank));
      for (final p in people) {
        for (final d in m.constraints[p.personId]?.must ?? <int>{}) {
          m.duties.putIfAbsent(d, () => []).add(p.personId);
        }
      }
      final caps = {
        for (var i = 0; i < people.length; i++)
          people[i].personId: balanced
              ? m.requiredDuties ~/ people.length +
                    (i >= people.length - m.requiredDuties % people.length
                        ? 1
                        : 0)
              : 8,
      };
      var nodes = 0;
      bool can(String id, int day) {
        if ((m.duties[day] ?? []).length >= 3 ||
            (m.constraints[id]?.cannot.contains(day) ?? false)) {
          return false;
        }
        var count = 0;
        for (final e in m.duties.entries) {
          if (e.value.contains(id)) {
            count++;
            if ((e.key - day).abs() < 3) return false;
          }
        }
        return count < caps[id]! &&
            !(m.boundary[id] ?? []).any(
              (b) => m.date(day).difference(calendarDate(b)).inDays < 3,
            );
      }

      bool solve() {
        if (++nodes > nodeLimit) {
          anyLimited = true;
          return false;
        }
        final total = m.duties.values.fold<int>(0, (n, v) => n + v.length);
        if (total == m.requiredDuties) return validateDuties(m).isEmpty;
        final counts = {
          for (final p in people)
            p.personId: m.duties.values
                .where((v) => v.contains(p.personId))
                .length,
        };
        final available = {
          for (final p in people)
            p.personId: [
              for (var d = 1; d <= m.days; d++)
                if (can(p.personId, d)) d,
            ],
        };
        var capacity = 0;
        for (final p in people) {
          var slots = 0, last = -10;
          for (final d in available[p.personId]!) {
            if (d - last >= 3) {
              slots++;
              last = d;
            }
          }
          final need = caps[p.personId]! - counts[p.personId]!;
          if (balanced && slots < need) return false;
          capacity += slots < need ? slots : need;
        }
        if (capacity < m.requiredDuties - total) return false;
        int? emptyDay;
        var minCandidates = 999;
        for (var d = 1; d <= m.days; d++) {
          if ((m.duties[d] ?? []).isNotEmpty) continue;
          final options = people
              .where((p) => available[p.personId]!.contains(d))
              .length;
          if (options == 0) return false;
          if (options < minCandidates) {
            emptyDay = d;
            minCandidates = options;
          }
        }
        final moves = <(String, int)>[];
        if (emptyDay != null) {
          for (final p in people) {
            if (available[p.personId]!.contains(emptyDay)) {
              moves.add((p.personId, emptyDay));
            }
          }
        } else if (balanced) {
          final needing =
              people
                  .where((p) => counts[p.personId]! < caps[p.personId]!)
                  .toList()
                ..sort((a, b) {
                  final c = available[a.personId]!.length.compareTo(
                    available[b.personId]!.length,
                  );
                  return c != 0
                      ? c
                      : a.seniorityRank.compareTo(b.seniorityRank);
                });
          if (needing.isEmpty) return false;
          for (final d in available[needing.first.personId]!) {
            moves.add((needing.first.personId, d));
          }
        } else {
          for (final p in people) {
            for (final d in available[p.personId]!) {
              moves.add((p.personId, d));
            }
          }
        }
        moves.sort((a, b) {
          int cost((String, int) move) =>
              (m.duties[move.$2]?.length ?? 0) * 1000 +
              counts[move.$1]! * 100 +
              m.person(move.$1).seniorityRank;
          final c = cost(a).compareTo(cost(b));
          return c != 0
              ? c
              : (a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
        });
        for (final move in moves) {
          m.duties.putIfAbsent(move.$2, () => []).add(move.$1);
          if (solve()) return true;
          m.duties[move.$2]!.remove(move.$1);
          if (nodes > nodeLimit) break;
        }
        return false;
      }

      if (solve()) {
        _optimize(m);
        for (final ids in m.duties.values) {
          ids.sort(
            (a, b) =>
                m.person(a).seniorityRank.compareTo(m.person(b).seniorityRank),
          );
        }
        return GenerationResult(month: m);
      }
    }
    return GenerationResult(searchLimited: anyLimited);
  }

  void _optimize(ScheduleMonth m) {
    var best = objective(m);
    for (var pass = 0; pass < optimizationPasses; pass++) {
      var changed = false;
      for (var a = 1; a <= m.days; a++) {
        for (var b = a + 1; b <= m.days; b++) {
          // Both single relocations and swaps allow staffing and category repair.
          for (final x in [...m.duties[a] ?? <String>[]]) {
            for (final y in <String?>[null, ...m.duties[b] ?? <String>[]]) {
              if (x == y ||
                  (m.duties[b] ?? []).contains(x) ||
                  (y != null && (m.duties[a] ?? []).contains(y))) {
                continue;
              }
              final oldA = [...m.duties[a] ?? <String>[]],
                  oldB = [...m.duties[b] ?? <String>[]];
              m.duties[a]!.remove(x);
              m.duties.putIfAbsent(b, () => []).add(x);
              if (y != null) {
                m.duties[b]!.remove(y);
                m.duties[a]!.add(y);
              }
              final score = objective(m);
              if (compareScore(score, best) < 0 && validateDuties(m).isEmpty) {
                best = score;
                changed = true;
              } else {
                m.duties[a] = oldA;
                m.duties[b] = oldB;
              }
            }
          }
        }
      }
      if (!changed) break;
    }
  }
}

ScheduleMonth editDuty(
  ScheduleMonth input,
  int from,
  int to,
  String person, {
  String? swap,
}) {
  if (!input.editable) {
    throw StateError('Kesin çizelgeyi önce düzenlemeye açın.');
  }
  if (from == to || !(input.duties[from] ?? []).contains(person)) {
    throw StateError('Taşınacak nöbet bulunamadı.');
  }
  final m = input.clone();
  m.duties[from]!.remove(person);
  m.duties.putIfAbsent(to, () => []).add(person);
  if (swap != null) {
    if (!(m.duties[to] ?? []).remove(swap)) {
      throw StateError('Değiştirilecek nöbet bulunamadı.');
    }
    m.duties[from]!.add(swap);
  }
  final errors = validateDuties(m);
  if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  m.manuallyEdited.addAll([from, to]);
  return m;
}
