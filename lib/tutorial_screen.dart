import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'main.dart'
    show
        AudioDuckingController,
        AudioSessionDuckingController,
        ButtonAction,
        FakeAudioDuckingController,
        FlutterTtsService,
        KeyEventChannelDispatcher,
        SoundEffectService,
        TtsService;
import 'theme/app_colors.dart';
import 'training_screen.dart';

/// チュートリアルの全6ステップ（Step 1/5 〜 Step 5/5 ＋ Step 6 完了画面）
enum TutorialStep {
  /// Step 1 (Step 1/5): チュートリアル開始＆トレーニング開始操作
  step1Start,

  /// Step 2 (Step 2/5): 調整モードへの突入 (Step 2-1) ＆ 調整項目の選択 (Step 2-2)
  step2Select,

  /// Step 3 (Step 3/5): 選択項目の数値・内容調整（0.7秒デバウンスTTS体験）
  step3Adjust,

  /// Step 4 (Step 4/5): 調整モードの終了（完了）
  step4FinishAdjust,

  /// Step 5 (Step 5/5): トレーニング内容の再確認（通常画面維持＋前曲で確認）
  step5Reconfirm,

  /// Step 6: チュートリアル完了画面（最初のトレーニングを開始する）
  step6Complete,
}

/// Step 2 内のサブフェーズ（Step 2-1 / Step 2-2）
enum Step2Phase {
  /// Step 2-1: 曲送り（次の曲へ進む）による調整モードへの突入待ち
  enterMode,

  /// Step 2-2: 音量(+/-)による調整項目選択と再生停止による決定待ち
  cycleItem,
}

/// Step 2-2 で選択し Step 3 で調整するトレーニング項目
enum TutorialItem {
  exerciseName('種目名'),
  weight('重量'),
  reps('レップ数'),
  sets('セット数');

  final String label;
  const TutorialItem(this.label);

  /// 次の項目へ巡回（循環）
  TutorialItem get next {
    switch (this) {
      case TutorialItem.exerciseName:
        return TutorialItem.weight;
      case TutorialItem.weight:
        return TutorialItem.reps;
      case TutorialItem.reps:
        return TutorialItem.sets;
      case TutorialItem.sets:
        return TutorialItem.exerciseName;
    }
  }

  /// 前の項目へ巡回（逆循環）
  TutorialItem get previous {
    switch (this) {
      case TutorialItem.exerciseName:
        return TutorialItem.sets;
      case TutorialItem.weight:
        return TutorialItem.exerciseName;
      case TutorialItem.reps:
        return TutorialItem.weight;
      case TutorialItem.sets:
        return TutorialItem.reps;
    }
  }
}

/// インタラクティブな操作チュートリアル画面
class TutorialScreen extends StatefulWidget {
  final TtsService? ttsService;
  final SoundEffectService? soundEffectService;
  final AudioDuckingController? duckingController;
  final bool? animateGlow;

  const TutorialScreen({
    super.key,
    this.ttsService,
    this.soundEffectService,
    this.duckingController,
    this.animateGlow,
  });

  /// 数値フォーマット用ヘルパー（整数の場合は小数点なし、端数は小数第1位）
  static String formatWeightNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  static String formatWeightSpeech(double val) => '${formatWeightNumber(val)}キロ';
  static String formatWeightDisplay(double val) =>
      '${formatWeightNumber(val)} kg';

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _presetExercises = [
    'ベンチプレス',
    'レッグプレス',
    'デッドリフト',
  ];

  late final AudioDuckingController _duckingController;
  late final FocusNode _keyboardFocusNode;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  // 状態変数
  TutorialStep _currentStep = TutorialStep.step1Start;
  Step2Phase _step2Phase = Step2Phase.enterMode;
  TutorialItem _selectedItem = TutorialItem.exerciseName;

  /// Step 1 ➔ Step 2 遷移中（開始の音声案内読み上げ中）フラグ
  bool _isStep1Starting = false;

  int _exerciseIndex = 0;
  double _currentWeight = 60.0;
  int _currentReps = 10;
  int _currentSets = 3;

  String get _currentExercise => _presetExercises[_exerciseIndex];

  Rect? _spotlightRect;
  bool _isNavigating = false;
  bool _isStepTransitioning = false;
  int _transitionGeneration = 0;

  // デバウンスタイマー
  Timer? _debounceTimer;
  Timer? _framePumpTimer;

  // GlobalKeys
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _startBtnKey = GlobalKey();
  final GlobalKey _exerciseCardKey = GlobalKey();
  final GlobalKey _weightCardKey = GlobalKey();
  final GlobalKey _repsCardKey = GlobalKey();
  final GlobalKey _setsCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _duckingController = widget.duckingController ??
        (SchedulerBinding.instance.runtimeType
                .toString()
                .contains('TestWidgetsFlutterBinding')
            ? FakeAudioDuckingController()
            : AudioSessionDuckingController());
    widget.ttsService?.initialize();
    KeyEventChannelDispatcher.instance.registerListener(_handleButtonAction);
    _keyboardFocusNode = FocusNode();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    );

    _startGlowIfNeeded();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
        _updateSpotlightRect();
        unawaited(
          _speak('チュートリアルを開始します。再生停止操作でトレーニングを開始します。'),
        );
      }
    });
  }

  bool get _effectiveAnimateGlow =>
      widget.animateGlow ??
      !SchedulerBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');

  void _startGlowIfNeeded() {
    final shouldGlow = _effectiveAnimateGlow &&
        _currentStep != TutorialStep.step5Reconfirm &&
        _currentStep != TutorialStep.step6Complete;
    if (shouldGlow) {
      if (!_glowController.isAnimating) {
        _glowController.repeat(reverse: true);
      }
    } else {
      if (_glowController.isAnimating) {
        _glowController.stop();
      }
      _glowController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _transitionGeneration++;
    _isStepTransitioning = false;
    KeyEventChannelDispatcher.instance.unregisterListener(_handleButtonAction);
    _cancelDebounce();
    _glowController.dispose();
    _keyboardFocusNode.dispose();
    widget.ttsService?.stop();
    _duckingController.releaseDucking();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 音声発話・効果音
  // --------------------------------------------------------------------------

  Future<void> _speak(String text, {bool waitForCompletion = false}) async {
    if (!mounted) return;
    try {
      await _duckingController.requestDucking();
      if (!mounted) return;
      await widget.ttsService?.stop();
      if (!mounted) return;
      final tts = widget.ttsService;
      if (tts is FlutterTtsService && waitForCompletion) {
        await tts.speakAndWait(text);
      } else {
        await tts?.speak(text);
      }
    } catch (e) {
      debugPrint('TutorialScreen._speak error: $e');
    }
  }

  Future<void> _playBeep() async {
    if (!mounted) return;
    try {
      await _duckingController.requestDucking();
      if (!mounted) return;
      await widget.soundEffectService?.playBeep();
    } catch (e) {
      debugPrint('TutorialScreen._playBeep error: $e');
    }
  }

  /// 現在選択されている項目の設定値読み上げ文字列を返す
  String _getSelectedItemValueSpeech() {
    switch (_selectedItem) {
      case TutorialItem.exerciseName:
        return _currentExercise;
      case TutorialItem.weight:
        return TutorialScreen.formatWeightSpeech(_currentWeight);
      case TutorialItem.reps:
        return '$_currentReps回';
      case TutorialItem.sets:
        return '$_currentSetsセット';
    }
  }

  /// 現在のトレーニング内容全体の確認読み上げ文字列を返す
  String get _currentSummarySpeech =>
      '$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット';

  // --------------------------------------------------------------------------
  // 0.7秒デバウンス制御
  // --------------------------------------------------------------------------

  void _startValueDebounce(String Function() speechBuilder) {
    _cancelDebounce();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      _framePumpTimer?.cancel();
      _framePumpTimer = null;
      _debounceTimer = null;
      if (!mounted || _currentStep != TutorialStep.step3Adjust) return;
      _speak(speechBuilder());
    });

    _framePumpTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
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

  // --------------------------------------------------------------------------
  // 画面遷移
  // --------------------------------------------------------------------------

  void _navigateToTrainingScreen() {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    _transitionGeneration++;
    _isStepTransitioning = false;
    _cancelDebounce();
    widget.ttsService?.stop();
    _duckingController.releaseDucking();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TrainingScreen(
          ttsService: widget.ttsService,
          soundEffectService: widget.soundEffectService,
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ボタンアクション集約ハンドラ
  // --------------------------------------------------------------------------

  void _handleButtonAction(ButtonAction action) {
    if (!mounted || _isNavigating || _isStepTransitioning) return;

    final effectiveAction = (action == ButtonAction.headsetHook)
        ? ButtonAction.mediaPlayPause
        : action;

    switch (_currentStep) {
      case TutorialStep.step1Start:
        if (effectiveAction == ButtonAction.mediaPlayPause) {
          _proceedFromStep1();
        }
        break;

      case TutorialStep.step2Select:
        _handleStep2Action(effectiveAction);
        break;

      case TutorialStep.step3Adjust:
        _handleStep3Action(effectiveAction);
        break;

      case TutorialStep.step4FinishAdjust:
        _handleStep4Action(effectiveAction);
        break;

      case TutorialStep.step5Reconfirm:
        _handleStep5Action(effectiveAction);
        break;

      case TutorialStep.step6Complete:
        if (effectiveAction == ButtonAction.mediaPlayPause) {
          _navigateToTrainingScreen();
        }
        break;
    }
  }

  /// Step 1 ➔ Step 2-1 の遷移演出
  Future<void> _proceedFromStep1() async {
    if (_isStepTransitioning) return;
    _isStepTransitioning = true;
    final int gen = ++_transitionGeneration;
    setState(() {
      _isStep1Starting = true;
    });
    try {
      await _playBeep();
      if (!mounted ||
          _currentStep != TutorialStep.step1Start ||
          gen != _transitionGeneration) {
        return;
      }
      await _speak(
        '開始、$_currentSummarySpeech',
        waitForCompletion: true,
      );
      if (!mounted ||
          _currentStep != TutorialStep.step1Start ||
          gen != _transitionGeneration) {
        return;
      }
      setState(() {
        _isStep1Starting = false;
        _currentStep = TutorialStep.step2Select;
        _step2Phase = Step2Phase.enterMode;
      });
      _startGlowIfNeeded();
      _updateSpotlightRect();
      await _speak('トレーニングの調整をしましょう。曲送り操作で調整をします。');
    } finally {
      if (mounted && gen == _transitionGeneration) {
        _isStepTransitioning = false;
      }
    }
  }

  /// Step 2 (Step 2-1: 調整モード突入 / Step 2-2: 項目選択)
  Future<void> _handleStep2Action(ButtonAction action) async {
    // Step 2-1 / Step 2-2 ともに前曲（確認）は無効化（反応なし）
    if (action == ButtonAction.mediaPrevious) {
      return;
    }

    if (_step2Phase == Step2Phase.enterMode) {
      if (action == ButtonAction.mediaNext) {
        if (_isStepTransitioning) return;
        _isStepTransitioning = true;
        final int gen = ++_transitionGeneration;
        try {
          await _playBeep();
          if (!mounted ||
              _currentStep != TutorialStep.step2Select ||
              _step2Phase != Step2Phase.enterMode ||
              gen != _transitionGeneration) {
            return;
          }
          setState(() {
            _step2Phase = Step2Phase.cycleItem;
            _selectedItem = TutorialItem.exerciseName;
          });
          _updateSpotlightRect();
          await _speak(
            '調整、種目名。音量操作で調整項目を選択し、再生停止操作で決定しましょう',
          );
        } finally {
          if (mounted && gen == _transitionGeneration) {
            _isStepTransitioning = false;
          }
        }
      }
    } else {
      if (action == ButtonAction.volumeUp) {
        await _playBeep();
        if (!mounted ||
            _currentStep != TutorialStep.step2Select ||
            _step2Phase != Step2Phase.cycleItem) {
          return;
        }
        setState(() {
          _selectedItem = _selectedItem.next;
        });
        _updateSpotlightRect();
        await _speak(_selectedItem.label);
      } else if (action == ButtonAction.volumeDown) {
        await _playBeep();
        if (!mounted ||
            _currentStep != TutorialStep.step2Select ||
            _step2Phase != Step2Phase.cycleItem) {
          return;
        }
        setState(() {
          _selectedItem = _selectedItem.previous;
        });
        _updateSpotlightRect();
        await _speak(_selectedItem.label);
      } else if (action == ButtonAction.mediaPlayPause) {
        if (_isStepTransitioning) return;
        _isStepTransitioning = true;
        final int gen = ++_transitionGeneration;
        try {
          await _playBeep();
          if (!mounted ||
              _currentStep != TutorialStep.step2Select ||
              _step2Phase != Step2Phase.cycleItem ||
              gen != _transitionGeneration) {
            return;
          }
          await _speak(
            '${_selectedItem.label}を調整します。',
            waitForCompletion: true,
          );
          if (!mounted ||
              _currentStep != TutorialStep.step2Select ||
              _step2Phase != Step2Phase.cycleItem ||
              gen != _transitionGeneration) {
            return;
          }
          setState(() {
            _currentStep = TutorialStep.step3Adjust;
          });
          _startGlowIfNeeded();
          _updateSpotlightRect();
          await _speak(
            '音量操作で${_selectedItem.label}を調整してください。再生停止で決定します。${_getSelectedItemValueSpeech()}',
          );
        } finally {
          if (mounted && gen == _transitionGeneration) {
            _isStepTransitioning = false;
          }
        }
      }
    }
  }

  /// Step 3: 選択項目の数値・内容調整
  Future<void> _handleStep3Action(ButtonAction action) async {
    // 前曲（確認）は無効化（反応なし）
    if (action == ButtonAction.mediaPrevious) {
      return;
    }

    if (action == ButtonAction.volumeUp || action == ButtonAction.volumeDown) {
      final bool isUp = action == ButtonAction.volumeUp;
      await _playBeep();
      if (!mounted || _currentStep != TutorialStep.step3Adjust) return;
      setState(() {
        switch (_selectedItem) {
          case TutorialItem.exerciseName:
            final step = isUp ? 1 : -1;
            final next = (_exerciseIndex + step) % _presetExercises.length;
            _exerciseIndex =
                next < 0 ? next + _presetExercises.length : next;
            break;
          case TutorialItem.weight:
            _currentWeight =
                (_currentWeight + (isUp ? 2.5 : -2.5)).clamp(0.0, 500.0);
            break;
          case TutorialItem.reps:
            _currentReps = (_currentReps + (isUp ? 1 : -1)).clamp(1, 100);
            break;
          case TutorialItem.sets:
            _currentSets = (_currentSets + (isUp ? 1 : -1)).clamp(1, 20);
            break;
        }
      });
      _startValueDebounce(_getSelectedItemValueSpeech);
    } else if (action == ButtonAction.mediaPlayPause) {
      if (_isStepTransitioning) return;
      _isStepTransitioning = true;
      _cancelDebounce();
      final int gen = ++_transitionGeneration;
      try {
        await _playBeep();
        if (!mounted ||
            _currentStep != TutorialStep.step3Adjust ||
            gen != _transitionGeneration) {
          return;
        }
        setState(() {
          _currentStep = TutorialStep.step4FinishAdjust;
        });
        _startGlowIfNeeded();
        _updateSpotlightRect();
        await _speak('曲送り操作で調整を完了します。調整、${_selectedItem.label}');
      } finally {
        if (mounted && gen == _transitionGeneration) {
          _isStepTransitioning = false;
        }
      }
    }
  }

  /// Step 4: 調整モードの終了（完了）
  Future<void> _handleStep4Action(ButtonAction action) async {
    if (action == ButtonAction.mediaNext) {
      if (_isStepTransitioning) return;
      _isStepTransitioning = true;
      final int gen = ++_transitionGeneration;
      try {
        await _playBeep();
        if (!mounted ||
            _currentStep != TutorialStep.step4FinishAdjust ||
            gen != _transitionGeneration) {
          return;
        }
        await _speak('確定', waitForCompletion: true);
        if (!mounted ||
            _currentStep != TutorialStep.step4FinishAdjust ||
            gen != _transitionGeneration) {
          return;
        }
        setState(() {
          _currentStep = TutorialStep.step5Reconfirm;
        });
        _startGlowIfNeeded();
        _updateSpotlightRect();
        await _speak(
          'トレーニングの調整が完了しました。曲戻し操作でトレーニングの内容を再確認しましょう。',
        );
      } finally {
        if (mounted && gen == _transitionGeneration) {
          _isStepTransitioning = false;
        }
      }
    }
  }

  /// Step 5: トレーニング内容の再確認
  Future<void> _handleStep5Action(ButtonAction action) async {
    if (action == ButtonAction.mediaPrevious) {
      if (_isStepTransitioning) return;
      _isStepTransitioning = true;
      final int gen = ++_transitionGeneration;
      try {
        await _speak(_currentSummarySpeech, waitForCompletion: true);
        if (!mounted ||
            _currentStep != TutorialStep.step5Reconfirm ||
            gen != _transitionGeneration) {
          return;
        }
        setState(() {
          _currentStep = TutorialStep.step6Complete;
        });
        _startGlowIfNeeded();
        _updateSpotlightRect();
        await _speak('チュートリアルは以上です。');
      } finally {
        if (mounted && gen == _transitionGeneration) {
          _isStepTransitioning = false;
        }
      }
    }
  }

  void _onSkipStepPressed() {
    _transitionGeneration++;
    _isStepTransitioning = false;
    _cancelDebounce();
    widget.ttsService?.stop();
    _duckingController.releaseDucking();

    String? nextSpeech;

    setState(() {
      _isStep1Starting = false;
      switch (_currentStep) {
        case TutorialStep.step1Start:
          _currentStep = TutorialStep.step2Select;
          _step2Phase = Step2Phase.enterMode;
          nextSpeech = 'トレーニングの調整をしましょう。曲送り操作で調整をします。';
          break;
        case TutorialStep.step2Select:
          _currentStep = TutorialStep.step3Adjust;
          nextSpeech =
              '音量操作で${_selectedItem.label}を調整してください。再生停止で決定します。${_getSelectedItemValueSpeech()}';
          break;
        case TutorialStep.step3Adjust:
          _currentStep = TutorialStep.step4FinishAdjust;
          nextSpeech = '曲送り操作で調整を完了します。調整、${_selectedItem.label}';
          break;
        case TutorialStep.step4FinishAdjust:
          _currentStep = TutorialStep.step5Reconfirm;
          nextSpeech =
              'トレーニングの調整が完了しました。曲戻し操作でトレーニングの内容を再確認しましょう。';
          break;
        case TutorialStep.step5Reconfirm:
          _currentStep = TutorialStep.step6Complete;
          nextSpeech = 'チュートリアルは以上です。';
          break;
        case TutorialStep.step6Complete:
          _navigateToTrainingScreen();
          break;
      }
    });
    _startGlowIfNeeded();
    _updateSpotlightRect();
    if (nextSpeech != null) {
      unawaited(_speak(nextSpeech!));
    }
  }

  // --------------------------------------------------------------------------
  // キーボードイベント（PC / エミュレータ）
  // --------------------------------------------------------------------------

  KeyEventResult _handleKeyboardEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _handleButtonAction(ButtonAction.mediaPlayPause);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      _handleButtonAction(ButtonAction.mediaPrevious);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      _handleButtonAction(ButtonAction.mediaNext);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.audioVolumeUp) {
      _handleButtonAction(ButtonAction.volumeUp);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.audioVolumeDown) {
      _handleButtonAction(ButtonAction.volumeDown);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --------------------------------------------------------------------------
  // スポットライト座標解決
  // --------------------------------------------------------------------------

  GlobalKey _getCardKeyForItem(TutorialItem item) {
    switch (item) {
      case TutorialItem.exerciseName:
        return _exerciseCardKey;
      case TutorialItem.weight:
        return _weightCardKey;
      case TutorialItem.reps:
        return _repsCardKey;
      case TutorialItem.sets:
        return _setsCardKey;
    }
  }

  GlobalKey? _getCurrentTargetKey() {
    switch (_currentStep) {
      case TutorialStep.step1Start:
        return _startBtnKey;
      case TutorialStep.step2Select:
        if (_step2Phase == Step2Phase.enterMode) {
          return _exerciseCardKey;
        }
        return _getCardKeyForItem(_selectedItem);
      case TutorialStep.step3Adjust:
      case TutorialStep.step4FinishAdjust:
        return _getCardKeyForItem(_selectedItem);
      case TutorialStep.step5Reconfirm:
      case TutorialStep.step6Complete:
        return null;
    }
  }

  void _updateSpotlightRect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetKey = _getCurrentTargetKey();
      if (targetKey == null || targetKey.currentContext == null) {
        if (_spotlightRect != null) {
          setState(() => _spotlightRect = null);
        }
        return;
      }

      final renderBox =
          targetKey.currentContext!.findRenderObject() as RenderBox?;
      final stackBox =
          _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null &&
          renderBox.hasSize &&
          stackBox != null &&
          stackBox.hasSize) {
        final globalPos = renderBox.localToGlobal(Offset.zero);
        final localPos = stackBox.globalToLocal(globalPos);
        final newRect = localPos & renderBox.size;
        if (_spotlightRect != newRect) {
          setState(() => _spotlightRect = newRect);
        }
      }
    });
  }

  /// 画面タップによる進行バックアップ処理
  void _onScreenOverlayTap() {
    switch (_currentStep) {
      case TutorialStep.step1Start:
        _proceedFromStep1();
        break;
      case TutorialStep.step2Select:
        if (_step2Phase == Step2Phase.enterMode) {
          _handleButtonAction(ButtonAction.mediaNext);
        } else {
          _handleButtonAction(ButtonAction.mediaPlayPause);
        }
        break;
      case TutorialStep.step3Adjust:
        _handleButtonAction(ButtonAction.mediaPlayPause);
        break;
      case TutorialStep.step4FinishAdjust:
        _handleButtonAction(ButtonAction.mediaNext);
        break;
      case TutorialStep.step5Reconfirm:
        _handleButtonAction(ButtonAction.mediaPrevious);
        break;
      case TutorialStep.step6Complete:
        break;
    }
  }

  // --------------------------------------------------------------------------
  // UI 構築
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool showSpotlightOverlay =
        _currentStep != TutorialStep.step5Reconfirm &&
            _currentStep != TutorialStep.step6Complete;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _transitionGeneration++;
          _isStepTransitioning = false;
          _cancelDebounce();
          widget.ttsService?.stop();
          _duckingController.releaseDucking();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          title: const Text(
            '操作チュートリアル',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '戻る',
            onPressed: () {
              _transitionGeneration++;
              _isStepTransitioning = false;
              _cancelDebounce();
              widget.ttsService?.stop();
              _duckingController.releaseDucking();
              Navigator.of(context).pop();
            },
          ),
          actions: [
            TextButton(
              key: const Key('btn_appbar_skip_training'),
              onPressed: _navigateToTrainingScreen,
              child: const Text(
                '本編へ',
                style: TextStyle(
                  color: AppColors.tealAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        body: Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyboardEvent,
          child: Stack(
            fit: StackFit.expand,
            key: _stackKey,
            children: [
              // 1. 下層：ワークアウト表示レイアウト（Step 5 では通常画面としてそのまま表示）
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _currentStep == TutorialStep.step5Reconfirm
                      ? _onScreenOverlayTap
                      : null,
                  child: _buildWorkoutBackground(),
                ),
              ),

              // 2. 中層：スポットライト＆暗転オーバーレイ（Step 1〜4 で有効）
              if (showSpotlightOverlay) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _onScreenOverlayTap,
                    child: CustomPaint(
                      painter: SpotlightOverlayPainter(
                        targetRect: _spotlightRect,
                      ),
                    ),
                  ),
                ),
                // 外側のみが呼吸するように明滅発光するホタル枠線（要素手前はクリア）
                _buildGlowOverlay(),
              ],

              // 3. 上層：フローティングガイダンスカード（Step 1〜5）
              if (_currentStep != TutorialStep.step6Complete)
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: _buildGuidanceCard(),
                ),

              // 4. Step 1 開始音声読み上げ中の画面中央案内オーバーレイ
              if (_isStep1Starting)
                Positioned.fill(
                  child: _buildStep1StartingCenterNotice(),
                ),

              // 5. Step 6 専用全画面完了カード
              if (_currentStep == TutorialStep.step6Complete)
                Positioned.fill(
                  child: _buildStep6CelebrationOverlay(),
                ),

              // 6. 右下スキップボタン（Step 1〜5）
              if (_currentStep != TutorialStep.step6Complete)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _buildSkipButton(),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: _buildMediaControlBar(),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 下層：ワークアウト画面コンポーネント
  // --------------------------------------------------------------------------

  bool _isItemHighlighted(TutorialItem item) {
    if (_currentStep == TutorialStep.step2Select &&
        _step2Phase == Step2Phase.cycleItem) {
      return _selectedItem == item;
    }
    if (_currentStep == TutorialStep.step3Adjust ||
        _currentStep == TutorialStep.step4FinishAdjust) {
      return _selectedItem == item;
    }
    return false;
  }

  Widget _buildWorkoutBackground() {
    final bool isExerciseHighlighted =
        _isItemHighlighted(TutorialItem.exerciseName);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 種目名カード
          Container(
            key: _exerciseCardKey,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isExerciseHighlighted
                    ? AppColors.tealAccent
                    : AppColors.border,
                width: isExerciseHighlighted ? 2.0 : 1.5,
              ),
            ),
            child: Center(
              child: Text(
                _currentExercise,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isExerciseHighlighted
                      ? AppColors.tealAccent
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3つの調整カード（重量・レップ数・セット数）
          Row(
            children: [
              // 重量カード
              Expanded(
                child: Container(
                  key: _weightCardKey,
                  child: _buildValueCard(
                    cardKey: const Key('card_weight'),
                    label: '重量',
                    value: TutorialScreen.formatWeightDisplay(_currentWeight),
                    isSelected: _isItemHighlighted(TutorialItem.weight),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // レップ数カード
              Expanded(
                child: Container(
                  key: _repsCardKey,
                  child: _buildValueCard(
                    cardKey: const Key('card_reps'),
                    label: 'レップ数',
                    value: '$_currentReps 回',
                    isSelected: _isItemHighlighted(TutorialItem.reps),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // セット数カード（分数表記ではなく総セット数のみ表示）
              Expanded(
                child: Container(
                  key: _setsCardKey,
                  child: _buildValueCard(
                    cardKey: const Key('card_sets'),
                    label: 'セット数',
                    value: '$_currentSets',
                    isSelected: _isItemHighlighted(TutorialItem.sets),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // 中央アクションボタン
          Center(
            child: SizedBox(
              key: _startBtnKey,
              width: 180,
              height: 54,
              child: ElevatedButton.icon(
                key: const Key('btn_next_workout'),
                onPressed: _onScreenOverlayTap,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: Text(
                  _currentStep == TutorialStep.step1Start ? '開始' : '次へ',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.onPrimaryAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(27),
                  ),
                  elevation: 4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueCard({
    required Key cardKey,
    required String label,
    required String value,
    required bool isSelected,
  }) {
    return Container(
      key: cardKey,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.tealAccent : AppColors.border,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color:
                    isSelected ? AppColors.tealAccent : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Step 1 ➔ Step 2 遷移中：画面中央の開始案内表示
  // --------------------------------------------------------------------------

  Widget _buildStep1StartingCenterNotice() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        key: const Key('step1_starting_notice'),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.tealAccent, width: 1.5),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.volume_up,
              color: AppColors.tealAccent,
              size: 36,
            ),
            SizedBox(height: 12),
            Text(
              'トレーニングが開始されました。（種目・重量・レップ数・セット数が読み上げられます）',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ガイダンスカード（Step 1〜5）
  // --------------------------------------------------------------------------

  Widget _buildGuidanceCard() {
    String stepBadge = '';
    String guidanceText = '';

    switch (_currentStep) {
      case TutorialStep.step1Start:
        stepBadge = 'Step 1/5';
        guidanceText = '再生（または停止）操作でトレーニングを開始しましょう';
        break;

      case TutorialStep.step2Select:
        stepBadge = 'Step 2/5';
        if (_step2Phase == Step2Phase.enterMode) {
          guidanceText = '曲送り（次の曲へ進む）で調整モードに切り替える';
        } else {
          guidanceText = '音量(+/-)で調整項目を選択 ➔ 再生停止で決定';
        }
        break;

      case TutorialStep.step3Adjust:
        stepBadge = 'Step 3/5';
        guidanceText = '音量(+/-)で${_selectedItem.label}を調整。再生停止で決定。';
        break;

      case TutorialStep.step4FinishAdjust:
        stepBadge = 'Step 4/5';
        guidanceText = '曲送り（次の曲へ進む）で調整モードを終了する。';
        break;

      case TutorialStep.step5Reconfirm:
        stepBadge = 'Step 5/5';
        guidanceText = '曲戻し（前の曲へ戻る）でトレーニングの内容を確認。';
        break;

      case TutorialStep.step6Complete:
        return const SizedBox.shrink();
    }

    return Card(
      color: const Color(0xE61E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.tealAccent, width: 1.2),
      ),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tealAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                stepBadge,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.tealAccent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              guidanceText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 発光ホタル枠線（要素手前はクリア・外側のみ明滅発光）
  // --------------------------------------------------------------------------

  Widget _buildGlowOverlay() {
    if (_spotlightRect == null || _spotlightRect!.isEmpty) {
      return const SizedBox.shrink();
    }

    final inflated = Rect.fromLTRB(
      _spotlightRect!.left - 4.0,
      _spotlightRect!.top - 4.0,
      _spotlightRect!.right + 4.0,
      _spotlightRect!.bottom + 4.0,
    );

    final double radius =
        _currentStep == TutorialStep.step1Start ? 31.0 : 16.0;

    return Positioned(
      left: inflated.left,
      top: inflated.top,
      width: inflated.width,
      height: inflated.height,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, _) {
            final t = _effectiveAnimateGlow ? _glowAnimation.value : 1.0;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: AppColors.tealAccent
                      .withValues(alpha: (0.55 + 0.45 * t).clamp(0.0, 1.0)),
                  width: 2.0 + 1.0 * t,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.tealAccent
                        .withValues(alpha: (0.35 + 0.35 * t).clamp(0.0, 1.0)),
                    blurRadius: 8.0 + 12.0 * t,
                    spreadRadius: 1.0 + 2.0 * t,
                    blurStyle: BlurStyle.outer,
                  ),
                  BoxShadow(
                    color: AppColors.tealAccent
                        .withValues(alpha: (0.12 + 0.18 * t).clamp(0.0, 1.0)),
                    blurRadius: 20.0 + 12.0 * t,
                    spreadRadius: 2.0 + 3.0 * t,
                    blurStyle: BlurStyle.outer,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Step 6: 完了画面
  // --------------------------------------------------------------------------

  Widget _buildStep6CelebrationOverlay() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 56,
                color: AppColors.tealAccent,
              ),
              const SizedBox(height: 12),
              const Text(
                'チュートリアル完了！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'イヤホン操作の準備が整いました。\nスマートフォンを触らずにトレーニングを開始してみましょう。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // おさらいカード
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('開始 / 次へ', '［再生/停止］ボタン'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildSummaryRow('調整モード', '［次の曲］ボタンで切替 / 完了'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildSummaryRow('項目の選択・変更', '［音量＋/−］ボタン'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildSummaryRow('内容の確認', '［前の曲］ボタン'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                key: const Key('btn_start_first_training'),
                onPressed: _navigateToTrainingScreen,
                icon: const Icon(Icons.fitness_center),
                label: const Text(
                  '最初のトレーニングを開始する',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.tealAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.tealAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            desc,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // スキップボタン（右下常設）
  // --------------------------------------------------------------------------

  Widget _buildSkipButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: TextButton.icon(
        key: const Key('btn_tutorial_skip'),
        onPressed: _onSkipStepPressed,
        icon: const Icon(
          Icons.fast_forward,
          size: 16,
          color: Colors.white70,
        ),
        label: const Text(
          'スキップ >',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 画面最下部：疑似メディアキーバー
  // --------------------------------------------------------------------------

  (String modeLabel, String volLabel) _getMediaBarLabels() {
    switch (_currentStep) {
      case TutorialStep.step1Start:
        return ('Step 1/5', '再生/停止: 開始');
      case TutorialStep.step2Select:
        if (_step2Phase == Step2Phase.enterMode) {
          return ('Step 2/5', '次曲: 調整モードへ');
        } else {
          return ('Step 2/5', '音量: 項目選択 / 再生: 決定');
        }
      case TutorialStep.step3Adjust:
        return ('Step 3/5', '音量: ${_selectedItem.label}調整 / 再生: 決定');
      case TutorialStep.step4FinishAdjust:
        return ('Step 4/5', '次曲: 調整終了');
      case TutorialStep.step5Reconfirm:
        return ('Step 5/5', '前曲: 内容確認');
      case TutorialStep.step6Complete:
        return ('チュートリアル完了', '再生/停止: 本編開始');
    }
  }

  Widget _buildMediaControlBar() {
    final (modeLabel, volLabel) = _getMediaBarLabels();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                modeLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.tealAccent,
                ),
              ),
              Text(
                volLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_prev'),
                icon: Icons.skip_previous,
                label: '前曲 (確認)',
                onTap: () => _handleButtonAction(ButtonAction.mediaPrevious),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_play_pause'),
                icon: Icons.play_arrow,
                label: '再生 (決定)',
                isPrimary: true,
                onTap: () => _handleButtonAction(ButtonAction.mediaPlayPause),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_next'),
                icon: Icons.skip_next,
                label: '次曲 (調整)',
                onTap: () => _handleButtonAction(ButtonAction.mediaNext),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_vol_down'),
                icon: Icons.volume_down,
                label: 'Vol-',
                onTap: () => _handleButtonAction(ButtonAction.volumeDown),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_vol_up'),
                icon: Icons.volume_up,
                label: 'Vol+',
                onTap: () => _handleButtonAction(ButtonAction.volumeUp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaBarButton({
    required Key buttonKey,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: buttonKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            decoration: BoxDecoration(
              color: isPrimary
                  ? AppColors.primaryAccent.withValues(alpha: 0.18)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPrimary ? AppColors.primaryAccent : AppColors.border,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isPrimary
                      ? AppColors.primaryAccent
                      : AppColors.tealAccent,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isPrimary
                          ? AppColors.primaryAccent
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 半透明ブラック（Black 70%）の背景から注目要素の矩形を完全にくり抜く CustomPainter
class SpotlightOverlayPainter extends CustomPainter {
  final Rect? targetRect;
  final double borderRadius;
  final Color overlayColor;
  final EdgeInsets padding;

  SpotlightOverlayPainter({
    required this.targetRect,
    this.borderRadius = 14.0,
    this.overlayColor = const Color(0xB3000000),
    this.padding = const EdgeInsets.all(4.0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final bgPaint = Paint()..color = overlayColor;

    if (targetRect == null || targetRect!.isEmpty) {
      canvas.drawRect(fullRect, bgPaint);
      return;
    }

    final backgroundPath = Path()..addRect(fullRect);

    final inflatedRect = Rect.fromLTRB(
      targetRect!.left - padding.left,
      targetRect!.top - padding.top,
      targetRect!.right + padding.right,
      targetRect!.bottom + padding.bottom,
    );

    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        inflatedRect,
        Radius.circular(borderRadius),
      ));

    final spotlightPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      holePath,
    );

    canvas.drawPath(spotlightPath, bgPaint);
  }

  @override
  bool shouldRepaint(covariant SpotlightOverlayPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.padding != padding;
  }
}
