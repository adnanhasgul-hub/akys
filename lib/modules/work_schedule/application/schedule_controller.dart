import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/schedule_repository.dart';
import '../domain/models.dart';
import '../engine/duty_engine.dart';

Map<String, dynamic> generateInBackground(Map<String, dynamic> json) {
  final result = const DutyEngine().generate(ScheduleMonth.fromJson(json));
  return {'month': result.month?.toJson(), 'errors': result.errors};
}

class ScheduleController extends ChangeNotifier {
  ScheduleController(this.repository);
  final ScheduleRepository repository;
  List<Personnel> personnel = [];
  List<ScheduleMonth> months = [];
  String? selectedId, error, notice;
  bool loading = true, busy = false;
  bool _disposed = false;
  StreamSubscription<List<Personnel>>? _peopleSub;
  StreamSubscription<List<ScheduleMonth>>? _monthsSub;
  ScheduleMonth? get month {
    for (final m in months) {
      if (m.id == selectedId) return m;
    }
    return null;
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> run(Future<void> Function() action, {String? success}) async {
    if (busy) return false;
    busy = true;
    error = null;
    notice = null;
    emit();
    try {
      await action();
      if (success != null) notice = success;
      return true;
    } catch (e) {
      error = e is ScheduleConflict ? e.message : 'İşlem tamamlanamadı. Bağlantınızı ve yönetici yetkinizi kontrol edip yeniden deneyin.';
      return false;
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() async {
    loading = true;
    emit();
    await _peopleSub?.cancel();
    await _monthsSub?.cancel();
    await run(() async {
      await repository.initialize();
      _peopleSub = repository.watchPersonnel().listen(
        (list) {
          personnel = list;
          emit();
        },
        onError: (Object e) {
          error = 'Personel yüklenemedi. Yeniden deneyin.';
          emit();
        },
      );
      _monthsSub = repository.watchMonths().listen(
        (list) {
          months = list;
          loading = false;
          emit();
        },
        onError: (Object e) {
          loading = false;
          error = 'Aylar yüklenemedi. Bağlantınızı ve yetkinizi kontrol edin.';
          emit();
        },
      );
    });
    if (error != null) {
      loading = false;
      emit();
    }
  }

  void select(String id) {
    selectedId = id;
    error = null;
    notice = null;
    emit();
  }

  Future<bool> updatePeople(List<Personnel> after) => run(
    () => repository.replacePersonnel(personnel, after),
    success: 'Personel kaydedildi. Geçmiş aylar değişmedi.',
  );
  Future<bool> addPerson(String name) {
    final now = DateTime.now().toUtc().toIso8601String();
    return updatePeople([
      ...personnel,
      Personnel(
        id: randomId(),
        displayName: name.trim(),
        seniorityRank: personnel.length + 1,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
  }

  Future<bool> createMonth(int year, int month, int total) => run(() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final active = personnel.where((p) => p.active).toList();
    if (active.isEmpty) {
      throw const ScheduleConflict('Önce aktif personel ekleyin.');
    }
    final next = ScheduleMonth(
      year: year,
      month: month,
      people: [
        for (final p in active)
          PersonSnapshot(p.id, p.displayName, p.seniorityRank),
      ],
      createdAt: now,
      updatedAt: now,
      requiredDuties: total,
    );
    final prev = DateTime.utc(year, month, 0);
    final previous = await repository.loadMonth(
      '${prev.year}-${prev.month.toString().padLeft(2, '0')}',
    );
    if (previous != null && previous.duties.isNotEmpty) {
      next.boundarySource = 'previous_month';
      next.boundaryConfirmed = true;
      for (final p in next.people) {
        next.boundary[p.personId] = [
          for (final e in previous.duties.entries)
            if (e.value.contains(p.personId)) dateKey(previous.date(e.key)),
        ];
      }
    }
    final saved = await repository.saveMonth(next, create: true);
    _accept(saved);
    selectedId = saved.id;
  }, success: 'Ay oluşturuldu. Personel snapshot’ı alındı.');
  void _accept(ScheduleMonth saved) {
    months = [
      for (final m in months)
        if (m.id != saved.id) m,
      saved,
    ]..sort((a, b) => b.id.compareTo(a.id));
  }

  Future<bool> save(ScheduleMonth next, {String? success}) => run(() async {
    _accept(await repository.saveMonth(next));
  }, success: success ?? 'Değişiklikler kaydedildi.');
  Future<bool> generate() => run(() async {
    final current = month;
    if (current == null || !current.editable) {
      throw const ScheduleConflict('Önce taslak ay seçin.');
    }
    if (!current.boundaryConfirmed) {
      throw const ScheduleConflict(
        'Önce önceki ay sınır nöbetlerini doğrulayın.',
      );
    }
    final result = await compute(generateInBackground, current.toJson());
    if (result['month'] == null) {
      throw ScheduleConflict(
        'Çizelge oluşturulamadı\n${(result['errors'] as List).join('\n')}',
      );
    }
    _accept(
      await repository.saveMonth(
        ScheduleMonth.fromJson(
          Map<String, dynamic>.from(result['month'] as Map),
        ),
      ),
    );
  }, success: 'Nöbet çizelgesi oluşturuldu ve kaydedildi.');
  Future<bool> move(int from, int to, String id, {String? swap}) =>
      run(() async {
        final current = month!;
        ScheduleMonth next;
        try {
          next = editDuty(current, from, to, id, swap: swap);
        } on StateError catch (e) {
          throw ScheduleConflict(e.message.toString());
        }
        final worse = compareScore(objective(next), objective(current)) > 0;
        _accept(await repository.saveMonth(next));
        notice = worse
            ? 'Taşıma kaydedildi. Uyarı: adalet / eşleşme puanı kötüleşti.'
            : 'Taşıma kaydedildi.';
      });
  Future<bool> changeStatus(MonthStatus status) => run(
    () async {
      final next = month!.clone();
      if (status != MonthStatus.draft) {
        final errors = validateDuties(next);
        if (errors.isNotEmpty) throw ScheduleConflict(errors.join('\n'));
      }
      next.status = status;
      _accept(await repository.saveMonth(next));
    },
    success: status == MonthStatus.draft
        ? 'Düzenlemeye açıldı; eski paylaşım bağlantıları iptal edildi.'
        : 'Ayın durumu kaydedildi.',
  );
  Future<String?> share() async {
    String? token;
    await run(() async {
      token = await repository.share(month!);
      final fresh = await repository.loadMonth(month!.id);
      if (fresh != null) _accept(fresh);
    });
    return token;
  }

  Future<bool> revoke(String token) => run(() async {
    await repository.revoke(month!, token);
    final fresh = await repository.loadMonth(month!.id);
    if (fresh != null) _accept(fresh);
  }, success: 'Paylaşım iptal edildi.');
  @override
  void dispose() {
    _disposed = true;
    _peopleSub?.cancel();
    _monthsSub?.cancel();
    super.dispose();
  }
}
