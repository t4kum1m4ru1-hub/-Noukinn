import 'enums.dart';

bool _stringListEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// マシン・種目マスタ定義（全29種目）
class Machine {
  final String id;
  final String name;
  final MuscleGroup category;
  final double baseWeight;
  final double bwFactor;
  final int baseReps;
  final int defaultSessionsSinceUsed;
  final List<String> primaryMuscleIds;
  final List<String> synergistMuscleIds;
  final String? imageAssetPath;

  const Machine({
    required this.id,
    required this.name,
    required this.category,
    required this.baseWeight,
    required this.bwFactor,
    required this.baseReps,
    required this.defaultSessionsSinceUsed,
    required this.primaryMuscleIds,
    required this.synergistMuscleIds,
    this.imageAssetPath,
  });

  bool get isIsolationOrCore =>
      (primaryMuscleIds.length + synergistMuscleIds.length) <= 4 ||
      category == MuscleGroup.arms ||
      category == MuscleGroup.core ||
      const <String>{
        'mac5',
        'mac6',
        'mac10',
        'mac14',
        'mac22',
        'mac23',
      }.contains(id);

  Machine copyWith({
    String? id,
    String? name,
    MuscleGroup? category,
    double? baseWeight,
    double? bwFactor,
    int? baseReps,
    int? defaultSessionsSinceUsed,
    List<String>? primaryMuscleIds,
    List<String>? synergistMuscleIds,
    String? imageAssetPath,
    bool clearImageAssetPath = false,
  }) {
    return Machine(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      baseWeight: baseWeight ?? this.baseWeight,
      bwFactor: bwFactor ?? this.bwFactor,
      baseReps: baseReps ?? this.baseReps,
      defaultSessionsSinceUsed:
          defaultSessionsSinceUsed ?? this.defaultSessionsSinceUsed,
      primaryMuscleIds: primaryMuscleIds ?? this.primaryMuscleIds,
      synergistMuscleIds: synergistMuscleIds ?? this.synergistMuscleIds,
      imageAssetPath: clearImageAssetPath
          ? null
          : (imageAssetPath ?? this.imageAssetPath),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'category': category.id,
      'base_weight': baseWeight,
      'bw_factor': bwFactor,
      'base_reps': baseReps,
      'default_sessions_since_used': defaultSessionsSinceUsed,
      'primary_muscle_ids': primaryMuscleIds,
      'synergist_muscle_ids': synergistMuscleIds,
      'image_asset_path': imageAssetPath,
    };
  }

  factory Machine.fromJson(Map<String, dynamic> json) {
    final primaryRaw =
        (json['primary_muscle_ids'] ?? json['primaryMuscleIds']) as List<dynamic>? ??
            const <dynamic>[];
    final synergistRaw =
        (json['synergist_muscle_ids'] ?? json['synergistMuscleIds'])
                as List<dynamic>? ??
            const <dynamic>[];

    return Machine(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      category: MuscleGroup.fromId(json['category'] as String?),
      baseWeight:
          ((json['base_weight'] ?? json['baseWeight']) as num?)?.toDouble() ??
              20.0,
      bwFactor:
          ((json['bw_factor'] ?? json['bwFactor']) as num?)?.toDouble() ?? 0.5,
      baseReps:
          ((json['base_reps'] ?? json['baseReps']) as num?)?.toInt() ?? 10,
      defaultSessionsSinceUsed: ((json['default_sessions_since_used'] ??
                  json['defaultSessionsSinceUsed']) as num?)
              ?.toInt() ??
          4,
      primaryMuscleIds: primaryRaw.map((e) => e.toString()).toList(),
      synergistMuscleIds: synergistRaw.map((e) => e.toString()).toList(),
      imageAssetPath:
          (json['image_asset_path'] ?? json['imageAssetPath']) as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Machine &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          category == other.category &&
          baseWeight == other.baseWeight &&
          bwFactor == other.bwFactor &&
          baseReps == other.baseReps &&
          defaultSessionsSinceUsed == other.defaultSessionsSinceUsed &&
          _stringListEquals(primaryMuscleIds, other.primaryMuscleIds) &&
          _stringListEquals(synergistMuscleIds, other.synergistMuscleIds) &&
          imageAssetPath == other.imageAssetPath;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    baseWeight,
    bwFactor,
    baseReps,
    defaultSessionsSinceUsed,
    Object.hashAll(primaryMuscleIds),
    Object.hashAll(synergistMuscleIds),
    imageAssetPath,
  );
}

/// マシン別履歴状態（未実施回数・前回重量・前回フィードバック）
class MachineHistoryEntry {
  final String machineId;
  final int sessionsSinceUsed;
  final double? lastWeightKg;
  final WorkoutFeedback? lastFeedback;

  const MachineHistoryEntry({
    required this.machineId,
    this.sessionsSinceUsed = 4,
    this.lastWeightKg,
    this.lastFeedback,
  });

  MachineHistoryEntry copyWith({
    String? machineId,
    int? sessionsSinceUsed,
    double? lastWeightKg,
    WorkoutFeedback? lastFeedback,
    bool clearLastWeight = false,
    bool clearLastFeedback = false,
  }) {
    return MachineHistoryEntry(
      machineId: machineId ?? this.machineId,
      sessionsSinceUsed: sessionsSinceUsed ?? this.sessionsSinceUsed,
      lastWeightKg: clearLastWeight ? null : (lastWeightKg ?? this.lastWeightKg),
      lastFeedback:
          clearLastFeedback ? null : (lastFeedback ?? this.lastFeedback),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'machine_id': machineId,
      'sessions_since_used': sessionsSinceUsed,
      'last_weight_kg': lastWeightKg,
      'last_feedback': lastFeedback?.id,
    };
  }

  factory MachineHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawMachineId = json['machine_id'] ?? json['machineId'] ?? '';
    final rawSessionsSinceUsed =
        json['sessions_since_used'] ?? json['sessionsSinceUsed'];
    final rawLastWeightKg = json['last_weight_kg'] ?? json['lastWeightKg'];
    final rawLastFeedback = json['last_feedback'] ?? json['lastFeedback'];

    return MachineHistoryEntry(
      machineId: rawMachineId as String,
      sessionsSinceUsed: (rawSessionsSinceUsed as num?)?.toInt() ?? 4,
      lastWeightKg: (rawLastWeightKg as num?)?.toDouble(),
      lastFeedback: WorkoutFeedback.tryFromId(rawLastFeedback as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MachineHistoryEntry &&
          runtimeType == other.runtimeType &&
          machineId == other.machineId &&
          sessionsSinceUsed == other.sessionsSinceUsed &&
          lastWeightKg == other.lastWeightKg &&
          lastFeedback == other.lastFeedback;

  @override
  int get hashCode =>
      Object.hash(machineId, sessionsSinceUsed, lastWeightKg, lastFeedback);
}
