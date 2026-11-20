import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';
import '../data/master_data.dart';
import '../engine/workout_menu_generator.dart';
import '../models/models.dart';
import '../screens/training_flow_screen.dart';
import '../services/auth_service.dart';
import '../services/workout_repository.dart';

/// アプリ全体の状態（プロファイル・54筋肉状態・29マシン履歴・セッション履歴・認証）を統合管理する ChangeNotifier
class AppState extends ChangeNotifier {
  static const int minBlankDays = 0;
  static const int maxBlankDays = 30;
  static const double minStimulationDays = 0.0;
  static const double maxStimulationDays = 30.0;
  static const int minPriorityP = 0;
  static const int maxPriorityP = 18;
  static const int minValidBirthYear = 1900;
  static const int maxValidBirthYear = 2025;
  static const double minValidBodyWeightKg = 20.0;
  static const double maxValidBodyWeightKg = 300.0;

  AuthService? _authService;
  WorkoutRepository? _repository;
  final WorkoutMenuGenerator generator;
  DateTime Function()? _clock;

  bool _isInitialized = false;
  Future<void>? _initFuture;
  AuthUser? _currentUser;
  UserProfile _profile = const UserProfile();
  Map<String, MuscleInputState> _muscleStates = MasterData.defaultMuscleStates(
    TrainingPurpose.bodyMakeMale,
  );
  Map<String, MachineHistoryEntry> _machineHistory =
      MasterData.defaultMachineHistory();
  List<WorkoutSessionRecord> _sessionHistory = const <WorkoutSessionRecord>[];
  int _sessionCount = 1;
  MenuGenerationResult? _lastMenuResult;

  AppState({
    AuthService? authService,
    WorkoutRepository? repository,
    this.generator = const WorkoutMenuGenerator(),
    DateTime Function()? clock,
  }) {
    _authService = authService;
    _repository = repository;
    _clock = clock;
  }

  /// 現在時刻を返す（テスト用クロック注入に対応）
  DateTime now() => (_clock ?? DateTime.now)();

  /// 外部からクロック関数を更新する（NoukinApp 再マウント時等）
  void updateClock(DateTime Function()? clock) {
    if (clock != null) {
      _clock = clock;
    }
  }

  bool get isInitialized => _isInitialized;
  AuthUser? get currentUser => _currentUser;
  bool get isLocalFallbackMode =>
      _authService?.isLocalFallbackMode ?? !SupabaseConfig.isInitialized;
  UserProfile get profile => _profile;
  Map<String, MuscleInputState> get muscleStates =>
      Map<String, MuscleInputState>.unmodifiable(_muscleStates);
  Map<String, MachineHistoryEntry> get machineHistory =>
      Map<String, MachineHistoryEntry>.unmodifiable(_machineHistory);
  List<WorkoutSessionRecord> get sessionHistory =>
      List<WorkoutSessionRecord>.unmodifiable(_sessionHistory);
  int get sessionCount => _sessionCount;
  MenuGenerationResult? get lastMenuResult => _lastMenuResult;

  WorkoutFeedback? get lastWorkoutFeedback =>
      _sessionHistory.isNotEmpty ? _sessionHistory.last.feedback : null;

  /// 現在の全54筋肉のリアルタイムM値情報を算出する
  Map<String, MuscleScoreInfo> computeCurrentMuscleScores() {
    return generator.computeMuscleScores(
      muscleStates: _muscleStates,
      profile: _profile,
      lastFeedback: lastWorkoutFeedback,
      now: now(),
    );
  }

  /// 永続化ストレージから状態を復元・初期化する
  Future<void> initialize() {
    final existing = _initFuture;
    if (existing != null) {
      return existing;
    }
    final future = _performInitialize();
    _initFuture = future;
    return future;
  }

  Future<void> _performInitialize() async {
    try {
      if (_authService == null || _repository == null) {
        final prefs = await SharedPreferences.getInstance();
        _authService ??= createAuthService(prefs: prefs);
        _repository ??= createWorkoutRepository(prefs: prefs);
      }

      final repo = _repository!;
      final auth = _authService!;

      final loadedUser = await auth.getCurrentUser();
      final loadedProfile = await repo.loadProfile();
      final effectiveProfile = loadedProfile ?? const UserProfile();

      final defaultMuscles = MasterData.defaultMuscleStates(
        effectiveProfile.purpose,
      );
      final loadedMuscles = await repo.loadMuscleStates();
      final mergedMuscles = <String, MuscleInputState>{
        for (final entry in defaultMuscles.entries)
          entry.key: _sanitizeMuscleState(
            loadedMuscles[entry.key] ?? entry.value,
          ),
      };

      final defaultHistory = MasterData.defaultMachineHistory();
      final loadedHistory = await repo.loadMachineHistory();
      final mergedHistory = <String, MachineHistoryEntry>{
        for (final entry in defaultHistory.entries)
          entry.key: loadedHistory[entry.key] ?? entry.value,
      };

      final loadedSessions = await repo.loadSessionHistory();
      final loadedCount = await repo.loadSessionCount();

      if (loadedMuscles.isEmpty) {
        await repo.saveMuscleStates(mergedMuscles);
      }
      if (loadedHistory.isEmpty) {
        await repo.saveMachineHistory(mergedHistory);
      }

      _currentUser = loadedUser;
      _profile = effectiveProfile;
      _muscleStates = mergedMuscles;
      _machineHistory = mergedHistory;
      _sessionHistory = List<WorkoutSessionRecord>.unmodifiable(loadedSessions);
      _sessionCount = loadedCount <= 0 ? 1 : loadedCount;
      _isInitialized = true;
      notifyListeners();
    } catch (_) {
      _isInitialized = true;
      notifyListeners();
    } finally {
      _initFuture = null;
    }
  }

  Future<WorkoutRepository> _ensureRepository() async {
    if (_repository != null) {
      return _repository!;
    }
    final prefs = await SharedPreferences.getInstance();
    _authService ??= createAuthService(prefs: prefs);
    _repository ??= createWorkoutRepository(prefs: prefs);
    return _repository!;
  }

  Future<AuthService> _ensureAuthService() async {
    if (_authService != null) {
      return _authService!;
    }
    final prefs = await SharedPreferences.getInstance();
    _authService ??= createAuthService(prefs: prefs);
    _repository ??= createWorkoutRepository(prefs: prefs);
    return _authService!;
  }

  static int _clampBlankDays(int value) =>
      value.clamp(minBlankDays, maxBlankDays);

  static double _clampStimulationDays(double value) {
    if (!value.isFinite) return 2.0;
    final clamped = value.clamp(minStimulationDays, maxStimulationDays);
    return double.parse(clamped.toStringAsFixed(1));
  }

  static int _clampPriorityP(int value) =>
      value.clamp(minPriorityP, maxPriorityP);

  static MuscleInputState _sanitizeMuscleState(MuscleInputState state) {
    return state.copyWith(
      blankDays: _clampBlankDays(state.blankDays),
      stimulationDays: _clampStimulationDays(state.stimulationDays),
      priorityP: _clampPriorityP(state.priorityP),
    );
  }

  /// 生成されたメニュー結果を記録する
  void recordGeneratedMenu(MenuGenerationResult result) {
    _lastMenuResult = result;
    notifyListeners();
  }

  /// トレーニング完了時の状態進行と履歴保存を一括適用する
  Future<void> completeWorkout(WorkoutCompletionResult result) async {
    final repo = await _ensureRepository();

    final nextMuscles = <String, MuscleInputState>{
      for (final entry in result.advanceResult.muscleStates.entries)
        entry.key: _sanitizeMuscleState(entry.value),
    };
    final nextHistory = Map<String, MachineHistoryEntry>.from(
      result.advanceResult.machineHistory,
    );
    final nextSessionCount = math.max(1, result.advanceResult.sessionCount);

    final updatedSessions = List<WorkoutSessionRecord>.from(_sessionHistory);
    final existingIdx = updatedSessions.indexWhere(
      (s) => s.id == result.sessionRecord.id,
    );
    if (existingIdx >= 0) {
      updatedSessions[existingIdx] = result.sessionRecord;
    } else {
      updatedSessions.add(result.sessionRecord);
    }

    final nextProfile = _profile.isFirstTime
        ? _profile.copyWith(isFirstTime: false)
        : _profile;

    _muscleStates = nextMuscles;
    _machineHistory = nextHistory;
    _sessionCount = nextSessionCount;
    _sessionHistory = List<WorkoutSessionRecord>.unmodifiable(updatedSessions);
    _lastMenuResult = result.menuResult;
    _profile = nextProfile;
    notifyListeners();

    await repo.saveProfile(_profile);
    await repo.saveMuscleStates(_muscleStates);
    await repo.saveMachineHistory(_machineHistory);
    await repo.saveSessionRecord(result.sessionRecord);
    await repo.saveSessionCount(_sessionCount);
  }

  /// トレーニング目的を変更し、既存の B_i / S_i / isInjured を保持したまま P_i テンプレートを適用する
  Future<void> updatePurpose(TrainingPurpose newPurpose) async {
    final repo = await _ensureRepository();
    final template =
        MasterData.purposePriorities[newPurpose] ?? const <String, int>{};

    final updatedMuscles = <String, MuscleInputState>{};
    for (final muscle in MasterData.muscles) {
      final current =
          _muscleStates[muscle.id] ??
          MuscleInputState(muscleId: muscle.id, priorityP: 10);
      updatedMuscles[muscle.id] = current.copyWith(
        priorityP: _clampPriorityP(template[muscle.id] ?? current.priorityP),
      );
    }

    _profile = _profile.copyWith(purpose: newPurpose);
    _muscleStates = updatedMuscles;
    notifyListeners();

    await repo.saveProfile(_profile);
    await repo.saveMuscleStates(_muscleStates);
  }

  /// 指定筋肉のケガ除外フラグを切り替える
  Future<void> toggleMuscleInjury(String muscleId, {bool? isInjured}) async {
    final current = _muscleStates[muscleId];
    if (current == null) return;
    final repo = await _ensureRepository();

    final nextInjured = isInjured ?? !current.isInjured;
    final updated = Map<String, MuscleInputState>.from(_muscleStates);
    updated[muscleId] = current.copyWith(isInjured: nextInjured);
    _muscleStates = updated;
    notifyListeners();

    await repo.saveMuscleStates(_muscleStates);
  }

  /// 個別筋肉の B_i / S_i / P_i / isInjured を更新・クランプして保存する
  Future<void> updateMuscleState(
    String muscleId, {
    int? blankDays,
    double? stimulationDays,
    int? priorityP,
    bool? isInjured,
  }) async {
    final current = _muscleStates[muscleId];
    if (current == null) return;
    final repo = await _ensureRepository();

    final nextState = current.copyWith(
      blankDays: blankDays != null
          ? _clampBlankDays(blankDays)
          : current.blankDays,
      stimulationDays: stimulationDays != null
          ? _clampStimulationDays(stimulationDays)
          : current.stimulationDays,
      priorityP: priorityP != null
          ? _clampPriorityP(priorityP)
          : current.priorityP,
      isInjured: isInjured ?? current.isInjured,
    );

    final updated = Map<String, MuscleInputState>.from(_muscleStates);
    updated[muscleId] = nextState;
    _muscleStates = updated;
    notifyListeners();

    await repo.saveMuscleStates(_muscleStates);
  }

  /// 指定された部位グループ（6大カテゴリ）に属する筋肉のみを一括調整する
  Future<void> applyGroupBatchAdjustment(
    MuscleGroup group, {
    int? blankDaysDelta,
    int? blankDaysSet,
    double? stimulationDaysDelta,
    double? stimulationDaysSet,
    int? priorityDelta,
    int? prioritySet,
  }) async {
    final repo = await _ensureRepository();
    final updated = Map<String, MuscleInputState>.from(_muscleStates);

    for (final muscle in MasterData.muscles) {
      if (muscle.group != group) {
        continue;
      }
      final current =
          updated[muscle.id] ??
          MuscleInputState(muscleId: muscle.id, priorityP: 10);

      var nextB = current.blankDays;
      if (blankDaysSet != null) {
        nextB = _clampBlankDays(blankDaysSet);
      } else if (blankDaysDelta != null) {
        nextB = _clampBlankDays(current.blankDays + blankDaysDelta);
      }

      var nextS = current.stimulationDays;
      if (stimulationDaysSet != null) {
        nextS = _clampStimulationDays(stimulationDaysSet);
      } else if (stimulationDaysDelta != null) {
        nextS = _clampStimulationDays(
          current.stimulationDays + stimulationDaysDelta,
        );
      }

      var nextP = current.priorityP;
      if (prioritySet != null) {
        nextP = _clampPriorityP(prioritySet);
      } else if (priorityDelta != null) {
        nextP = _clampPriorityP(current.priorityP + priorityDelta);
      }

      updated[muscle.id] = current.copyWith(
        blankDays: nextB,
        stimulationDays: nextS,
        priorityP: nextP,
      );
    }

    _muscleStates = updated;
    notifyListeners();

    await repo.saveMuscleStates(_muscleStates);
  }

  /// ユーザープロファイルを検証・更新し、性別変更時はボディーメイク目的を自動同期する
  Future<void> updateProfile({
    Gender? gender,
    int? birthYear,
    ExperienceLevel? experience,
    double? bodyWeightKg,
  }) async {
    final repo = await _ensureRepository();

    final nextGender = gender ?? _profile.gender;
    final nextBirthYear =
        (birthYear != null &&
            birthYear >= minValidBirthYear &&
            birthYear <= maxValidBirthYear)
        ? birthYear
        : _profile.birthYear;
    final nextExperience = experience ?? _profile.experience;
    final nextBodyWeight =
        (bodyWeightKg != null &&
            bodyWeightKg.isFinite &&
            bodyWeightKg >= minValidBodyWeightKg &&
            bodyWeightKg <= maxValidBodyWeightKg)
        ? double.parse(bodyWeightKg.toStringAsFixed(1))
        : _profile.bodyWeightKg;

    var nextPurpose = _profile.purpose;
    var purposeChanged = false;
    if (nextGender == Gender.female &&
        nextPurpose == TrainingPurpose.bodyMakeMale) {
      nextPurpose = TrainingPurpose.bodyMakeFemale;
      purposeChanged = true;
    } else if (nextGender == Gender.male &&
        nextPurpose == TrainingPurpose.bodyMakeFemale) {
      nextPurpose = TrainingPurpose.bodyMakeMale;
      purposeChanged = true;
    }

    _profile = _profile.copyWith(
      gender: nextGender,
      birthYear: nextBirthYear,
      experience: nextExperience,
      bodyWeightKg: nextBodyWeight,
      purpose: nextPurpose,
    );

    if (purposeChanged) {
      final template =
          MasterData.purposePriorities[nextPurpose] ?? const <String, int>{};
      final updatedMuscles = <String, MuscleInputState>{};
      for (final muscle in MasterData.muscles) {
        final current =
            _muscleStates[muscle.id] ??
            MuscleInputState(muscleId: muscle.id, priorityP: 10);
        updatedMuscles[muscle.id] = current.copyWith(
          priorityP: _clampPriorityP(template[muscle.id] ?? current.priorityP),
        );
      }
      _muscleStates = updatedMuscles;
    }

    notifyListeners();

    await repo.saveProfile(_profile);
    if (purposeChanged) {
      await repo.saveMuscleStates(_muscleStates);
    }
  }

  /// Google OAuth（または未設定時のローカルフォールバック）でログインする
  Future<AuthUser?> signInWithGoogle() async {
    final auth = await _ensureAuthService();
    final user = await auth.signInWithGoogle();
    _currentUser = user;
    notifyListeners();
    return user;
  }

  /// ログアウトする（ローカルのトレーニング履歴・プロファイルは保護される）
  Future<void> signOut() async {
    final auth = await _ensureAuthService();
    await auth.signOut();
    _currentUser = null;
    notifyListeners();
  }
}
