import 'enums.dart';
import 'machine.dart';
import 'muscle.dart';

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// メニュー生成で処方された1種目分のメニューデータ
class PrescribedExercise {
  final Machine machine;
  final double weightKg;
  final int reps;
  final int sets;
  final List<String> primaryMuscleNames;
  final List<String> synergistMuscleNames;
  final double finalScore;
  final double rawScore;
  final List<String> reasons;

  const PrescribedExercise({
    required this.machine,
    required this.weightKg,
    required this.reps,
    required this.sets,
    this.primaryMuscleNames = const <String>[],
    this.synergistMuscleNames = const <String>[],
    this.finalScore = 0.0,
    this.rawScore = 0.0,
    this.reasons = const <String>[],
  });

  PrescribedExercise copyWith({
    Machine? machine,
    double? weightKg,
    int? reps,
    int? sets,
    List<String>? primaryMuscleNames,
    List<String>? synergistMuscleNames,
    double? finalScore,
    double? rawScore,
    List<String>? reasons,
  }) {
    return PrescribedExercise(
      machine: machine ?? this.machine,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      sets: sets ?? this.sets,
      primaryMuscleNames: primaryMuscleNames ?? this.primaryMuscleNames,
      synergistMuscleNames: synergistMuscleNames ?? this.synergistMuscleNames,
      finalScore: finalScore ?? this.finalScore,
      rawScore: rawScore ?? this.rawScore,
      reasons: reasons ?? this.reasons,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'machine': machine.toJson(),
      'weight_kg': weightKg,
      'reps': reps,
      'sets': sets,
      'primary_muscle_names': primaryMuscleNames,
      'synergist_muscle_names': synergistMuscleNames,
      'final_score': finalScore,
      'raw_score': rawScore,
      'reasons': reasons,
    };
  }

  factory PrescribedExercise.fromJson(Map<String, dynamic> json) {
    final machineRaw = json['machine'];
    final primaryRaw =
        (json['primary_muscle_names'] ?? json['primaryMuscleNames'])
                as List<dynamic>? ??
            const <dynamic>[];
    final synergistRaw =
        (json['synergist_muscle_names'] ?? json['synergistMuscleNames'])
                as List<dynamic>? ??
            const <dynamic>[];
    final reasonsRaw = json['reasons'] as List<dynamic>? ?? const <dynamic>[];

    return PrescribedExercise(
      machine: Machine.fromJson(
        machineRaw is Map
            ? Map<String, dynamic>.from(machineRaw)
            : const <String, dynamic>{},
      ),
      weightKg:
          ((json['weight_kg'] ?? json['weightKg']) as num?)?.toDouble() ?? 0.0,
      reps: (json['reps'] as num?)?.toInt() ?? 10,
      sets: (json['sets'] as num?)?.toInt() ?? 3,
      primaryMuscleNames: primaryRaw.map((e) => e.toString()).toList(),
      synergistMuscleNames: synergistRaw.map((e) => e.toString()).toList(),
      finalScore:
          ((json['final_score'] ?? json['finalScore']) as num?)?.toDouble() ??
              0.0,
      rawScore:
          ((json['raw_score'] ?? json['rawScore']) as num?)?.toDouble() ?? 0.0,
      reasons: reasonsRaw.map((e) => e.toString()).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrescribedExercise &&
          runtimeType == other.runtimeType &&
          machine == other.machine &&
          weightKg == other.weightKg &&
          reps == other.reps &&
          sets == other.sets &&
          _listEquals(primaryMuscleNames, other.primaryMuscleNames) &&
          _listEquals(synergistMuscleNames, other.synergistMuscleNames) &&
          finalScore == other.finalScore &&
          rawScore == other.rawScore &&
          _listEquals(reasons, other.reasons);

  @override
  int get hashCode => Object.hash(
    machine,
    weightKg,
    reps,
    sets,
    Object.hashAll(primaryMuscleNames),
    Object.hashAll(synergistMuscleNames),
    finalScore,
    rawScore,
    Object.hashAll(reasons),
  );
}

/// 実施完了した1種目分の実績レコード
class CompletedExerciseRecord {
  final String machineId;
  final String machineName;
  final double weightKg;
  final int reps;
  final int sets;
  final bool completed;

  const CompletedExerciseRecord({
    required this.machineId,
    required this.machineName,
    required this.weightKg,
    required this.reps,
    required this.sets,
    this.completed = true,
  });

  factory CompletedExerciseRecord.fromPrescribed(
    PrescribedExercise prescribed, {
    bool completed = true,
  }) {
    return CompletedExerciseRecord(
      machineId: prescribed.machine.id,
      machineName: prescribed.machine.name,
      weightKg: prescribed.weightKg,
      reps: prescribed.reps,
      sets: prescribed.sets,
      completed: completed,
    );
  }

  CompletedExerciseRecord copyWith({
    String? machineId,
    String? machineName,
    double? weightKg,
    int? reps,
    int? sets,
    bool? completed,
  }) {
    return CompletedExerciseRecord(
      machineId: machineId ?? this.machineId,
      machineName: machineName ?? this.machineName,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      sets: sets ?? this.sets,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'machine_id': machineId,
      'machine_name': machineName,
      'weight_kg': weightKg,
      'reps': reps,
      'sets': sets,
      'completed': completed,
    };
  }

  factory CompletedExerciseRecord.fromJson(Map<String, dynamic> json) {
    final rawMachineId = json['machine_id'] ?? json['machineId'] ?? '';
    final rawMachineName = json['machine_name'] ?? json['machineName'] ?? '';
    final rawWeightKg = json['weight_kg'] ?? json['weightKg'];

    return CompletedExerciseRecord(
      machineId: rawMachineId as String,
      machineName: rawMachineName as String,
      weightKg: (rawWeightKg as num?)?.toDouble() ?? 0.0,
      reps: (json['reps'] as num?)?.toInt() ?? 10,
      sets: (json['sets'] as num?)?.toInt() ?? 3,
      completed: json['completed'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompletedExerciseRecord &&
          runtimeType == other.runtimeType &&
          machineId == other.machineId &&
          machineName == other.machineName &&
          weightKg == other.weightKg &&
          reps == other.reps &&
          sets == other.sets &&
          completed == other.completed;

  @override
  int get hashCode =>
      Object.hash(machineId, machineName, weightKg, reps, sets, completed);
}

/// 1回分のトレーニングセッション実績
class WorkoutSessionRecord {
  final String id;
  final DateTime completedAt;
  final WorkoutDurationCourse durationCourse;
  final WorkoutCondition condition;
  final TimeSlot timeSlot;
  final String? focusMuscleId;
  final List<CompletedExerciseRecord> exercises;
  final WorkoutFeedback feedback;
  final DateTime createdAt;

  const WorkoutSessionRecord({
    required this.id,
    required this.completedAt,
    required this.durationCourse,
    required this.condition,
    required this.timeSlot,
    this.focusMuscleId,
    required this.exercises,
    required this.feedback,
    required this.createdAt,
  });

  WorkoutSessionRecord copyWith({
    String? id,
    DateTime? completedAt,
    WorkoutDurationCourse? durationCourse,
    WorkoutCondition? condition,
    TimeSlot? timeSlot,
    String? focusMuscleId,
    List<CompletedExerciseRecord>? exercises,
    WorkoutFeedback? feedback,
    DateTime? createdAt,
    bool clearFocusMuscleId = false,
  }) {
    return WorkoutSessionRecord(
      id: id ?? this.id,
      completedAt: completedAt ?? this.completedAt,
      durationCourse: durationCourse ?? this.durationCourse,
      condition: condition ?? this.condition,
      timeSlot: timeSlot ?? this.timeSlot,
      focusMuscleId:
          clearFocusMuscleId ? null : (focusMuscleId ?? this.focusMuscleId),
      exercises: exercises ?? this.exercises,
      feedback: feedback ?? this.feedback,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'completed_at': completedAt.toIso8601String(),
      'duration_course': durationCourse.id,
      'condition': condition.id,
      'time_slot': timeSlot.id,
      'focus_muscle_id': focusMuscleId,
      'exercises_json': exercises.map((e) => e.toJson()).toList(),
      'feedback': feedback.id,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory WorkoutSessionRecord.fromJson(Map<String, dynamic> json) {
    final completedAtRaw = json['completed_at'] ?? json['completedAt'];
    final completedAt = completedAtRaw is DateTime
        ? completedAtRaw
        : DateTime.parse(completedAtRaw as String);

    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final createdAt = createdAtRaw == null
        ? completedAt
        : (createdAtRaw is DateTime
              ? createdAtRaw
              : DateTime.parse(createdAtRaw as String));

    final exercisesRaw =
        (json['exercises_json'] ?? json['exercises']) as List<dynamic>? ??
            const <dynamic>[];
    final parsedExercises = exercisesRaw
        .map(
          (e) => CompletedExerciseRecord.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();

    return WorkoutSessionRecord(
      id: (json['id'] as String?) ?? '',
      completedAt: completedAt,
      durationCourse: WorkoutDurationCourse.fromId(
        (json['duration_course'] ?? json['durationCourse']) as String?,
      ),
      condition: WorkoutCondition.fromId(json['condition'] as String?),
      timeSlot: TimeSlot.fromId(
        (json['time_slot'] ?? json['timeSlot']) as String?,
      ),
      focusMuscleId:
          (json['focus_muscle_id'] ?? json['focusMuscleId']) as String?,
      exercises: parsedExercises,
      feedback: WorkoutFeedback.fromId(json['feedback'] as String?),
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutSessionRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          completedAt == other.completedAt &&
          durationCourse == other.durationCourse &&
          condition == other.condition &&
          timeSlot == other.timeSlot &&
          focusMuscleId == other.focusMuscleId &&
          _listEquals(exercises, other.exercises) &&
          feedback == other.feedback &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    completedAt,
    durationCourse,
    condition,
    timeSlot,
    focusMuscleId,
    Object.hashAll(exercises),
    feedback,
    createdAt,
  );
}

/// WorkoutMenuGenerator.generateMenu の戻り値
class MenuGenerationResult {
  final List<PrescribedExercise> exercises;
  final Map<String, MuscleScoreInfo> muscleScores;
  final TimeSlot timeSlot;
  final WorkoutDurationCourse? course;
  final WorkoutCondition? condition;
  final DateTime? generatedAt;
  final String? focusMuscleId;

  const MenuGenerationResult({
    required this.exercises,
    required this.muscleScores,
    required this.timeSlot,
    this.course,
    this.condition,
    this.generatedAt,
    this.focusMuscleId,
  });

  MenuGenerationResult copyWith({
    List<PrescribedExercise>? exercises,
    Map<String, MuscleScoreInfo>? muscleScores,
    TimeSlot? timeSlot,
    WorkoutDurationCourse? course,
    WorkoutCondition? condition,
    DateTime? generatedAt,
    String? focusMuscleId,
    bool clearCourse = false,
    bool clearCondition = false,
    bool clearGeneratedAt = false,
    bool clearFocusMuscleId = false,
  }) {
    return MenuGenerationResult(
      exercises: exercises ?? this.exercises,
      muscleScores: muscleScores ?? this.muscleScores,
      timeSlot: timeSlot ?? this.timeSlot,
      course: clearCourse ? null : (course ?? this.course),
      condition: clearCondition ? null : (condition ?? this.condition),
      generatedAt: clearGeneratedAt ? null : (generatedAt ?? this.generatedAt),
      focusMuscleId:
          clearFocusMuscleId ? null : (focusMuscleId ?? this.focusMuscleId),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'exercises': exercises.map((e) => e.toJson()).toList(),
      'muscle_scores': muscleScores.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'time_slot': timeSlot.id,
      'course': course?.id,
      'condition': condition?.id,
      'generated_at': generatedAt?.toIso8601String(),
      'focus_muscle_id': focusMuscleId,
    };
  }

  factory MenuGenerationResult.fromJson(Map<String, dynamic> json) {
    final exercisesRaw = json['exercises'] as List<dynamic>? ?? const <dynamic>[];
    final scoresRaw =
        (json['muscle_scores'] ?? json['muscleScores']) as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{};
    final rawCourse = json['course'] as String?;
    final rawCondition = json['condition'] as String?;
    final rawGeneratedAt = json['generated_at'] ?? json['generatedAt'];

    return MenuGenerationResult(
      exercises: exercisesRaw
          .map(
            (e) => PrescribedExercise.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      muscleScores: scoresRaw.map(
        (key, value) => MapEntry(
          key.toString(),
          MuscleScoreInfo.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      timeSlot: TimeSlot.fromId(
        (json['time_slot'] ?? json['timeSlot']) as String?,
      ),
      course: rawCourse == null ? null : WorkoutDurationCourse.fromId(rawCourse),
      condition:
          rawCondition == null ? null : WorkoutCondition.fromId(rawCondition),
      generatedAt: rawGeneratedAt == null
          ? null
          : (rawGeneratedAt is DateTime
                ? rawGeneratedAt
                : DateTime.parse(rawGeneratedAt as String)),
      focusMuscleId:
          (json['focus_muscle_id'] ?? json['focusMuscleId']) as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuGenerationResult &&
          runtimeType == other.runtimeType &&
          _listEquals(exercises, other.exercises) &&
          _mapEquals(muscleScores, other.muscleScores) &&
          timeSlot == other.timeSlot &&
          course == other.course &&
          condition == other.condition &&
          generatedAt == other.generatedAt &&
          focusMuscleId == other.focusMuscleId;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(exercises),
    Object.hashAllUnordered(
      muscleScores.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    timeSlot,
    course,
    condition,
    generatedAt,
    focusMuscleId,
  );
}

/// WorkoutMenuGenerator.advanceSessionDay の戻り値
class SessionAdvanceResult {
  final Map<String, MuscleInputState> muscleStates;
  final Map<String, MachineHistoryEntry> machineHistory;
  final int sessionCount;

  const SessionAdvanceResult({
    required this.muscleStates,
    required this.machineHistory,
    required this.sessionCount,
  });

  SessionAdvanceResult copyWith({
    Map<String, MuscleInputState>? muscleStates,
    Map<String, MachineHistoryEntry>? machineHistory,
    int? sessionCount,
  }) {
    return SessionAdvanceResult(
      muscleStates: muscleStates ?? this.muscleStates,
      machineHistory: machineHistory ?? this.machineHistory,
      sessionCount: sessionCount ?? this.sessionCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'muscle_states': muscleStates.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'machine_history': machineHistory.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'session_count': sessionCount,
    };
  }

  factory SessionAdvanceResult.fromJson(Map<String, dynamic> json) {
    final statesRaw =
        (json['muscle_states'] ?? json['muscleStates']) as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{};
    final historyRaw =
        (json['machine_history'] ?? json['machineHistory'])
                as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{};

    return SessionAdvanceResult(
      muscleStates: statesRaw.map(
        (key, value) => MapEntry(
          key.toString(),
          MuscleInputState.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      machineHistory: historyRaw.map(
        (key, value) => MapEntry(
          key.toString(),
          MachineHistoryEntry.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      sessionCount:
          ((json['session_count'] ?? json['sessionCount']) as num?)?.toInt() ??
              0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionAdvanceResult &&
          runtimeType == other.runtimeType &&
          _mapEquals(muscleStates, other.muscleStates) &&
          _mapEquals(machineHistory, other.machineHistory) &&
          sessionCount == other.sessionCount;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      muscleStates.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      machineHistory.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    sessionCount,
  );
}
