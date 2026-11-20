import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// トレーニング中画面（Screen A2）の状態・種目進行・数値調整を管理するコントローラ
class TrainingSessionController extends ChangeNotifier {
  static const double weightStepKg = 2.5;
  static const double minWeightKg = 2.5;
  static const int minReps = 1;
  static const int minSets = 1;

  final MenuGenerationResult menuResult;
  final VoidCallback? onWorkoutCompleted;

  late final List<PrescribedExercise> _exercises;
  int _currentIndex = 0;
  bool _isStarted = false;

  TrainingSessionController({
    required this.menuResult,
    this.onWorkoutCompleted,
  }) : _exercises = menuResult.exercises
           .map(_sanitizeExercise)
           .toList(growable: true);

  static PrescribedExercise _sanitizeExercise(PrescribedExercise exercise) {
    final sanitizedWeight =
        (!exercise.weightKg.isFinite || exercise.weightKg < minWeightKg)
        ? minWeightKg
        : exercise.weightKg;
    final sanitizedReps = math.max(minReps, exercise.reps);
    final sanitizedSets = math.max(minSets, exercise.sets);
    if (sanitizedWeight == exercise.weightKg &&
        sanitizedReps == exercise.reps &&
        sanitizedSets == exercise.sets) {
      return exercise;
    }
    return exercise.copyWith(
      weightKg: sanitizedWeight,
      reps: sanitizedReps,
      sets: sanitizedSets,
    );
  }

  /// テストや単体利用向けに種目リストから直接生成するファクトリ
  factory TrainingSessionController.fromExercises({
    required List<PrescribedExercise> exercises,
    TimeSlot timeSlot = TimeSlot.evening,
    WorkoutDurationCourse? course,
    WorkoutCondition? condition,
    DateTime? generatedAt,
    String? focusMuscleId,
    VoidCallback? onWorkoutCompleted,
  }) {
    return TrainingSessionController(
      menuResult: MenuGenerationResult(
        exercises: exercises,
        muscleScores: const <String, MuscleScoreInfo>{},
        timeSlot: timeSlot,
        course: course,
        condition: condition,
        generatedAt: generatedAt,
        focusMuscleId: focusMuscleId,
      ),
      onWorkoutCompleted: onWorkoutCompleted,
    );
  }

  List<PrescribedExercise> get exercises =>
      List<PrescribedExercise>.unmodifiable(_exercises);

  int get currentIndex => _currentIndex;
  int get currentExerciseIndex => _currentIndex;
  int get totalCount => _exercises.length;
  bool get isEmpty => _exercises.isEmpty;
  bool get isStarted => _isStarted;
  bool get isLastExercise =>
      _exercises.isNotEmpty && _currentIndex >= _exercises.length - 1;

  PrescribedExercise get currentExercise {
    if (_exercises.isEmpty) {
      throw StateError('TrainingSessionController has no exercises');
    }
    return _exercises[_currentIndex];
  }

  PrescribedExercise? get currentExerciseOrNull =>
      (_exercises.isEmpty ||
              _currentIndex < 0 ||
              _currentIndex >= _exercises.length)
          ? null
          : _exercises[_currentIndex];

  double get weightKg => currentExerciseOrNull?.weightKg ?? minWeightKg;
  int get reps => currentExerciseOrNull?.reps ?? minReps;
  int get sets => currentExerciseOrNull?.sets ?? minSets;

  String get progressText => _exercises.isEmpty
      ? '0 / 0'
      : '${_currentIndex + 1} / ${_exercises.length}';

  /// 整数なら小数点なし（60）、小数ありなら小数第1位まで（62.5）でフォーマットする
  static String formatWeightNumber(double val) {
    if (!val.isFinite || val <= 0) return '2.5';
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  String get formattedWeightDisplay => '${formatWeightNumber(weightKg)} kg';

  /// 現在表示中の種目（_currentIndex）と [newIndex] の種目の順番をその場で入れ替える
  void swapExercise(int newIndex) {
    if (_exercises.isEmpty ||
        newIndex < 0 ||
        newIndex >= _exercises.length ||
        newIndex == _currentIndex) {
      return;
    }
    final temp = _exercises[_currentIndex];
    _exercises[_currentIndex] = _exercises[newIndex];
    _exercises[newIndex] = temp;
    notifyListeners();
  }

  /// noukin_app 互換エイリアス
  void swapExerciseWith(int targetIndex) => swapExercise(targetIndex);

  /// 現在の種目の重量を [delta] kg 調整する（最小 2.5 kg）
  void adjustWeight(double delta) {
    if (_exercises.isEmpty || !delta.isFinite || delta == 0) return;
    final current = _exercises[_currentIndex];
    final baseWeight = (current.weightKg.isFinite && current.weightKg > 0.0)
        ? current.weightKg
        : minWeightKg;
    final raw = baseWeight + delta;
    if (!raw.isFinite) return;
    final rounded = double.parse(raw.toStringAsFixed(1));
    final clamped = math.max(minWeightKg, rounded);
    _exercises[_currentIndex] = current.copyWith(weightKg: clamped);
    notifyListeners();
  }

  /// 現在の種目のレップ数を [delta] 回調整する（最小 1 回）
  void adjustReps(int delta) {
    if (_exercises.isEmpty || delta == 0) return;
    final current = _exercises[_currentIndex];
    final clamped = math.max(minReps, current.reps + delta);
    _exercises[_currentIndex] = current.copyWith(reps: clamped);
    notifyListeners();
  }

  /// 現在の種目のセット数を [delta] セット調整する（最小 1 セット）
  void adjustSets(int delta) {
    if (_exercises.isEmpty || delta == 0) return;
    final current = _exercises[_currentIndex];
    final clamped = math.max(minSets, current.sets + delta);
    _exercises[_currentIndex] = current.copyWith(sets: clamped);
    notifyListeners();
  }

  /// 「開始 / 次へ」ボタン押下時の進行処理。最終種目の完了時は true を返す。
  bool advanceOrComplete() {
    if (_exercises.isEmpty) return false;
    if (!_isStarted) {
      _isStarted = true;
      notifyListeners();
      return false;
    }
    if (_currentIndex < _exercises.length - 1) {
      _currentIndex++;
      notifyListeners();
      return false;
    }
    onWorkoutCompleted?.call();
    return true;
  }

  /// 編集・入れ替え後の種目リストをそのまま返す（advanceSessionDay への入力用）
  List<PrescribedExercise> get updatedPrescribedExercises =>
      List<PrescribedExercise>.unmodifiable(_exercises);

  /// 編集・入れ替え後の種目リストを履歴保存用レコードへ変換する
  List<CompletedExerciseRecord> toCompletedRecords() {
    return _exercises
        .map(
          (exercise) =>
              CompletedExerciseRecord.fromPrescribed(exercise, completed: true),
        )
        .toList(growable: false);
  }
}
