import 'dart:math';

import 'difficulty.dart';

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime calendarDate(String value) {
  final d = DateTime.parse(value);
  return DateTime.utc(d.year, d.month, d.day);
}

const monthNames = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
const dayNames = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
String randomId() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

enum DutySeniorityGroup { senior, junior }

String dutyGroupLabel(DutySeniorityGroup group) => switch (group) {
  DutySeniorityGroup.senior => 'Kıdemli',
  DutySeniorityGroup.junior => 'Çömez',
};

/// Legacy-only migration; explicit groups never follow rank or name changes.
DutySeniorityGroup legacyDutyGroup(int rank) =>
    rank <= 4 ? DutySeniorityGroup.senior : DutySeniorityGroup.junior;
DutySeniorityGroup readDutyGroup(Object? value, int rank) => switch (value) {
  'senior' => DutySeniorityGroup.senior,
  'junior' => DutySeniorityGroup.junior,
  _ => legacyDutyGroup(rank),
};

class Personnel {
  const Personnel({
    required this.id,
    required this.displayName,
    required this.seniorityRank,
    this.active = true,
    this.profession = 'resident_physician',
    DutySeniorityGroup? dutySeniorityGroup,
    required this.createdAt,
    required this.updatedAt,
  }) : dutySeniorityGroup =
           dutySeniorityGroup ??
           (seniorityRank <= 4
               ? DutySeniorityGroup.senior
               : DutySeniorityGroup.junior);
  final String id, displayName, profession, createdAt, updatedAt;
  final int seniorityRank;
  final bool active;
  final DutySeniorityGroup dutySeniorityGroup;
  Personnel copy({
    String? name,
    int? rank,
    bool? active,
    DutySeniorityGroup? dutySeniorityGroup,
  }) => Personnel(
    id: id,
    displayName: name ?? displayName,
    seniorityRank: rank ?? seniorityRank,
    active: active ?? this.active,
    profession: profession,
    dutySeniorityGroup: dutySeniorityGroup ?? this.dutySeniorityGroup,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'profession': profession,
    'dutySeniorityGroup': dutySeniorityGroup.name,
    'active': active,
    'seniorityRank': seniorityRank,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
  factory Personnel.fromJson(Map<String, dynamic> j) => Personnel(
    id: j['id'] as String,
    displayName: j['displayName'] as String,
    seniorityRank: j['seniorityRank'] as int,
    active: j['active'] as bool,
    dutySeniorityGroup: readDutyGroup(
      j['dutySeniorityGroup'],
      j['seniorityRank'] as int,
    ),
    profession: j['profession'] as String,
    createdAt: j['createdAt'] as String,
    updatedAt: j['updatedAt'] as String,
  );
}

const initialNames = [
  'Dr. Adnan Hasgül',
  'Dr. Muhammed Raşit Erikçi',
  'Dr. Burak Ergen',
  'Dr. Tuncay Güngör',
  'Dr. Mehmet Argüz',
  'Dr. Muhammed Yasin Dülek',
  'Dr. Rabia Düman',
];
List<Personnel> seedPersonnel(List<Personnel> existing, String now) =>
    existing.isNotEmpty
    ? existing
    : [
        for (var i = 0; i < initialNames.length; i++)
          Personnel(
            id: 'initial-resident-${i + 1}',
            displayName: initialNames[i],
            seniorityRank: i + 1,
            dutySeniorityGroup: i < 4
                ? DutySeniorityGroup.senior
                : DutySeniorityGroup.junior,
            createdAt: now,
            updatedAt: now,
          ),
      ];
List<Personnel> reorderPersonnel(List<Personnel> people, List<String> ids) {
  if (ids.length != people.length ||
      ids.toSet().length != ids.length ||
      !ids.toSet().containsAll(people.map((p) => p.id))) {
    throw ArgumentError('Personel listesi değişti; yeniden yükleyin.');
  }
  return [
    for (var i = 0; i < ids.length; i++)
      people.firstWhere((p) => p.id == ids[i]).copy(rank: i + 1),
  ];
}

class PersonSnapshot {
  const PersonSnapshot(
    this.personId,
    this.displayName,
    this.seniorityRank, {
    this.activeAtCreation = true,
    DutySeniorityGroup? dutySeniorityGroup,
  }) : dutySeniorityGroup =
           dutySeniorityGroup ??
           (seniorityRank <= 4
               ? DutySeniorityGroup.senior
               : DutySeniorityGroup.junior);
  final String personId, displayName;
  final int seniorityRank;
  final bool activeAtCreation;
  final DutySeniorityGroup dutySeniorityGroup;
  Map<String, dynamic> toJson() => {
    'personId': personId,
    'displayName': displayName,
    'seniorityRank': seniorityRank,
    'activeAtCreation': activeAtCreation,
    'dutySeniorityGroup': dutySeniorityGroup.name,
  };
  factory PersonSnapshot.fromJson(Map<String, dynamic> j) => PersonSnapshot(
    j['personId'] as String,
    j['displayName'] as String,
    j['seniorityRank'] as int,
    activeAtCreation: j['activeAtCreation'] as bool,
    dutySeniorityGroup: readDutyGroup(
      j['dutySeniorityGroup'],
      j['seniorityRank'] as int,
    ),
  );
}

class PersonalConstraints {
  PersonalConstraints({Set<int>? cannot, Set<int>? must})
    : cannot = cannot ?? {},
      must = must ?? {};
  final Set<int> cannot, must;
  Map<String, dynamic> toJson() => {
    'cannot': cannot.toList()..sort(),
    'must': must.toList()..sort(),
  };
  factory PersonalConstraints.fromJson(Map<String, dynamic> j) =>
      PersonalConstraints(
        cannot: Set<int>.from(j['cannot'] as List),
        must: Set<int>.from(j['must'] as List),
      );
}

enum MonthStatus { draft, finalised, published, archived }

String statusLabel(MonthStatus status) => switch (status) {
  MonthStatus.draft => 'Taslak',
  MonthStatus.finalised => 'Kesin',
  MonthStatus.published => 'Paylaşıldı',
  MonthStatus.archived => 'Arşiv',
};

enum ClinicTask { outpatient, consultation, ward, intensiveCare, discharge }

String taskLabel(ClinicTask task) => switch (task) {
  ClinicTask.outpatient => 'Poliklinik',
  ClinicTask.consultation => 'Konsültasyon',
  ClinicTask.ward => 'Servis',
  ClinicTask.intensiveCare => 'Yoğun Bakım',
  ClinicTask.discharge => 'Epikriz Düzenleme',
};

class TaskAssignment {
  const TaskAssignment(this.primary, this.backup);
  final String primary, backup;
  Map<String, dynamic> toJson() => {'primary': primary, 'backup': backup};
  factory TaskAssignment.fromJson(Map<String, dynamic> j) =>
      TaskAssignment(j['primary'] as String, j['backup'] as String);
}

class TaskOverride {
  const TaskOverride(this.date, this.task, this.personId, {this.reason = ''});
  final String date, personId, reason;
  final ClinicTask task;
  String get key => '$date|${task.name}';
  Map<String, dynamic> toJson() => {
    'date': date,
    'task': task.name,
    'personId': personId,
    'reason': reason,
  };
  factory TaskOverride.fromJson(Map<String, dynamic> j) => TaskOverride(
    j['date'] as String,
    ClinicTask.values.byName(j['task'] as String),
    j['personId'] as String,
    reason: j['reason'] as String? ?? '',
  );
}

class ScheduleMonth {
  ScheduleMonth({
    required this.year,
    required this.month,
    required this.people,
    required this.createdAt,
    required this.updatedAt,
    this.status = MonthStatus.draft,
    this.revision = 0,
    this.schemaVersion = 3,
    this.difficultySchemaVersion = 0,
    this.difficultySettingsSnapshot,
    List<HolidayDay>? holidayCalendarSnapshot,
    Map<String, int>? holidayDifficultyOverrides,
    this.engineVersion = '1.1.0',
    List<Map<String, dynamic>>? snapshotGroupUpdates,
    int? requiredDuties,
    this.publishedAt,
    this.boundarySource = 'manual',
    this.boundaryConfirmed = false,
    Map<String, PersonalConstraints>? constraints,
    Map<String, List<String>>? boundary,
    Map<int, List<String>>? duties,
    Set<int>? manuallyEdited,
    Map<ClinicTask, TaskAssignment>? tasks,
    Map<String, TaskOverride>? overrides,
    List<String>? shareTokens,
  }) : requiredDuties =
           requiredDuties ??
           min(people.length * 8, DateTime.utc(year, month + 1, 0).day * 3),
       constraints =
           constraints ??
           {for (final p in people) p.personId: PersonalConstraints()},
       boundary = boundary ?? {},
       duties = duties ?? {},
       manuallyEdited = manuallyEdited ?? {},
       tasks = tasks ?? {},
       overrides = overrides ?? {},
       shareTokens = shareTokens ?? [],
       snapshotGroupUpdates = snapshotGroupUpdates ?? [],
       holidayCalendarSnapshot = List.unmodifiable(
         holidayCalendarSnapshot ?? <HolidayDay>[],
       ),
       holidayDifficultyOverrides = Map.unmodifiable(
         holidayDifficultyOverrides ?? <String, int>{},
       );
  final int year, month;
  final List<PersonSnapshot> people;
  final String createdAt;
  String updatedAt, boundarySource;
  bool boundaryConfirmed;
  String? publishedAt;
  int revision, requiredDuties;
  int schemaVersion;
  final int difficultySchemaVersion;
  final DifficultySettings? difficultySettingsSnapshot;
  final List<HolidayDay> holidayCalendarSnapshot;
  final Map<String, int> holidayDifficultyOverrides;
  DifficultySnapshot get difficulty => DifficultySnapshot(
    settings: difficultySettingsSnapshot ?? DifficultySettings.defaults(),
    calendar: holidayCalendarSnapshot,
    overrides: holidayDifficultyOverrides,
  );
  int difficultyScore(int day) => difficulty.score(date(day));
  bool isHoliday(int day) => difficulty.holiday(date(day)) != null;
  String engineVersion;
  final List<Map<String, dynamic>> snapshotGroupUpdates;
  MonthStatus status;
  final Map<String, PersonalConstraints> constraints;
  final Map<String, List<String>> boundary;
  final Map<int, List<String>> duties;
  final Set<int> manuallyEdited;
  final Map<ClinicTask, TaskAssignment> tasks;
  final Map<String, TaskOverride> overrides;
  final List<String> shareTokens;
  String get id =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
  String get title => '$year ${monthNames[month - 1]}';
  int get days => DateTime.utc(year, month + 1, 0).day;
  bool get editable => status == MonthStatus.draft;
  DateTime date(int day) => DateTime.utc(year, month, day);
  PersonSnapshot person(String id) =>
      people.firstWhere((p) => p.personId == id);
  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'difficultySchemaVersion': difficultySchemaVersion,
    'difficultySettingsSnapshot': difficultySettingsSnapshot?.toJson(),
    'holidayCalendarSnapshot': holidayCalendarSnapshot
        .map((h) => h.toJson())
        .toList(),
    'holidayDifficultyOverrides': holidayDifficultyOverrides,
    'engineVersion': engineVersion,
    'snapshotGroupUpdates': snapshotGroupUpdates,
    'year': year,
    'month': month,
    'status': status == MonthStatus.finalised ? 'final' : status.name,
    'revision': revision,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'publishedAt': publishedAt,
    'requiredDuties': requiredDuties,
    'personnelSnapshot': people.map((p) => p.toJson()).toList(),
    'constraints': constraints.map((k, v) => MapEntry(k, v.toJson())),
    'boundaryConditions': boundary,
    'boundarySource': boundarySource,
    'boundaryConfirmed': boundaryConfirmed,
    'duties': duties.map(
      (k, v) => MapEntry('$k', {
        'date': dateKey(date(k)),
        'personIds': v,
        'source': manuallyEdited.contains(k) ? 'manual' : 'generated',
        'manuallyEdited': manuallyEdited.contains(k),
      }),
    ),
    'tasks': tasks.map((k, v) => MapEntry(k.name, v.toJson())),
    'overrides': overrides.map((k, v) => MapEntry(k, v.toJson())),
    'shareTokens': shareTokens,
  };
  ScheduleMonth clone() => ScheduleMonth.fromJson(toJson());
  factory ScheduleMonth.fromJson(Map<String, dynamic> j) => ScheduleMonth(
    year: j['year'] as int,
    month: j['month'] as int,
    people: [
      for (final p in j['personnelSnapshot'] as List)
        PersonSnapshot.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
    createdAt: j['createdAt'] as String,
    updatedAt: j['updatedAt'] as String,
    status: j['status'] == 'final'
        ? MonthStatus.finalised
        : MonthStatus.values.byName(j['status'] as String),
    revision: j['revision'] as int,
    schemaVersion: j['schemaVersion'] as int? ?? 1,
    difficultySchemaVersion: j['difficultySchemaVersion'] as int? ?? 0,
    difficultySettingsSnapshot: j['difficultySettingsSnapshot'] == null
        ? null
        : DifficultySettings.fromJson(
            Map<String, dynamic>.from(j['difficultySettingsSnapshot'] as Map),
          ),
    holidayCalendarSnapshot: [
      for (final h in j['holidayCalendarSnapshot'] as List? ?? [])
        HolidayDay.fromJson(Map<String, dynamic>.from(h as Map)),
    ],
    holidayDifficultyOverrides: Map<String, int>.from(
      j['holidayDifficultyOverrides'] as Map? ?? {},
    ),
    engineVersion: j['engineVersion'] as String? ?? '1.0.0',
    snapshotGroupUpdates: [
      for (final update in j['snapshotGroupUpdates'] as List? ?? [])
        Map<String, dynamic>.from(update as Map),
    ],
    requiredDuties: j['requiredDuties'] as int,
    publishedAt: j['publishedAt'] as String?,
    boundarySource: j['boundarySource'] as String,
    boundaryConfirmed: j['boundaryConfirmed'] as bool? ?? false,
    constraints: (j['constraints'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        PersonalConstraints.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    boundary: (j['boundaryConditions'] as Map).map(
      (k, v) => MapEntry(k as String, List<String>.from(v as List)),
    ),
    duties: (j['duties'] as Map).map(
      (k, v) => MapEntry(
        int.parse(k as String),
        List<String>.from((v as Map)['personIds'] as List),
      ),
    ),
    manuallyEdited: {
      for (final e in (j['duties'] as Map).entries)
        if ((e.value as Map)['manuallyEdited'] == true)
          int.parse(e.key as String),
    },
    tasks: (j['tasks'] as Map).map(
      (k, v) => MapEntry(
        ClinicTask.values.byName(k as String),
        TaskAssignment.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    overrides: (j['overrides'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        TaskOverride.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    shareTokens: List<String>.from(j['shareTokens'] as List? ?? []),
  );
}
