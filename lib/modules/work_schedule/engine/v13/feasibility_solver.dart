import '../../domain/models.dart';
import '../../domain/duty_positions.dart';
import 'constraint_validator.dart';
import 'solver_result.dart';

/// Whole-month exhaustive CSP. Cooperative event-loop yielding works on Web and
/// native Dart; deterministic node budgets, never elapsed time, bound the search.
class FeasibilitySolver {
  const FeasibilitySolver({this.nodeLimit = 100000, this.yieldEvery = 32});
  final int nodeLimit, yieldEvery;
  Future<SolverResult> solve(
    ScheduleMonth input, {
    SolverCancellation? cancellation,
    void Function(
      int visitedStates,
      int elapsedMilliseconds,
      int? firstFeasibleMilliseconds,
    )?
    onProgress,
    List<num> Function(List<DutyPositions>)? lexicographicObjective,
  }) async {
    final watch = Stopwatch()..start();
    var nodes = 0, limited = false, seniorProof = false, optimum = false;
    List<DutyPositions> best = [];
    int? firstFeasible;
    var bestCoverage = -1;
    List<num>? bestObjective;
    bool improves(List<num> a, List<num> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          return a[i] < b[i];
        }
      }
      return false;
    }

    final vacancies = <String, VacancyProof>{};
    SolverResult result(
      SolverStatus status, {
      String message = '',
      bool impossible = false,
    }) => SolverResult(
      status: status,
      positions: List.unmodifiable(best),
      visitedStates: nodes,
      elapsedMilliseconds: watch.elapsedMilliseconds,
      firstFeasibleMilliseconds: firstFeasible,
      proofMilliseconds: optimum ? watch.elapsedMilliseconds : null,
      optimalityProven: optimum,
      infeasibilityProven: impossible,
      realSeniorInfeasibilityProven: seniorProof,
      cancelled: cancellation?.cancelled ?? false,
      message: message,
      vacancies: Map.unmodifiable(vacancies),
    );
    try {
      if (nodeLimit < 0 || yieldEvery < 1) {
        return result(SolverStatus.error, message: 'Geçersiz arama bütçesi.');
      }
      final m = input.clone();
      final pre = const ConstraintValidator()
          .validate(m, [])
          .where((e) => !{'MISSING_DAY', 'MISSING_MUST'}.contains(e.code))
          .toList();
      if (pre.isNotEmpty) {
        return result(
          SolverStatus.infeasible,
          message: pre.map((e) => e.message).join('\n'),
          impossible: true,
        );
      }
      final people = m.people.where((p) => p.activeAtCreation).toList()
        ..sort((a, b) {
          final c = a.seniorityRank.compareTo(b.seniorityRank);
          return c != 0 ? c : a.personId.compareTo(b.personId);
        });
      final seniors = people
          .where((p) => p.dutySeniorityGroup == DutySeniorityGroup.senior)
          .toList();
      final juniors = substitutionCandidates(m);
      final used = {for (final p in people) p.personId: <int>{}};
      final rows = <int, DutyPositions>{};
      final filledWitness = <int>{};
      bool available(PersonSnapshot p, int day) {
        final days = used[p.personId]!;
        final c = m.constraints[p.personId] ?? PersonalConstraints();
        if (days.length >= 8 ||
            c.cannot.contains(day) ||
            days.any((d) => (d - day).abs() < 3)) {
          return false;
        }
        if (c.must.any((d) => d != day && (d - day).abs() < 3)) {
          return false;
        }
        if ({...days, ...c.must, day}.length > 8) {
          return false;
        }
        return !(m.boundary[p.personId] ?? []).any(
          (b) => m.date(day).difference(calendarDate(b)).inDays < 3,
        );
      }

      List<DutyPositions> options(
        int day,
        bool substitutions, {
        bool optionalThirds = true,
      }) {
        final date = dateKey(m.date(day));
        final must = people
            .where(
              (p) => m.constraints[p.personId]?.must.contains(day) ?? false,
            )
            .map((p) => p.personId)
            .toSet();
        // Inactive must obligations cannot be satisfied.
        if (m.people.any(
          (p) =>
              !p.activeAtCreation &&
              (m.constraints[p.personId]?.must.contains(day) ?? false),
        )) {
          return [];
        }
        final out = <DutyPositions>[];
        for (final s in [...seniors, if (substitutions) ...juniors]) {
          if (!available(s, day)) {
            continue;
          }
          final js = juniors
              .where((j) => j.personId != s.personId && available(j, day))
              .toList();
          final choices = <List<String>>[
            for (final j in js) [j.personId],
            <String>[],
          ];
          // Third person only when a must obligation requires it, never default.
          for (var a = 0; a < js.length; a++) {
            for (var b = a + 1; b < js.length; b++) {
              if ((lexicographicObjective != null && optionalThirds) ||
                  (must.contains(js[a].personId) &&
                      must.contains(js[b].personId))) {
                choices.add([js[a].personId, js[b].personId]);
              }
            }
          }
          for (final ids in choices) {
            if (!{s.personId, ...ids}.containsAll(must)) {
              continue;
            }
            out.add(
              DutyPositions(
                date: date,
                seniorDutyPersonId: s.personId,
                juniorDutyPersonIds: ids,
                seniorRoleIsSubstitution:
                    s.dutySeniorityGroup == DutySeniorityGroup.junior,
                seniorRoleOriginalGroup: s.dutySeniorityGroup.name,
                juniorVacancyReason: ids.isEmpty
                    ? 'NOT_PROVEN: Aylık kısıtlar altında boş; zorunluluk henüz kanıtlanmadı.'
                    : null,
              ),
            );
          }
        }
        // Least-used values are a feasibility heuristic, not a fairness objective.
        out.sort((a, b) {
          if (a.seniorRoleIsSubstitution || b.seniorRoleIsSubstitution) {
            final actual = (a.seniorRoleIsSubstitution ? 1 : 0).compareTo(
              b.seniorRoleIsSubstitution ? 1 : 0,
            );
            if (actual != 0) {
              return actual;
            }
            final rank = people
                .firstWhere((p) => p.personId == a.seniorDutyPersonId)
                .seniorityRank
                .compareTo(
                  people
                      .firstWhere((p) => p.personId == b.seniorDutyPersonId)
                      .seniorityRank,
                );
            if (rank != 0) {
              return rank;
            }
          }
          final senior = used[a.seniorDutyPersonId]!.length.compareTo(
            used[b.seniorDutyPersonId]!.length,
          );
          if (senior != 0) {
            return senior;
          }
          final filled = b.juniorDutyPersonIds.length.compareTo(
            a.juniorDutyPersonIds.length,
          );
          if (filled != 0) {
            return filled;
          }
          final loadA = a.juniorDutyPersonIds.fold<int>(
            0,
            (sum, id) => sum + used[id]!.length,
          );
          final loadB = b.juniorDutyPersonIds.fold<int>(
            0,
            (sum, id) => sum + used[id]!.length,
          );
          final load = loadA.compareTo(loadB);
          if (load != 0) {
            return load;
          }
          final rank = people
              .firstWhere((p) => p.personId == a.seniorDutyPersonId)
              .seniorityRank
              .compareTo(
                people
                    .firstWhere((p) => p.personId == b.seniorDutyPersonId)
                    .seniorityRank,
              );
          if (rank != 0) {
            return rank;
          }
          return a.juniorDutyPersonIds
              .join(',')
              .compareTo(b.juniorDutyPersonIds.join(','));
        });
        return out;
      }

      Future<bool> search(
        bool substitutions, {
        bool firstOnly = false,
        int? forceDay,
      }) async {
        if (nodes >= nodeLimit || (cancellation?.cancelled ?? false)) {
          limited = true;
          return false;
        }
        nodes++;
        if (nodes % yieldEvery == 0) {
          onProgress?.call(nodes, watch.elapsedMilliseconds, firstFeasible);
          await Future<void>.delayed(Duration.zero);
        }
        if (cancellation?.cancelled ?? false) {
          limited = true;
          return false;
        }
        if (rows.length == m.days) {
          final candidate = [for (var d = 1; d <= m.days; d++) rows[d]!];
          final errors = const ConstraintValidator().validate(m, candidate);
          if (errors.isNotEmpty) {
            throw StateError('Son doğrulama başarısız: ${errors.first.code}');
          }
          for (var d = 1; d <= m.days; d++) {
            if (rows[d]!.juniorDutyPersonIds.isNotEmpty) {
              filledWitness.add(d);
            }
          }
          firstFeasible ??= watch.elapsedMilliseconds;
          final coverage = candidate
              .where((r) => r.juniorDutyPersonIds.isNotEmpty)
              .length;
          final score = lexicographicObjective?.call(candidate);
          if (score != null
              ? (bestObjective == null || improves(score, bestObjective!))
              : coverage > bestCoverage) {
            bestObjective = score;
            best = candidate;
            bestCoverage = coverage;
          }
          return true;
        }
        var chosen = 0;
        List<DutyPositions>? domain;
        var possibleCoverage = rows.values
            .where((r) => r.juniorDutyPersonIds.isNotEmpty)
            .length;
        for (var day = 1; day <= m.days; day++) {
          if (rows.containsKey(day)) {
            continue;
          }
          var opts = options(day, substitutions, optionalThirds: !firstOnly);
          if (day == forceDay) {
            opts = opts.where((r) => r.juniorDutyPersonIds.isNotEmpty).toList();
          }
          if (opts.isEmpty) {
            return false;
          }
          if (opts.any((r) => r.juniorDutyPersonIds.isNotEmpty)) {
            possibleCoverage++;
          }
          if (domain == null || opts.length < domain.length) {
            chosen = day;
            domain = opts;
          }
        }
        if (lexicographicObjective == null &&
            !firstOnly &&
            possibleCoverage <= bestCoverage) {
          return false;
        }
        var found = false;
        for (final row in domain!) {
          rows[chosen] = row;
          final ids = [row.seniorDutyPersonId!, ...row.juniorDutyPersonIds];
          for (final id in ids) {
            used[id]!.add(chosen);
          }
          final success = await search(
            substitutions,
            firstOnly: firstOnly,
            forceDay: forceDay,
          );
          for (final id in ids) {
            used[id]!.remove(chosen);
          }
          rows.remove(chosen);
          found = found || success;
          if (limited || (success && firstOnly)) {
            return found;
          }
        }
        return found;
      }

      await Future<void>.delayed(Duration.zero);
      await search(false, firstOnly: true);
      if (limited) {
        return result(SolverStatus.searchLimitReached);
      }
      if (best.isEmpty) {
        seniorProof = true;
        await search(true, firstOnly: true);
        if (limited) {
          return result(SolverStatus.searchLimitReached);
        }
        if (best.isEmpty) {
          return result(SolverStatus.infeasible, impossible: true);
        }
      }
      if (lexicographicObjective != null) {
        await search(seniorProof);
        optimum = !limited;
        return result(
          limited ? SolverStatus.searchLimitReached : SolverStatus.feasible,
        );
      }
      // An admissible capacity bound proves the maximum number of covered days.
      final upperBound = (juniors.length * 8).clamp(0, m.days);
      if (bestCoverage < upperBound) {
        await search(seniorProof);
      }
      optimum = !limited || bestCoverage == upperBound;
      if (bestCoverage == upperBound) {
        optimum = true;
      }
      final saved = List<DutyPositions>.from(best);
      for (final row in saved.where((r) => r.juniorDutyPersonIds.isEmpty)) {
        final day = int.parse(row.date.substring(8));
        if (filledWitness.contains(day)) {
          vacancies[row.date] = VacancyProof.notProven;
          continue;
        }
        if (limited) {
          vacancies[row.date] = VacancyProof.notProven;
          continue;
        }
        final exists = await search(
          seniorProof,
          firstOnly: true,
          forceDay: day,
        );
        vacancies[row.date] = !exists && !limited
            ? VacancyProof.provenUnavoidable
            : VacancyProof.notProven;
      }
      best = saved
          .map(
            (r) => r.juniorDutyPersonIds.isNotEmpty
                ? r
                : DutyPositions(
                    date: r.date,
                    seniorDutyPersonId: r.seniorDutyPersonId,
                    juniorDutyPersonIds: [],
                    seniorRoleIsSubstitution: r.seniorRoleIsSubstitution,
                    seniorRoleOriginalGroup: r.seniorRoleOriginalGroup,
                    juniorVacancyReason:
                        vacancies[r.date] == VacancyProof.provenUnavoidable
                        ? 'PROVEN_UNAVOIDABLE: Bu tarihin junior pozisyonu için geçerli aylık çözüm yok.'
                        : 'NOT_PROVEN: Bu tarihte boşluk zorunluluğu kanıtlanmadı.',
                  ),
          )
          .toList();
      return result(
        limited ? SolverStatus.searchLimitReached : SolverStatus.feasible,
      );
    } catch (e) {
      return result(
        SolverStatus.error,
        message: 'Çözüm sırasında teknik hata: $e',
      );
    }
  }
}
