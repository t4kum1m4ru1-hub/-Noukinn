import 'enums.dart';

/// 筋肉マスタ定義（全54筋肉）
class Muscle {
  final String id;
  final String name;
  final MuscleGroup group;
  final MuscleTimeCategory timeCat;
  final int recoveryDays;

  const Muscle({
    required this.id,
    required this.name,
    required this.group,
    required this.timeCat,
    required this.recoveryDays,
  });

  Muscle copyWith({
    String? id,
    String? name,
    MuscleGroup? group,
    MuscleTimeCategory? timeCat,
    int? recoveryDays,
  }) {
    return Muscle(
      id: id ?? this.id,
      name: name ?? this.name,
      group: group ?? this.group,
      timeCat: timeCat ?? this.timeCat,
      recoveryDays: recoveryDays ?? this.recoveryDays,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'group': group.id,
      'time_cat': timeCat.id,
      'recovery_days': recoveryDays,
    };
  }

  factory Muscle.fromJson(Map<String, dynamic> json) {
    final rawTimeCat = (json['time_cat'] ?? json['timeCat']) as String?;
    final rawRecoveryDays = json['recovery_days'] ?? json['recoveryDays'];

    return Muscle(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      group: MuscleGroup.fromId(json['group'] as String?),
      timeCat: MuscleTimeCategory.fromId(rawTimeCat),
      recoveryDays: (rawRecoveryDays as num?)?.toInt() ?? 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Muscle &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          group == other.group &&
          timeCat == other.timeCat &&
          recoveryDays == other.recoveryDays;

  @override
  int get hashCode => Object.hash(id, name, group, timeCat, recoveryDays);
}

/// 各筋肉のユーザー状態パラメータ（B_i, S_i, P_i, ケガ除外）
class MuscleInputState {
  final String muscleId;
  final int blankDays;
  final double stimulationDays;
  final int priorityP;
  final bool isInjured;

  const MuscleInputState({
    required this.muscleId,
    this.blankDays = 4,
    this.stimulationDays = 2.0,
    this.priorityP = 10,
    this.isInjured = false,
  });

  MuscleInputState copyWith({
    String? muscleId,
    int? blankDays,
    double? stimulationDays,
    int? priorityP,
    bool? isInjured,
  }) {
    return MuscleInputState(
      muscleId: muscleId ?? this.muscleId,
      blankDays: blankDays ?? this.blankDays,
      stimulationDays: stimulationDays ?? this.stimulationDays,
      priorityP: priorityP ?? this.priorityP,
      isInjured: isInjured ?? this.isInjured,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'muscle_id': muscleId,
      'blank_days': blankDays,
      'stimulation_days': stimulationDays,
      'priority_p': priorityP,
      'is_injured': isInjured,
    };
  }

  factory MuscleInputState.fromJson(Map<String, dynamic> json) {
    final rawMuscleId = json['muscle_id'] ?? json['muscleId'] ?? '';
    final rawBlankDays = json['blank_days'] ?? json['blankDays'];
    final rawStimulationDays =
        json['stimulation_days'] ?? json['stimulationDays'];
    final rawPriorityP = json['priority_p'] ?? json['priorityP'];
    final rawIsInjured = json['is_injured'] ?? json['isInjured'];

    return MuscleInputState(
      muscleId: rawMuscleId as String,
      blankDays: (rawBlankDays as num?)?.toInt() ?? 4,
      stimulationDays: (rawStimulationDays as num?)?.toDouble() ?? 2.0,
      priorityP: (rawPriorityP as num?)?.toInt() ?? 10,
      isInjured: rawIsInjured as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MuscleInputState &&
          runtimeType == other.runtimeType &&
          muscleId == other.muscleId &&
          blankDays == other.blankDays &&
          stimulationDays == other.stimulationDays &&
          priorityP == other.priorityP &&
          isInjured == other.isInjured;

  @override
  int get hashCode => Object.hash(
    muscleId,
    blankDays,
    stimulationDays,
    priorityP,
    isInjured,
  );
}

/// 各筋肉の算出M値および回復ステータス詳細
class MuscleScoreInfo {
  final String muscleId;
  final int bRaw;
  final int bCapped;
  final int priorityP;
  final int baseRecoveryDays;
  final int effectiveRecoveryDays;
  final double stimulationDays;
  final double mVal;
  final double synMVal;
  final MuscleScoreStatus status;
  final String? muscleName;
  final MuscleGroup? group;
  final MuscleTimeCategory? timeCat;
  final bool isExtendedByVolume;
  final bool isExtendedByAge;

  const MuscleScoreInfo({
    required this.muscleId,
    required this.bRaw,
    required this.bCapped,
    required this.priorityP,
    required this.baseRecoveryDays,
    required this.effectiveRecoveryDays,
    required this.stimulationDays,
    required this.mVal,
    required this.synMVal,
    required this.status,
    this.muscleName,
    this.group,
    this.timeCat,
    this.isExtendedByVolume = false,
    this.isExtendedByAge = false,
  });

  MuscleScoreInfo copyWith({
    String? muscleId,
    int? bRaw,
    int? bCapped,
    int? priorityP,
    int? baseRecoveryDays,
    int? effectiveRecoveryDays,
    double? stimulationDays,
    double? mVal,
    double? synMVal,
    MuscleScoreStatus? status,
    String? muscleName,
    MuscleGroup? group,
    MuscleTimeCategory? timeCat,
    bool? isExtendedByVolume,
    bool? isExtendedByAge,
    bool clearMuscleName = false,
    bool clearGroup = false,
    bool clearTimeCat = false,
  }) {
    return MuscleScoreInfo(
      muscleId: muscleId ?? this.muscleId,
      bRaw: bRaw ?? this.bRaw,
      bCapped: bCapped ?? this.bCapped,
      priorityP: priorityP ?? this.priorityP,
      baseRecoveryDays: baseRecoveryDays ?? this.baseRecoveryDays,
      effectiveRecoveryDays:
          effectiveRecoveryDays ?? this.effectiveRecoveryDays,
      stimulationDays: stimulationDays ?? this.stimulationDays,
      mVal: mVal ?? this.mVal,
      synMVal: synMVal ?? this.synMVal,
      status: status ?? this.status,
      muscleName: clearMuscleName ? null : (muscleName ?? this.muscleName),
      group: clearGroup ? null : (group ?? this.group),
      timeCat: clearTimeCat ? null : (timeCat ?? this.timeCat),
      isExtendedByVolume: isExtendedByVolume ?? this.isExtendedByVolume,
      isExtendedByAge: isExtendedByAge ?? this.isExtendedByAge,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'muscle_id': muscleId,
      'b_raw': bRaw,
      'b_capped': bCapped,
      'priority_p': priorityP,
      'base_recovery_days': baseRecoveryDays,
      'effective_recovery_days': effectiveRecoveryDays,
      'stimulation_days': stimulationDays,
      'm_val': mVal,
      'syn_m_val': synMVal,
      'status': status.id,
      'muscle_name': muscleName,
      'group': group?.id,
      'time_cat': timeCat?.id,
      'is_extended_by_volume': isExtendedByVolume,
      'is_extended_by_age': isExtendedByAge,
    };
  }

  factory MuscleScoreInfo.fromJson(Map<String, dynamic> json) {
    final rawGroup = json['group'] as String?;
    final rawTimeCat = (json['time_cat'] ?? json['timeCat']) as String?;

    return MuscleScoreInfo(
      muscleId: ((json['muscle_id'] ?? json['muscleId']) as String?) ?? '',
      bRaw: ((json['b_raw'] ?? json['bRaw']) as num?)?.toInt() ?? 0,
      bCapped: ((json['b_capped'] ?? json['bCapped']) as num?)?.toInt() ?? 0,
      priorityP:
          ((json['priority_p'] ?? json['priorityP']) as num?)?.toInt() ?? 0,
      baseRecoveryDays: ((json['base_recovery_days'] ??
                  json['baseRecoveryDays']) as num?)
              ?.toInt() ??
          2,
      effectiveRecoveryDays: ((json['effective_recovery_days'] ??
                  json['effectiveRecoveryDays']) as num?)
              ?.toInt() ??
          2,
      stimulationDays: ((json['stimulation_days'] ??
                  json['stimulationDays']) as num?)
              ?.toDouble() ??
          0.0,
      mVal: ((json['m_val'] ?? json['mVal']) as num?)?.toDouble() ?? 0.0,
      synMVal:
          ((json['syn_m_val'] ?? json['synMVal']) as num?)?.toDouble() ?? 0.0,
      status: MuscleScoreStatus.fromId(json['status'] as String?),
      muscleName:
          (json['muscle_name'] ?? json['muscleName']) as String?,
      group: rawGroup == null ? null : MuscleGroup.fromId(rawGroup),
      timeCat:
          rawTimeCat == null ? null : MuscleTimeCategory.fromId(rawTimeCat),
      isExtendedByVolume: (json['is_extended_by_volume'] ??
              json['isExtendedByVolume']) as bool? ??
          false,
      isExtendedByAge: (json['is_extended_by_age'] ??
              json['isExtendedByAge']) as bool? ??
          false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MuscleScoreInfo &&
          runtimeType == other.runtimeType &&
          muscleId == other.muscleId &&
          bRaw == other.bRaw &&
          bCapped == other.bCapped &&
          priorityP == other.priorityP &&
          baseRecoveryDays == other.baseRecoveryDays &&
          effectiveRecoveryDays == other.effectiveRecoveryDays &&
          stimulationDays == other.stimulationDays &&
          mVal == other.mVal &&
          synMVal == other.synMVal &&
          status == other.status &&
          muscleName == other.muscleName &&
          group == other.group &&
          timeCat == other.timeCat &&
          isExtendedByVolume == other.isExtendedByVolume &&
          isExtendedByAge == other.isExtendedByAge;

  @override
  int get hashCode => Object.hash(
    muscleId,
    bRaw,
    bCapped,
    priorityP,
    baseRecoveryDays,
    effectiveRecoveryDays,
    stimulationDays,
    mVal,
    synMVal,
    status,
    muscleName,
    group,
    timeCat,
    isExtendedByVolume,
    isExtendedByAge,
  );
}
