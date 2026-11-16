import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart'
    show
        ButtonAction,
        KeyEventChannelDispatcher,
        SoundEffectService,
        TtsService;
import 'review_screen.dart';
import 'theme/app_colors.dart';
import 'training_controller.dart';

export 'training_controller.dart';

/// トレーニング中に表示する専用画面
class TrainingScreen extends StatefulWidget {
  final TtsService? ttsService;
  final SoundEffectService? soundEffectService;
  final TrainingController? controller;

  const TrainingScreen({
    super.key,
    this.ttsService,
    this.soundEffectService,
    this.controller,
  });

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final TrainingController _controller;
  late final bool _ownsController;
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _hasNavigatedToReview = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = TrainingController(
        ttsService: widget.ttsService,
        soundEffectService: widget.soundEffectService,
        onWorkoutCompleted: _navigateToReviewScreen,
      );
      _ownsController = true;
    }
    _controller.addListener(_onControllerChanged);
    KeyEventChannelDispatcher.instance.registerListener(_onHardwareKeyAction);
  }

  @override
  void dispose() {
    KeyEventChannelDispatcher.instance.unregisterListener(_onHardwareKeyAction);
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onHardwareKeyAction(ButtonAction action) {
    if (!mounted) return;
    _controller.handleButtonAction(action);
  }

  void _navigateToReviewScreen() {
    if (!mounted || _hasNavigatedToReview) return;
    _hasNavigatedToReview = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => const ReviewScreen(),
          ),
        )
        .then((_) {
          _hasNavigatedToReview = false;
        });
  }

  /// PC/デスクトップ検証用のキーボードショートカット処理
  KeyEventResult _handleKeyboardEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _controller.handleButtonAction(ButtonAction.mediaPlayPause);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      _controller.handleButtonAction(ButtonAction.mediaPrevious);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      _controller.handleButtonAction(ButtonAction.mediaNext);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.audioVolumeUp) {
      _controller.handleButtonAction(ButtonAction.volumeUp);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.audioVolumeDown) {
      _controller.handleButtonAction(ButtonAction.volumeDown);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 種目名タップ時に全3種目から選択してスワップするボトムシートを表示
  void _showExerciseSwapBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final exercises = _controller.exercises;
        final currentIdx = _controller.currentExerciseIndex;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '種目変更（現在の種目と順番を入れ替え）',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...List.generate(exercises.length, (index) {
                  final item = exercises[index];
                  final isCurrent = index == currentIdx;
                  final wText = TrainingController.formatWeightNumber(
                    item.weight,
                  );
                  return ListTile(
                    key: Key('swap_exercise_option_$index'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: isCurrent
                        ? AppColors.surfaceVariant
                        : Colors.transparent,
                    leading: Icon(
                      isCurrent ? Icons.check_circle : Icons.swap_vert,
                      color: isCurrent
                          ? AppColors.primaryAccent
                          : AppColors.tealAccent,
                    ),
                    title: Text(
                      '${index + 1}. ${item.name}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCurrent
                            ? AppColors.primaryAccent
                            : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      '$wText kg / ${item.reps} 回 / ${item.sets} セット',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _controller.swapExerciseWith(index);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentExercise = _controller.displayedExercise;
    final mode = _controller.mode;
    final target = _controller.selectedTarget;

    final isExerciseSelectedInB =
        mode == TrainingMode.adjustSelect &&
        target == AdjustmentTarget.exercise;
    final isExerciseEditingInC =
        mode == TrainingMode.adjustValue && target == AdjustmentTarget.exercise;

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyboardEvent,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            key: const Key('training_back_button'),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'メイン画面へ戻る',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: GestureDetector(
            key: const Key('btn_select_exercise'),
            onTap: _showExerciseSwapBottomSheet,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isExerciseEditingInC
                    ? AppColors.primaryAccent.withAlpha(45)
                    : (isExerciseSelectedInB
                          ? AppColors.tealAccent.withAlpha(35)
                          : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isExerciseEditingInC
                      ? AppColors.primaryAccent
                      : (isExerciseSelectedInB
                            ? AppColors.tealAccent
                            : Colors.transparent),
                  width: (isExerciseEditingInC || isExerciseSelectedInB)
                      ? 2.0
                      : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      currentExercise.name,
                      key: const Key('exercise_title'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isExerciseEditingInC ? 24 : 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: isExerciseEditingInC
                            ? AppColors.primaryAccent
                            : (isExerciseSelectedInB
                                  ? AppColors.tealAccent
                                  : AppColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.swap_horiz,
                    size: 18,
                    color: isExerciseEditingInC
                        ? AppColors.primaryAccent
                        : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 16,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 中心：トレーニング種目の画像
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  currentExercise.imagePath,
                                  key: const Key('exercise_image'),
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    // AVIF 非対応環境等の場合のフォールバック表示
                                    return Container(
                                      width: double.infinity,
                                      height: 180,
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.fitness_center,
                                            size: 56,
                                            color: AppColors.tealAccent,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            currentExercise.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            currentExercise.imagePath,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 中央画像のすぐ下：横幅いっぱいの「開始 / 次へ」ボタン
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: ElevatedButton(
                            key: const Key('btn_next_workout'),
                            onPressed: _controller.onPlayPauseOrNextPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryAccent,
                              foregroundColor: AppColors.onPrimaryAccent,
                              minimumSize: const Size.fromHeight(50),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _controller.isStarted ? '次へ' : '開始',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        // 下部：縦に並ぶ3つのカード（状態B/Cのハイライト連動）
                        _buildCounterCard(
                          cardKey: const Key('card_weight'),
                          target: AdjustmentTarget.weight,
                          label: '重量',
                          valueText: _controller.formattedWeightDisplay,
                          downKey: const Key('btn_weight_down'),
                          upKey: const Key('btn_weight_up'),
                          onDown: () => _controller.adjustWeightDirect(-2.5),
                          onUp: () => _controller.adjustWeightDirect(2.5),
                        ),
                        _buildCounterCard(
                          cardKey: const Key('card_reps'),
                          target: AdjustmentTarget.reps,
                          label: 'レップ数',
                          valueText: '${_controller.reps} 回',
                          downKey: const Key('btn_reps_down'),
                          upKey: const Key('btn_reps_up'),
                          onDown: () => _controller.adjustRepsDirect(-1),
                          onUp: () => _controller.adjustRepsDirect(1),
                        ),
                        _buildCounterCard(
                          cardKey: const Key('card_sets'),
                          target: AdjustmentTarget.sets,
                          label: 'セット数',
                          valueText: '${_controller.sets} セット',
                          downKey: const Key('btn_sets_down'),
                          upKey: const Key('btn_sets_up'),
                          onDown: () => _controller.adjustSetsDirect(-1),
                          onUp: () => _controller.adjustSetsDirect(1),
                        ),
                        // 音声ガイドの音量バー
                        _buildVolumeCard(),
                        // 最下部：1段コンパクトなモード表示＆疑似メディアキーバー
                        _buildMediaControlBar(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 左右に増減ボタンを持つ数値調整カード（状態B選択時・状態C値調整時は枠線と背景をハイライト）
  Widget _buildCounterCard({
    required Key cardKey,
    required AdjustmentTarget target,
    required String label,
    required String valueText,
    required Key downKey,
    required Key upKey,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    final isSelectedInB =
        _controller.mode == TrainingMode.adjustSelect &&
        _controller.selectedTarget == target;
    final isEditingInC =
        _controller.mode == TrainingMode.adjustValue &&
        _controller.selectedTarget == target;

    final Color borderColor = isEditingInC
        ? AppColors.primaryAccent
        : (isSelectedInB ? AppColors.tealAccent : AppColors.border);
    final double borderWidth = (isEditingInC || isSelectedInB) ? 2.0 : 1.0;
    final Color cardColor = isEditingInC
        ? const Color(0xFF2D2212)
        : (isSelectedInB ? const Color(0xFF162927) : AppColors.surface);
    final Color valueColor = isEditingInC
        ? AppColors.primaryAccent
        : AppColors.tealAccent;

    return Card(
      key: cardKey,
      color: cardColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              key: downKey,
              icon: const Icon(Icons.remove),
              onPressed: onDown,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceVariant,
                foregroundColor: valueColor,
                minimumSize: const Size(44, 44),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: (isEditingInC || isSelectedInB)
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: (isEditingInC || isSelectedInB)
                        ? FontWeight.bold
                        : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: isEditingInC ? 28 : 24,
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            IconButton.filledTonal(
              key: upKey,
              icon: const Icon(Icons.add),
              onPressed: onUp,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceVariant,
                foregroundColor: valueColor,
                minimumSize: const Size(44, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 音声ガイドの音量バーカード
  Widget _buildVolumeCard() {
    final percent = (_controller.volume * 100).round();
    return Card(
      key: const Key('card_volume'),
      color: AppColors.surface,
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.volume_up,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '音声ガイドの音量',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$percent%',
                  key: const Key('volume_value_text'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.tealAccent,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.tealAccent,
                inactiveTrackColor: AppColors.trackInactive,
                thumbColor: AppColors.tealAccent,
                overlayColor: AppColors.tealAccent.withAlpha(50),
                trackHeight: 4,
              ),
              child: Slider(
                key: const Key('volume_slider'),
                value: _controller.volume,
                min: 0.0,
                max: 1.0,
                onChanged: _controller.setVolume,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 画面最下部：現在のモード状態表示および操作兼・疑似メディアキーバー（1段コンパクト配置）
  Widget _buildMediaControlBar() {
    final mode = _controller.mode;
    final targetLabel = _controller.selectedTarget.label;

    late final String modeText;
    late final String volLabel;

    switch (mode) {
      case TrainingMode.normal:
        modeText = _controller.isStarted ? '状態A: 通常（進行中）' : '状態A: 通常（開始前）';
        volLabel = '無効';
        break;
      case TrainingMode.adjustSelect:
        modeText = '状態B: 項目選択［$targetLabel］';
        volLabel = '項目送り';
        break;
      case TrainingMode.adjustValue:
        modeText = '状態C: 値調整［$targetLabel］';
        volLabel = '値変更';
        break;
    }

    return Container(
      key: const Key('media_control_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  modeText,
                  key: const Key('training_mode_indicator'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: mode == TrainingMode.normal
                        ? AppColors.textSecondary
                        : (mode == TrainingMode.adjustSelect
                              ? AppColors.tealAccent
                              : AppColors.primaryAccent),
                  ),
                ),
              ),
              Text(
                '音量キー: $volLabel',
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
                buttonKey: const Key('btn_media_prev'),
                icon: Icons.skip_previous,
                label: '前曲 (内容確認)',
                onTap: () =>
                    _controller.handleButtonAction(ButtonAction.mediaPrevious),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('btn_media_play_pause'),
                icon: Icons.play_arrow,
                label: '再生/停止 (決定/次へ)',
                isPrimary: true,
                onTap: () =>
                    _controller.handleButtonAction(ButtonAction.mediaPlayPause),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('btn_media_next'),
                icon: Icons.skip_next,
                label: '次曲 (調整/完了)',
                onTap: () =>
                    _controller.handleButtonAction(ButtonAction.mediaNext),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('btn_media_vol_down'),
                icon: Icons.volume_down,
                label: 'Vol-',
                onTap: () =>
                    _controller.handleButtonAction(ButtonAction.volumeDown),
              ),
              const SizedBox(width: 4),
              _buildMediaBarButton(
                buttonKey: const Key('btn_media_vol_up'),
                icon: Icons.volume_up,
                label: 'Vol+',
                onTap: () =>
                    _controller.handleButtonAction(ButtonAction.volumeUp),
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
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
          decoration: BoxDecoration(
            color: isPrimary
                ? AppColors.primaryAccent.withAlpha(40)
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
    );
  }
}
