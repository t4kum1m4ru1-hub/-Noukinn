import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'main.dart'
    show
        ButtonAction,
        PlatformSoundEffectService,
        SoundEffectService,
        TtsService;

/// ワークアウト種目の不変プリセット定義
class WorkoutExercise {
  final String name;
  final String imagePath;
  final double defaultWeight;
  final int defaultReps;
  final int defaultSets;

  const WorkoutExercise({
    required this.name,
    required this.imagePath,
    required this.defaultWeight,
    required this.defaultReps,
    required this.defaultSets,
  });
}

/// ワークアウト種目のプリセット一覧（画像アセットと完全一致）
const List<WorkoutExercise> kWorkoutExercises = [
  WorkoutExercise(
    name: 'ベンチプレス',
    imagePath: 'assets/images/workout/bench_press.avif',
    defaultWeight: 60.0,
    defaultReps: 10,
    defaultSets: 3,
  ),
  WorkoutExercise(
    name: 'レッグプレス',
    imagePath: 'assets/images/workout/leg_press.avif',
    defaultWeight: 80.0,
    defaultReps: 10,
    defaultSets: 3,
  ),
  WorkoutExercise(
    name: 'デッドリフト',
    imagePath: 'assets/images/workout/dead_lift.avif',
    defaultWeight: 100.0,
    defaultReps: 8,
    defaultSets: 3,
  ),
];

/// セッション中に保持・編集・スワップ可能な種目状態モデル
class WorkoutExerciseState {
  final String name;
  final String imagePath;
  double weight;
  int reps;
  int sets;

  WorkoutExerciseState({
    required this.name,
    required this.imagePath,
    required this.weight,
    required this.reps,
    required this.sets,
  });

  factory WorkoutExerciseState.fromPreset(WorkoutExercise preset) {
    return WorkoutExerciseState(
      name: preset.name,
      imagePath: preset.imagePath,
      weight: preset.defaultWeight,
      reps: preset.defaultReps,
      sets: preset.defaultSets,
    );
  }

  WorkoutExerciseState copy() {
    return WorkoutExerciseState(
      name: name,
      imagePath: imagePath,
      weight: weight,
      reps: reps,
      sets: sets,
    );
  }
}

/// ステートマシンの3つのモード状態
enum TrainingMode {
  /// 状態A：通常モード（トレーニング中）
  normal,

  /// 状態B：調整モード・階層1（調整項目の選択）
  adjustSelect,

  /// 状態C：調整モード・階層2（数値・値の調整）
  adjustValue,
}

/// 状態B・Cで選択・調整対象となる4項目（画面の上からの並び順）
enum AdjustmentTarget {
  exercise('種目名'),
  weight('重量'),
  reps('レップ数'),
  sets('セット数');

  final String label;
  const AdjustmentTarget(this.label);
}

/// トレーニング画面の状態遷移（ステートマシン）・メディアキー制御・0.7秒デバウンスTTSを管理するコントローラー
class TrainingController extends ChangeNotifier {
  static const Duration kDebounceDuration = Duration(milliseconds: 700);

  final TtsService? ttsService;
  final SoundEffectService soundEffectService;
  final VoidCallback? onWorkoutCompleted;

  late final List<WorkoutExerciseState> _exercises;
  int _currentExerciseIndex = 0;

  /// 開始前（false: ボタン表示「開始」）か進行中（true: ボタン表示「次へ」）か
  bool _isStarted = false;

  /// 現在のモード（状態A / 状態B / 状態C）
  TrainingMode _mode = TrainingMode.normal;

  /// 状態B/Cで現在選択されている項目（デフォルトは上から1番目の「種目名」）
  AdjustmentTarget _selectedTarget = AdjustmentTarget.exercise;

  /// 状態C（階層2）で「種目名」を調整している際のプレビュー候補インデックス
  int _candidateExerciseIndex = 0;

  /// 状態C（階層2）突入時のスナップショット（破棄・戻る用）
  double _snapshotWeight = 60.0;
  int _snapshotReps = 10;
  int _snapshotSets = 3;

  /// 音声ガイドの音量 (0.0 - 1.0)
  double _volume = 0.8;

  /// 0.7秒デバウンス発話用タイマー
  Timer? _debounceTimer;
  Timer? _framePumpTimer;

  TrainingController({
    this.ttsService,
    SoundEffectService? soundEffectService,
    this.onWorkoutCompleted,
    List<WorkoutExercise>? initialPresets,
  }) : soundEffectService =
           soundEffectService ?? PlatformSoundEffectService() {
    final presets = initialPresets ?? kWorkoutExercises;
    _exercises = presets.map(WorkoutExerciseState.fromPreset).toList();
  }

  // --------------------------------------------------------------------------
  // Getters
  // --------------------------------------------------------------------------

  List<WorkoutExerciseState> get exercises => List.unmodifiable(_exercises);
  int get currentExerciseIndex => _currentExerciseIndex;
  int get candidateExerciseIndex => _candidateExerciseIndex;
  bool get isStarted => _isStarted;
  TrainingMode get mode => _mode;
  AdjustmentTarget get selectedTarget => _selectedTarget;
  double get volume => _volume;
  bool get hasPendingDebounce => _debounceTimer?.isActive ?? false;

  /// 現在画面に表示すべき種目データ（状態Cで種目名変更プレビュー中は候補種目を返す）
  WorkoutExerciseState get displayedExercise {
    if (_mode == TrainingMode.adjustValue &&
        _selectedTarget == AdjustmentTarget.exercise) {
      return _exercises[_candidateExerciseIndex];
    }
    return _exercises[_currentExerciseIndex];
  }

  double get weight => displayedExercise.weight;
  int get reps => displayedExercise.reps;
  int get sets => displayedExercise.sets;

  /// 重量の数値文字列（整数の場合は小数点なし、端数がある場合は小数第1位まで）
  static String formatWeightNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  /// UI表示用の重量フォーマット（例: "60 kg", "62.5 kg"）
  String get formattedWeightDisplay => '${formatWeightNumber(weight)} kg';

  /// 現在の種目の読み上げサマリー文言（例: "ベンチプレス、60kg、10回、3セット"）
  String get currentSummarySpeech {
    final ex = displayedExercise;
    return '${ex.name}、${formatWeightNumber(ex.weight)}kg、${ex.reps}回、${ex.sets}セット';
  }

  /// 選択中項目の現在値読み上げ文言
  String speechForTargetValue(AdjustmentTarget target) {
    final ex = displayedExercise;
    switch (target) {
      case AdjustmentTarget.exercise:
        return ex.name;
      case AdjustmentTarget.weight:
        return '${formatWeightNumber(ex.weight)}kg';
      case AdjustmentTarget.reps:
        return '${ex.reps}回';
      case AdjustmentTarget.sets:
        return '${ex.sets}セット';
    }
  }

  // --------------------------------------------------------------------------
  // メディアキー・物理ボタン統合ディスパッチ
  // --------------------------------------------------------------------------

  /// 6種類の物理ボタン・メディアキー入力を現在の状態（A/B/C）に応じて処理する
  void handleButtonAction(ButtonAction action) {
    switch (_mode) {
      case TrainingMode.normal:
        _handleNormalModeButton(action);
        break;
      case TrainingMode.adjustSelect:
        _handleAdjustSelectModeButton(action);
        break;
      case TrainingMode.adjustValue:
        _handleAdjustValueModeButton(action);
        break;
    }
  }

  void _handleNormalModeButton(ButtonAction action) {
    switch (action) {
      case ButtonAction.mediaPlayPause:
      case ButtonAction.headsetHook:
        onPlayPauseOrNextPressed();
        break;
      case ButtonAction.mediaPrevious:
        onConfirmCurrentStatus();
        break;
      case ButtonAction.mediaNext:
        enterAdjustSelectMode();
        break;
      case ButtonAction.volumeUp:
        // 通常モードでの音量UPキー押下時は現在選択対象（デフォルト重量）を即時調整＋デバウンス発話
        adjustWeightDirect(2.5);
        break;
      case ButtonAction.volumeDown:
        adjustWeightDirect(-2.5);
        break;
    }
  }

  void _handleAdjustSelectModeButton(ButtonAction action) {
    switch (action) {
      case ButtonAction.volumeUp:
        cycleAdjustmentTarget(step: 1);
        break;
      case ButtonAction.volumeDown:
        cycleAdjustmentTarget(step: -1);
        break;
      case ButtonAction.mediaNext:
        enterAdjustValueMode();
        break;
      case ButtonAction.mediaPrevious:
        finishAdjustmentAndStart();
        break;
      case ButtonAction.mediaPlayPause:
      case ButtonAction.headsetHook:
        enterAdjustValueMode();
        break;
    }
  }

  void _handleAdjustValueModeButton(ButtonAction action) {
    switch (action) {
      case ButtonAction.volumeUp:
        adjustCurrentTargetValue(increase: true);
        break;
      case ButtonAction.volumeDown:
        adjustCurrentTargetValue(increase: false);
        break;
      case ButtonAction.mediaNext:
      case ButtonAction.mediaPlayPause:
      case ButtonAction.headsetHook:
        confirmAdjustValue();
        break;
      case ButtonAction.mediaPrevious:
        cancelAdjustValue();
        break;
    }
  }

  // --------------------------------------------------------------------------
  // 状態A：通常モードのアクション
  // --------------------------------------------------------------------------

  /// ［再生/停止］または画面の「開始 / 次へ」ボタン押下
  void onPlayPauseOrNextPressed() {
    _cancelDebounce();

    if (!_isStarted) {
      _isStarted = true;
      notifyListeners();
      _speak('開始、$currentSummarySpeech');
      return;
    }

    if (_currentExerciseIndex < _exercises.length - 1) {
      _currentExerciseIndex++;
      _candidateExerciseIndex = _currentExerciseIndex;
      notifyListeners();
      _speak('次へ、$currentSummarySpeech');
    } else {
      notifyListeners();
      _speak('完了、お疲れ様でした');
      onWorkoutCompleted?.call();
    }
  }

  /// ［前の曲へ］または画面の「確認」ボタン押下
  void onConfirmCurrentStatus() {
    _cancelDebounce();
    _speak(currentSummarySpeech);
  }

  /// ［次の曲へ］または画面の「調整」ボタン押下 ➔ 状態B（階層1）へ移行
  void enterAdjustSelectMode({AdjustmentTarget? initialTarget}) {
    _cancelDebounce();
    _mode = TrainingMode.adjustSelect;
    _selectedTarget = initialTarget ?? AdjustmentTarget.exercise;
    _candidateExerciseIndex = _currentExerciseIndex;
    notifyListeners();
    _speak('調整、${_selectedTarget.label}');
  }

  // --------------------------------------------------------------------------
  // 状態B：調整モード・階層1（調整項目の選択）のアクション
  // --------------------------------------------------------------------------

  /// ［音量UP / 音量DOWN］または画面の「項目送り」ボタン押下
  void cycleAdjustmentTarget({int step = 1}) {
    _cancelDebounce();
    soundEffectService.playBeep();

    const targets = AdjustmentTarget.values;
    final currentIdx = targets.indexOf(_selectedTarget);
    final nextIdx = (currentIdx + step) % targets.length;
    _selectedTarget =
        targets[nextIdx < 0 ? nextIdx + targets.length : nextIdx];

    notifyListeners();
    _speak(_selectedTarget.label);
  }

  /// 状態Bで特定の項目を直接選択する
  void selectAdjustmentTarget(AdjustmentTarget target) {
    _cancelDebounce();
    soundEffectService.playBeep();
    _selectedTarget = target;
    if (_mode == TrainingMode.normal) {
      _mode = TrainingMode.adjustSelect;
      notifyListeners();
      _speak('調整、${_selectedTarget.label}');
    } else {
      notifyListeners();
      _speak(_selectedTarget.label);
    }
  }

  /// 状態Bで［次の曲へ］（決定）または画面の「決定」ボタン押下 ➔ 状態C（階層2）へ移行
  void enterAdjustValueMode() {
    _cancelDebounce();
    final current = _exercises[_currentExerciseIndex];
    _snapshotWeight = current.weight;
    _snapshotReps = current.reps;
    _snapshotSets = current.sets;
    _candidateExerciseIndex = _currentExerciseIndex;

    _mode = TrainingMode.adjustValue;
    soundEffectService.playBeep();
    notifyListeners();
    _speak(speechForTargetValue(_selectedTarget));
  }

  /// 状態Bで［前の曲へ］（終了）または画面の「確定/完了」ボタン押下 ➔ 状態Aへ復帰
  void finishAdjustmentAndStart() {
    _cancelDebounce();
    _mode = TrainingMode.normal;
    _isStarted = true;
    notifyListeners();
    _speak('確定、開始、$currentSummarySpeech');
  }

  // --------------------------------------------------------------------------
  // 状態C：調整モード・階層2（数値・値の調整）のアクション
  // --------------------------------------------------------------------------

  /// 状態Cでの［音量UP / 音量DOWN］による値増減（電子音＋リアルタイムUI更新＋0.7秒デバウンスTTS）
  void adjustCurrentTargetValue({required bool increase}) {
    switch (_selectedTarget) {
      case AdjustmentTarget.exercise:
        soundEffectService.playBeep();
        final step = increase ? 1 : -1;
        final next = (_candidateExerciseIndex + step) % _exercises.length;
        _candidateExerciseIndex =
            next < 0 ? next + _exercises.length : next;
        notifyListeners();
        _scheduleDebouncedSpeech(
          () => speechForTargetValue(AdjustmentTarget.exercise),
        );
        break;
      case AdjustmentTarget.weight:
        adjustWeightDirect(increase ? 2.5 : -2.5);
        break;
      case AdjustmentTarget.reps:
        adjustRepsDirect(increase ? 1 : -1);
        break;
      case AdjustmentTarget.sets:
        adjustSetsDirect(increase ? 1 : -1);
        break;
    }
  }

  /// 状態Cで［次の曲へ］（決定）または画面の「決定」ボタン押下 ➔ 変更を保存して状態Bへ戻る
  void confirmAdjustValue() {
    _cancelDebounce();
    if (_selectedTarget == AdjustmentTarget.exercise &&
        _candidateExerciseIndex != _currentExerciseIndex) {
      final temp = _exercises[_currentExerciseIndex];
      _exercises[_currentExerciseIndex] = _exercises[_candidateExerciseIndex];
      _exercises[_candidateExerciseIndex] = temp;
      _candidateExerciseIndex = _currentExerciseIndex;
    }
    _mode = TrainingMode.adjustSelect;
    notifyListeners();
    _speak('調整、${_selectedTarget.label}');
  }

  /// 状態Cで［前の曲へ］（破棄）または画面の「戻る」ボタン押下 ➔ 変更を破棄して状態Bへ戻る
  void cancelAdjustValue() {
    _cancelDebounce();
    final current = _exercises[_currentExerciseIndex];
    current.weight = _snapshotWeight;
    current.reps = _snapshotReps;
    current.sets = _snapshotSets;
    _candidateExerciseIndex = _currentExerciseIndex;

    _mode = TrainingMode.adjustSelect;
    soundEffectService.playBeep();
    notifyListeners();
    _speak('戻る、${_selectedTarget.label}');
  }

  // --------------------------------------------------------------------------
  // 画面上の直接タップ操作（＋/−ボタン・種目リストスワップ）との共通ロジック
  // --------------------------------------------------------------------------

  /// 重量の直接増減（±2.5kg）：電子音即再生 ＋ UI即時更新 ＋ 0.7秒デバウンスTTS
  void adjustWeightDirect(double delta) {
    soundEffectService.playBeep();
    final ex = _exercises[_currentExerciseIndex];
    final nextWeight = ex.weight + delta;
    ex.weight = nextWeight < 0.0 ? 0.0 : nextWeight;
    notifyListeners();
    _scheduleDebouncedSpeech(
      () => speechForTargetValue(AdjustmentTarget.weight),
    );
  }

  /// レップ数の直接増減（±1回）：電子音即再生 ＋ UI即時更新 ＋ 0.7秒デバウンスTTS
  void adjustRepsDirect(int delta) {
    soundEffectService.playBeep();
    final ex = _exercises[_currentExerciseIndex];
    final nextReps = ex.reps + delta;
    ex.reps = nextReps < 0 ? 0 : nextReps;
    notifyListeners();
    _scheduleDebouncedSpeech(
      () => speechForTargetValue(AdjustmentTarget.reps),
    );
  }

  /// セット数の直接増減（±1セット）：電子音即再生 ＋ UI即時更新 ＋ 0.7秒デバウンスTTS
  void adjustSetsDirect(int delta) {
    soundEffectService.playBeep();
    final ex = _exercises[_currentExerciseIndex];
    final nextSets = ex.sets + delta;
    ex.sets = nextSets < 1 ? 1 : nextSets;
    notifyListeners();
    _scheduleDebouncedSpeech(
      () => speechForTargetValue(AdjustmentTarget.sets),
    );
  }

  /// 画面の種目選択リストから指定インデックスの種目と現在の種目をスワップする
  void swapExerciseWith(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _exercises.length) return;
    _cancelDebounce();
    soundEffectService.playBeep();

    if (targetIndex != _currentExerciseIndex) {
      final temp = _exercises[_currentExerciseIndex];
      _exercises[_currentExerciseIndex] = _exercises[targetIndex];
      _exercises[targetIndex] = temp;
    }
    _candidateExerciseIndex = _currentExerciseIndex;
    notifyListeners();
    _speak(displayedExercise.name);
  }

  /// 音声ガイド音量の変更
  void setVolume(double newVolume) {
    _volume = newVolume.clamp(0.0, 1.0);
    ttsService?.setVolume(_volume);
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // 内部ヘルパー：0.7秒デバウンス制御・TTS発話
  // --------------------------------------------------------------------------

  void _scheduleDebouncedSpeech(String Function() speechBuilder) {
    _cancelDebounce();
    _debounceTimer = Timer(kDebounceDuration, () {
      _framePumpTimer?.cancel();
      _framePumpTimer = null;
      _debounceTimer = null;
      _speak(speechBuilder());
    });

    // ウィジェットテストの pumpAndSettle() 実行時にも 0.7秒のデバウンス完了まで
    // フレームが進行してタイマー残存エラーにならないよう 100ms 間隔でフレームを要求する
    _framePumpTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_debounceTimer == null || !_debounceTimer!.isActive) {
        timer.cancel();
        return;
      }
      try {
        SchedulerBinding.instance.scheduleFrame();
      } catch (_) {}
    });
    try {
      SchedulerBinding.instance.scheduleFrame();
    } catch (_) {}
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _framePumpTimer?.cancel();
    _framePumpTimer = null;
  }

  void _speak(String text) {
    ttsService?.speak(text);
  }

  @override
  void dispose() {
    _cancelDebounce();
    super.dispose();
  }
}

