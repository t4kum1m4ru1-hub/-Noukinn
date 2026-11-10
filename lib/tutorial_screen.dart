import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'main.dart'
    show
        AudioDuckingController,
        AudioSessionDuckingController,
        ButtonAction,
        KeyEventChannelDispatcher,
        SoundEffectService,
        TtsService;
import 'theme/app_colors.dart';
import 'training_screen.dart';

/// チュートリアルの全6ステップ
enum TutorialStep {
  /// Step 1: 初期案内画面（チュートリアル趣旨説明・開始/スキップボタン）
  step1Intro,

  /// Step 2: 開始操作体験（暗転＋開始ボタンスポットライト＋イヤホン再生ボタン）
  step2Start,

  /// Step 3: 調整モード突入＆項目選択（Part 1: 突入 / Part 2: 項目送り・決定）
  step3Select,

  /// Step 4: 重量調整とデバウンス体験（重量カードスポットライト＋Vol±で±2.5kg＋0.7sデバウンス）
  step4Adjust,

  /// Step 5: 調整完了の体験（全体暗転＋次曲キーで確定）
  step5Confirm,

  /// Step 6: 完了と本編スタート（暗転解除＋祝福表示＋本編遷移）
  step6Complete,
}

/// Step 3 内のサブフェーズ
enum Step3Phase {
  /// Part 1: 次曲キー（87）による調整モード突入待ち
  enterMode,

  /// Part 2: 音量キー（24/25）による項目巡回と再生キー（85）による決定待ち
  cycleItem,
}

/// Step 3 で選択巡回するトレーニング項目
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
  final bool animateGlow;

  const TutorialScreen({
    super.key,
    this.ttsService,
    this.soundEffectService,
    this.duckingController,
    this.animateGlow = true,
  });

  /// 数値フォーマット用ヘルパー（整数の場合は小数点なし、端数は小数第1位）
  static String formatWeightNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  static String formatWeightSpeech(double val) => '${formatWeightNumber(val)}キロ';
  static String formatWeightDisplay(double val) => '${formatWeightNumber(val)} kg';

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen>
    with SingleTickerProviderStateMixin {
  late final AudioDuckingController _duckingController;
  late final FocusNode _keyboardFocusNode;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  // 状態変数
  TutorialStep _currentStep = TutorialStep.step1Intro;
  Step3Phase _step3Phase = Step3Phase.enterMode;
  TutorialItem _selectedItem = TutorialItem.exerciseName;

  double _currentWeight = 60.0;
  final int _currentReps = 10;
  final int _currentSets = 3;
  final String _currentExercise = 'ベンチプレス';

  Rect? _spotlightRect;
  String? _warningMessage;
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
    _duckingController =
        widget.duckingController ?? AudioSessionDuckingController();
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
      }
    });
  }

  void _startGlowIfNeeded() {
    if (widget.animateGlow &&
        _currentStep != TutorialStep.step1Intro &&
        _currentStep != TutorialStep.step6Complete) {
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

  Future<void> _speak(String text) async {
    if (!mounted) return;
    try {
      await _duckingController.requestDucking();
      if (!mounted) return;
      await widget.ttsService?.stop();
      if (!mounted) return;
      await widget.ttsService?.speak(text);
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

  // --------------------------------------------------------------------------
  // 0.7秒デバウンス制御
  // --------------------------------------------------------------------------

  void _startWeightDebounce(String Function() speechBuilder) {
    _cancelDebounce();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      _framePumpTimer?.cancel();
      _framePumpTimer = null;
      _debounceTimer = null;
      if (!mounted || _currentStep != TutorialStep.step4Adjust) return;
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
      case TutorialStep.step1Intro:
        if (effectiveAction == ButtonAction.mediaPlayPause) {
          setState(() {
            _currentStep = TutorialStep.step2Start;
          });
          _startGlowIfNeeded();
          _updateSpotlightRect();
        }
        break;

      case TutorialStep.step2Start:
        if (effectiveAction == ButtonAction.mediaPlayPause) {
          _proceedFromStep2();
        }
        break;

      case TutorialStep.step3Select:
        _handleStep3Action(effectiveAction);
        break;

      case TutorialStep.step4Adjust:
        _handleStep4Action(effectiveAction);
        break;

      case TutorialStep.step5Confirm:
        _handleStep5Action(effectiveAction);
        break;

      case TutorialStep.step6Complete:
        if (effectiveAction == ButtonAction.mediaPlayPause) {
          _navigateToTrainingScreen();
        }
        break;
    }
  }

  Future<void> _proceedFromStep2() async {
    if (_isStepTransitioning) return;
    _isStepTransitioning = true;
    final int gen = ++_transitionGeneration;
    try {
      await _playBeep();
      if (!mounted ||
          _currentStep != TutorialStep.step2Start ||
          gen != _transitionGeneration) {
        return;
      }
      await _speak('開始、ベンチプレス、60キロ、10回、3セット');
      if (!mounted ||
          _currentStep != TutorialStep.step2Start ||
          gen != _transitionGeneration) {
        return;
      }
      setState(() {
        _currentStep = TutorialStep.step3Select;
        _step3Phase = Step3Phase.enterMode;
      });
      _startGlowIfNeeded();
      _updateSpotlightRect();
    } finally {
      if (mounted && gen == _transitionGeneration) {
        _isStepTransitioning = false;
      }
    }
  }

  Future<void> _handleStep3Action(ButtonAction action) async {
    if (action == ButtonAction.mediaPrevious) {
      await _speak(
          '$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
      return;
    }

    if (_step3Phase == Step3Phase.enterMode) {
      if (action == ButtonAction.mediaNext) {
        if (_isStepTransitioning) return;
        _isStepTransitioning = true;
        final int gen = ++_transitionGeneration;
        try {
          await _playBeep();
          if (!mounted ||
              _currentStep != TutorialStep.step3Select ||
              _step3Phase != Step3Phase.enterMode ||
              gen != _transitionGeneration) {
            return;
          }
          await _speak('調整、種目名');
          if (!mounted ||
              _currentStep != TutorialStep.step3Select ||
              _step3Phase != Step3Phase.enterMode ||
              gen != _transitionGeneration) {
            return;
          }
          setState(() {
            _step3Phase = Step3Phase.cycleItem;
            _selectedItem = TutorialItem.exerciseName;
          });
          _updateSpotlightRect();
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
            _currentStep != TutorialStep.step3Select ||
            _step3Phase != Step3Phase.cycleItem) {
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
            _currentStep != TutorialStep.step3Select ||
            _step3Phase != Step3Phase.cycleItem) {
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
              _currentStep != TutorialStep.step3Select ||
              _step3Phase != Step3Phase.cycleItem ||
              gen != _transitionGeneration) {
            return;
          }
          await _speak(TutorialScreen.formatWeightSpeech(_currentWeight));
          if (!mounted ||
              _currentStep != TutorialStep.step3Select ||
              _step3Phase != Step3Phase.cycleItem ||
              gen != _transitionGeneration) {
            return;
          }
          setState(() {
            _currentStep = TutorialStep.step4Adjust;
          });
          _updateSpotlightRect();
        } finally {
          if (mounted && gen == _transitionGeneration) {
            _isStepTransitioning = false;
          }
        }
      }
    }
  }

  Future<void> _handleStep4Action(ButtonAction action) async {
    if (action == ButtonAction.mediaPrevious) {
      await _speak(
          '$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
      return;
    }

    if (action == ButtonAction.volumeUp) {
      await _playBeep();
      if (!mounted || _currentStep != TutorialStep.step4Adjust) return;
      setState(() {
        _currentWeight = (_currentWeight + 2.5).clamp(0.0, 500.0);
      });
      _startWeightDebounce(
          () => TutorialScreen.formatWeightSpeech(_currentWeight));
    } else if (action == ButtonAction.volumeDown) {
      await _playBeep();
      if (!mounted || _currentStep != TutorialStep.step4Adjust) return;
      setState(() {
        _currentWeight = (_currentWeight - 2.5).clamp(0.0, 500.0);
      });
      _startWeightDebounce(
          () => TutorialScreen.formatWeightSpeech(_currentWeight));
    } else if (action == ButtonAction.mediaPlayPause) {
      if (_isStepTransitioning) return;
      _isStepTransitioning = true;
      _cancelDebounce();
      final int gen = ++_transitionGeneration;
      try {
        await _playBeep();
        if (!mounted ||
            _currentStep != TutorialStep.step4Adjust ||
            gen != _transitionGeneration) {
          return;
        }
        await _speak('調整、重量');
        if (!mounted ||
            _currentStep != TutorialStep.step4Adjust ||
            gen != _transitionGeneration) {
          return;
        }
        setState(() {
          _currentStep = TutorialStep.step5Confirm;
          _warningMessage = null;
        });
        _startGlowIfNeeded();
        _updateSpotlightRect();
      } finally {
        if (mounted && gen == _transitionGeneration) {
          _isStepTransitioning = false;
        }
      }
    }
  }

  Future<void> _handleStep5Action(ButtonAction action) async {
    if (action == ButtonAction.mediaNext) {
      if (_isStepTransitioning) return;
      _isStepTransitioning = true;
      final int gen = ++_transitionGeneration;
      try {
        await _playBeep();
        if (!mounted ||
            _currentStep != TutorialStep.step5Confirm ||
            gen != _transitionGeneration) {
          return;
        }
        await _speak(
            '確定、開始、$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
        if (!mounted ||
            _currentStep != TutorialStep.step5Confirm ||
            gen != _transitionGeneration) {
          return;
        }
        setState(() {
          _currentStep = TutorialStep.step6Complete;
          _warningMessage = null;
        });
        _startGlowIfNeeded();
        _updateSpotlightRect();
      } finally {
        if (mounted && gen == _transitionGeneration) {
          _isStepTransitioning = false;
        }
      }
    } else {
      setState(() {
        _warningMessage = '［次の曲へ進む］ボタンを押して調整を完了してください';
      });
    }
  }

  void _onSkipStepPressed() {
    _transitionGeneration++;
    _isStepTransitioning = false;
    _cancelDebounce();
    widget.ttsService?.stop();
    _duckingController.releaseDucking();
    setState(() {
      _warningMessage = null;
      switch (_currentStep) {
        case TutorialStep.step1Intro:
          _currentStep = TutorialStep.step2Start;
          break;
        case TutorialStep.step2Start:
          _currentStep = TutorialStep.step3Select;
          _step3Phase = Step3Phase.enterMode;
          break;
        case TutorialStep.step3Select:
          _currentStep = TutorialStep.step4Adjust;
          break;
        case TutorialStep.step4Adjust:
          _currentStep = TutorialStep.step5Confirm;
          break;
        case TutorialStep.step5Confirm:
          _currentStep = TutorialStep.step6Complete;
          break;
        case TutorialStep.step6Complete:
          _navigateToTrainingScreen();
          break;
      }
    });
    _startGlowIfNeeded();
    _updateSpotlightRect();
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

  GlobalKey? _getCurrentTargetKey() {
    switch (_currentStep) {
      case TutorialStep.step1Intro:
        return null;
      case TutorialStep.step2Start:
        return _startBtnKey;
      case TutorialStep.step3Select:
        if (_step3Phase == Step3Phase.enterMode) {
          return _exerciseCardKey;
        }
        switch (_selectedItem) {
          case TutorialItem.exerciseName:
            return _exerciseCardKey;
          case TutorialItem.weight:
            return _weightCardKey;
          case TutorialItem.reps:
            return _repsCardKey;
          case TutorialItem.sets:
            return _setsCardKey;
        }
      case TutorialStep.step4Adjust:
        return _weightCardKey;
      case TutorialStep.step5Confirm:
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

  // --------------------------------------------------------------------------
  // UI 構築
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
            // 1. 下層：ワークアウト表示レイアウト
            Positioned.fill(
              child: _buildWorkoutBackground(),
            ),

            // 2. 中層：スポットライト＆暗転オーバーレイ（Step 2〜5 で有効）
            if (_currentStep != TutorialStep.step1Intro &&
                _currentStep != TutorialStep.step6Complete) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_currentStep == TutorialStep.step2Start) {
                      _proceedFromStep2();
                    }
                  },
                  child: CustomPaint(
                    painter: SpotlightOverlayPainter(
                      targetRect: _spotlightRect,
                    ),
                  ),
                ),
              ),
              // ホタルの呼吸発光枠線
              _buildGlowOverlay(),
            ],

            // 3. 上層：フローティングガイダンスカード（Step 2〜5）
            if (_currentStep != TutorialStep.step1Intro &&
                _currentStep != TutorialStep.step6Complete)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _buildGuidanceCard(),
              ),

            // 4. Step 1 専用全画面カード
            if (_currentStep == TutorialStep.step1Intro)
              Positioned.fill(
                child: _buildStep1IntroOverlay(),
              ),

            // 5. Step 6 専用全画面祝福カード
            if (_currentStep == TutorialStep.step6Complete)
              Positioned.fill(
                child: _buildStep6CelebrationOverlay(),
              ),

            // 6. 右下スキップボタン（Step 2〜5）
            if (_currentStep != TutorialStep.step1Intro &&
                _currentStep != TutorialStep.step6Complete)
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

  Widget _buildWorkoutBackground() {
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
                color: (_currentStep == TutorialStep.step3Select &&
                        _selectedItem == TutorialItem.exerciseName)
                    ? AppColors.tealAccent
                    : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  _currentExercise,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1 / $_currentSets セット目',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
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
                    isSelected: (_currentStep == TutorialStep.step4Adjust) ||
                        (_currentStep == TutorialStep.step3Select &&
                            _selectedItem == TutorialItem.weight),
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
                    isSelected: _currentStep == TutorialStep.step3Select &&
                        _selectedItem == TutorialItem.reps,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // セット数カード
              Expanded(
                child: Container(
                  key: _setsCardKey,
                  child: _buildValueCard(
                    cardKey: const Key('card_sets'),
                    label: 'セット数',
                    value: '1 / $_currentSets',
                    isSelected: _currentStep == TutorialStep.step3Select &&
                        _selectedItem == TutorialItem.sets,
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
                onPressed: () {
                  if (_currentStep == TutorialStep.step2Start) {
                    _proceedFromStep2();
                  }
                },
                icon: const Icon(Icons.play_arrow, size: 28),
                label: Text(
                  _currentStep == TutorialStep.step2Start ? '開始' : '次へ',
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
                color: isSelected
                    ? AppColors.tealAccent
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ガイダンスカード（Step 2〜5）
  // --------------------------------------------------------------------------

  Widget _buildGuidanceCard() {
    String stepBadge = '';
    String guidanceText = '';
    String subHint = '';

    switch (_currentStep) {
      case TutorialStep.step2Start:
        stepBadge = 'STEP 1/5: 開始操作';
        guidanceText = 'イヤホンの［再生/停止］ボタンを押してトレーニングを始めてみましょう';
        subHint = '🎧 キー (85) を押下または画面タップ';
        break;

      case TutorialStep.step3Select:
        if (_step3Phase == Step3Phase.enterMode) {
          stepBadge = 'STEP 2/5 (1/2): 調整モード起動';
          guidanceText = 'イヤホンの［次の曲へ進む］ボタンを押して、調整モードに入りましょう';
          subHint = '⏭️ 次曲キー (87) で調整モードへ突入';
        } else {
          stepBadge = 'STEP 2/5 (2/2): 項目選択';
          guidanceText = '［音量＋/−］で項目を切り替え、［再生/停止］で決定してください';
          subHint = '🔊 現在フォーカス: ${_selectedItem.label}';
        }
        break;

      case TutorialStep.step4Adjust:
        stepBadge = 'STEP 3/5: 重量調整と音声';
        guidanceText =
            '［音量＋/−］で重量を調整（連打対応）。指を離して0.7秒後に最新の重量を読み上げます。終わったら［再生/停止］で決定。';
        subHint = '💡 連打中は画面がリアルタイムに更新され、最後の1回だけ発話されます';
        break;

      case TutorialStep.step5Confirm:
        stepBadge = 'STEP 4/5: 調整の完了';
        guidanceText = '［次の曲へ進む］ボタンを押して、調整を完了しましょう';
        subHint = '⏭️ 次曲キー (87) で調整モードを確定終了';
        break;

      default:
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
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              ],
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
            if (subHint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subHint,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (_warningMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amberAccent, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.amberAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _warningMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 発光ホタル枠線
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

    return Positioned(
      left: inflated.left,
      top: inflated.top,
      width: inflated.width,
      height: inflated.height,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, _) {
            final t = widget.animateGlow ? _glowAnimation.value : 1.0;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(
                  color: AppColors.tealAccent
                      .withValues(alpha: (0.5 + 0.5 * t).clamp(0.0, 1.0)),
                  width: 2.0 + 1.0 * t,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.tealAccent
                        .withValues(alpha: (0.35 + 0.35 * t).clamp(0.0, 1.0)),
                    blurRadius: 8.0 + 12.0 * t,
                    spreadRadius: 1.5 + 2.5 * t,
                  ),
                  BoxShadow(
                    color: AppColors.tealAccent
                        .withValues(alpha: (0.12 + 0.18 * t).clamp(0.0, 1.0)),
                    blurRadius: 22.0 + 12.0 * t,
                    spreadRadius: 4.0 + 4.0 * t,
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
  // Step 1: 案内画面
  // --------------------------------------------------------------------------

  Widget _buildStep1IntroOverlay() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fitness_center,
                size: 48,
                color: AppColors.tealAccent,
              ),
              const SizedBox(height: 12),
              const Text(
                'のう筋 操作チュートリアル',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'スマートフォンをポケットに入れたまま、イヤホンのボタンだけでトレーニングを完結できる体験を学びましょう。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // 操作一覧カード
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
                    _buildIntroItem('🎧 ［再生/停止］', 'トレーニング開始 / 次へ / 決定'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildIntroItem('⏭️ ［次の曲］', '調整モードの切替 / 完了'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildIntroItem('🔊 ［音量＋/−］', '項目の選択 / 重量・回数の増減（連打対応）'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildIntroItem('⏮️ ［前の曲］', 'いつでも種目内容の安全確認'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // メイン開始ボタン
              ElevatedButton(
                key: const Key('btn_tutorial_start'),
                onPressed: () {
                  setState(() {
                    _currentStep = TutorialStep.step2Start;
                  });
                  _startGlowIfNeeded();
                  _updateSpotlightRect();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.tealAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'チュートリアルを開始する',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),

              // スキップボタン
              TextButton(
                key: const Key('btn_tutorial_skip_all'),
                onPressed: _navigateToTrainingScreen,
                child: const Text(
                  'スキップして直接トレーニングへ',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroItem(String title, String desc) {
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
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            desc,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
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
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                '🎉 チュートリアル完了！',
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
                    _buildIntroItem('✅ 開始 / 次へ', '［再生/停止］ボタン'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildIntroItem('✅ 調整モード', '［次の曲］ボタンでON/確定'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildIntroItem('✅ 重量・回数変更', '［音量＋/−］ボタン（連打対応）'),
                    const Divider(color: AppColors.trackInactive, height: 12),
                    _buildIntroItem('✅ 内容の確認', '［前の曲］ボタン（いつでも安全）'),
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
      case TutorialStep.step1Intro:
        return ('［チュートリアル］Step 1: 案内', '音量キー: 無効');
      case TutorialStep.step2Start:
        return ('［チュートリアル］Step 1: 開始操作体験', '音量キー: 無効');
      case TutorialStep.step3Select:
        if (_step3Phase == Step3Phase.enterMode) {
          return ('［チュートリアル］Step 2: 調整モード起動', '音量キー: 無効');
        } else {
          return ('［チュートリアル］Step 2: 項目選択', '音量キー: 項目切り替え');
        }
      case TutorialStep.step4Adjust:
        return ('［チュートリアル］Step 3: 重量調整（連打デバウンス）', '音量キー: 重量±2.5kg');
      case TutorialStep.step5Confirm:
        return ('［チュートリアル］Step 4: 調整完了操作', '音量キー: 無効');
      case TutorialStep.step6Complete:
        return ('［チュートリアル］Step 5: 完了', '音量キー: 無効');
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
                onTap: () =>
                    _handleButtonAction(ButtonAction.mediaPrevious),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_play_pause'),
                icon: Icons.play_arrow,
                label: '再生 (決定)',
                isPrimary: true,
                onTap: () =>
                    _handleButtonAction(ButtonAction.mediaPlayPause),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_next'),
                icon: Icons.skip_next,
                label: '次曲 (調整)',
                onTap: () =>
                    _handleButtonAction(ButtonAction.mediaNext),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_vol_down'),
                icon: Icons.volume_down,
                label: 'Vol-',
                onTap: () =>
                    _handleButtonAction(ButtonAction.volumeDown),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('virtual_key_vol_up'),
                icon: Icons.volume_up,
                label: 'Vol+',
                onTap: () =>
                    _handleButtonAction(ButtonAction.volumeUp),
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
    this.overlayColor = const Color(0xB3000000), // Colors.black.withOpacity(0.70)
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
