import '../../../core/design/akys_design_system.dart';
import 'compact_duty_card.dart';
import 'solver_status_summary.dart';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/duty_positions.dart';
import '../engine/v13/fairness_optimizer.dart';
import '../engine/v13/solver_result.dart';
import '../engine/v13/constraint_validator.dart';

const v13SolverEnabled = bool.fromEnvironment(
  'AKYS_V13_SOLVER',
  defaultValue: false,
);

class V13SolverPanel extends StatefulWidget {
  const V13SolverPanel({
    required this.month,
    required this.onSave,
    this.enabled = v13SolverEnabled,
    super.key,
  });
  final ScheduleMonth month;
  final Future<bool> Function(ScheduleMonth) onSave;
  final bool enabled;
  @override
  State<V13SolverPanel> createState() => _V13SolverPanelState();
}

class _V13SolverPanelState extends State<V13SolverPanel> {
  SolverCancellation? cancellation;
  FairnessResult? result;
  List<DutyPositions>? preview;
  bool running = false, manual = false, saving = false;
  int budget = 2000, nodes = 0, elapsed = 0;
  int? firstMs;
  String? error;
  @override
  void initState() {
    super.initState();
    preview = widget.month.dutyPositions;
  }

  @override
  void dispose() {
    cancellation?.cancel();
    super.dispose();
  }

  Future<void> search() async {
    if (!widget.month.boundaryConfirmed) {
      setState(() => error = 'Önce önceki ay sınır nöbetlerini doğrulayın.');
      return;
    }
    cancellation = SolverCancellation();
    setState(() {
      running = true;
      error = null;
      nodes = 0;
      elapsed = 0;
      firstMs = null;
    });
    final r = await FairnessOptimizer(nodeLimit: budget, yieldEvery: 8)
        .optimize(
          widget.month,
          cancellation: cancellation,
          onProgress: (n, ms, first) {
            if (mounted) {
              setState(() {
                nodes = n;
                elapsed = ms;
                firstMs = first;
              });
            }
          },
        );
    if (!mounted) return;
    setState(() {
      running = false;
      result = r;
      nodes = r.solver.visitedStates;
      elapsed = r.solver.elapsedMilliseconds;
      firstMs = r.solver.firstFeasibleMilliseconds;
      if (r.solver.hasValidIncumbent) {
        preview = r.solver.positions;
        manual = false;
      } else {
        error = r.solver.message.isNotEmpty
            ? r.solver.message
            : r.solver.statusCode;
      }
    });
  }

  Future<void> edit(int index) async {
    final row = preview![index];
    String? senior = row.seniorDutyPersonId;
    final juniors = [...row.juniorDutyPersonIds];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${row.date} pozisyonları'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: senior,
                  isExpanded: true,
                  items: [
                    for (final p in widget.month.people)
                      DropdownMenuItem(
                        value: p.personId,
                        child: Text(p.displayName),
                      ),
                  ],
                  onChanged: (v) => setDialog(() => senior = v),
                ),
                const Text('Junior pozisyonları (en fazla iki)'),
                for (final p in widget.month.people.where(
                  (p) => p.dutySeniorityGroup == DutySeniorityGroup.junior,
                ))
                  CheckboxListTile(
                    title: Text(p.displayName),
                    value: juniors.contains(p.personId),
                    onChanged: (v) => setDialog(() {
                      if (v == true) {
                        juniors.add(p.personId);
                      } else {
                        juniors.remove(p.personId);
                      }
                    }),
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
              child: const Text('Önizlemeye Uygula'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final p = widget.month.person(senior!);
    final next = [...preview!];
    next[index] = DutyPositions(
      date: row.date,
      seniorDutyPersonId: senior,
      juniorDutyPersonIds: juniors,
      seniorRoleIsSubstitution:
          p.dutySeniorityGroup == DutySeniorityGroup.junior,
      seniorRoleOriginalGroup: p.dutySeniorityGroup.name,
      juniorVacancyReason: juniors.isEmpty
          ? 'NOT_PROVEN: Manuel boşluk; zorunluluğu kanıtlanmadı.'
          : null,
    );
    setState(() {
      preview = next
          .map(
            (r) => r.juniorDutyPersonIds.isNotEmpty
                ? r
                : DutyPositions(
                    date: r.date,
                    seniorDutyPersonId: r.seniorDutyPersonId,
                    juniorDutyPersonIds: [],
                    seniorRoleIsSubstitution: r.seniorRoleIsSubstitution,
                    seniorRoleOriginalGroup: r.seniorRoleOriginalGroup,
                    juniorVacancyReason: 'NOT_PROVEN: Manuel değişiklikten sonra yeniden doğrulama gerekir.',
                  ),
          )
          .toList();
      manual = true;
      result = null;
    });
  }

  Future<void> save() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('V1.3 taslağını kaydet'),
        content: const Text(
          'Önizleme mevcut taslak nöbetlerini değiştirecek. Kesinleştirme veya yayımlama yapılmayacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Taslağı Kaydet'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final next = widget.month.clone();
    next.dutyPositions = List.from(preview!);
    next.duties.clear();
    for (final r in preview!) {
      next.duties[int.parse(r.date.substring(8))] = [
        r.seniorDutyPersonId!,
        ...r.juniorDutyPersonIds,
      ];
    }
    next.requiredDuties = next.duties.values.fold(0, (n, v) => n + v.length);
    next.engineVersion = '1.3.0';
    next.v13Diagnostics = {
      'status': manual
          ? 'MANUALLY_EDITED'
          : result?.solver.statusCode ?? 'RELOADED',
      'optimalityProven': !manual && (result?.optimalityProven ?? false),
      'hierarchyProven':
          !manual &&
          (result?.stages['monthlyHierarchy']?.optimalityProven ?? false),
      'stages': {
        if (!manual && result != null)
          for (final e in result!.stages.entries)
            e.key: {
              'values': e.value.values,
              'optimalityProven': e.value.optimalityProven,
            },
      },
      'visitedStates': nodes,
      'elapsedMilliseconds': elapsed,
      'firstFeasibleMilliseconds': firstMs,
    };
    setState(() => saving = true);
    try {
      await widget.onSave(next);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final issues = preview == null
        ? <ConstraintIssue>[]
        : const ConstraintValidator().validate(widget.month, preview!);
    final report = preview != null && issues.isEmpty
        ? FairnessReport(widget.month, preview!)
        : null;
    final hierarchyProven =
        !manual &&
        (result?.stages['monthlyHierarchy']?.optimalityProven ??
            (identical(preview, widget.month.dutyPositions) &&
                widget.month.v13Diagnostics?['hierarchyProven'] == true));
    final optimal =
        !manual &&
        (result?.optimalityProven ??
            (identical(preview, widget.month.dutyPositions) &&
                widget.month.v13Diagnostics?['optimalityProven'] == true));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AkysSectionHeader(title: 'V1.3 deneysel nöbet motoru'),
            if (widget.month.dutyPositions == null)
              const Text(
                'Eski ayda pozisyon bilgisi yok; mevcut kayıt tahminle dönüştürülmez. Yeni arama ayrı önizleme üretir.',
              ),
            DropdownButton<int>(
              isExpanded: true,
              value: budget,
              items: [
                for (final n in [500, 2000, 10000])
                  DropdownMenuItem(value: n, child: Text('$n durum bütçesi')),
              ],
              onChanged: running ? null : (v) => setState(() => budget = v!),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: running || saving || !widget.month.editable
                      ? null
                      : search,
                  child: const Text('V1.3 Önizleme Oluştur'),
                ),
                if (running)
                  OutlinedButton(
                    onPressed: () => cancellation?.cancel(),
                    child: const Text('Aramayı İptal Et'),
                  ),
              ],
            ),
            Text(
              'Ziyaret: $nodes / $budget · Süre: $elapsed ms · İlk çözüm: ${firstMs ?? '—'} ms',
            ),
            if (running) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            SolverStatusSummary(
              valid: preview == null ? null : issues.isEmpty,
              hierarchyProven: hierarchyProven,
              optimal: optimal,
              searchLimited:
                  result?.solver.status == SolverStatus.searchLimitReached,
              finished: result != null && !running,
            ),
            if (preview != null) ...[
              for (final e in issues)
                Text('${e.code} ${e.date ?? ''}: ${e.message}'),
              if (report != null)
                ExpansionTile(
                  title: Text(
                    'Kıdem ve adalet raporu · İhlal: ${report.hierarchyViolations} · Boş junior: ${report.vacancies} · Geçici senior: ${report.substitutions}',
                  ),
                  children: [
                    for (final p in report.people.values)
                      ListTile(
                        title: Text(
                          '${p.person.displayName} · ${p.person.dutySeniorityGroup.name} K${p.person.seniorityRank}',
                        ),
                        subtitle: Text(
                          'Toplam ${p.total} · Senior ${p.seniorRoles} / Junior ${p.juniorRoles} · Tek ${p.solo} / Eşli ${p.paired}\nPzt–Çar / Per / Cum / Cmt / Paz: ${p.categories.join(' / ')} · Tatil ${p.holidays}\nPuan ${p.points} · Ortalama ${p.average.toStringAsFixed(2)}',
                        ),
                      ),
                  ],
                ),
              ExpansionTile(
                title: const Text('Günlük senior / junior pozisyonları'),
                children: [
                  for (var i = 0; i < preview!.length; i++)
                    CompactDutyCard(
                      key: ValueKey('preview-${preview![i].date}'),
                      month: widget.month,
                      day: int.parse(preview![i].date.substring(8)),
                      position: preview![i],
                      positionsKnown: true,
                      errors: [
                        for (final e in issues)
                          if (e.date == preview![i].date || e.date == null)
                            e.message,
                      ],
                      onEdit: running || saving || !widget.month.editable
                          ? null
                          : () => edit(i),
                    ),
                ],
              ),
              FilledButton(
                onPressed:
                    running ||
                        saving ||
                        !widget.month.editable ||
                        issues.isNotEmpty
                    ? null
                    : save,
                child: const Text('V1.3 Taslağını Kaydet'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
