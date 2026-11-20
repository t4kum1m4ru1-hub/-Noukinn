import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/training_session_controller.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';

/// 画面 A2: トレーニング中画面（noukin_app UI 忠実移植）
class TrainingScreen extends StatefulWidget {
  final TrainingSessionController controller;
  final FutureOr<void> Function()? onCompleted;
  final VoidCallback? onBackPressed;

  const TrainingScreen({
    super.key,
    required this.controller,
    this.onCompleted,
    this.onBackPressed,
  });

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  bool _hasNavigatedToReview = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant TrainingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _hasNavigatedToReview = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handlePrimaryAction() async {
    if (_hasNavigatedToReview) return;
    final completed = widget.controller.advanceOrComplete();
    if (!completed) return;
    _hasNavigatedToReview = true;
    try {
      await widget.onCompleted?.call();
    } finally {
      if (mounted) {
        _hasNavigatedToReview = false;
      }
    }
  }

  void _showExerciseSwapBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final exercises = widget.controller.exercises;
        final currentIdx = widget.controller.currentIndex;
        final maxSheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.75;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
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
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(exercises.length, (index) {
                          final item = exercises[index];
                          final isCurrent = index == currentIdx;
                          final wText =
                              TrainingSessionController.formatWeightNumber(
                                item.weightKg,
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
                              isCurrent
                                  ? Icons.check_circle
                                  : Icons.swap_vert,
                              color: isCurrent
                                  ? AppColors.primaryAccent
                                  : AppColors.tealAccent,
                            ),
                            title: Text(
                              '${index + 1}. ${item.machine.name}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCurrent
                                    ? AppColors.primaryAccent
                                    : AppColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '$wText kg / ${item.reps} 回 / ${item.sets} セット',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              widget.controller.swapExercise(index);
                            },
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final exercise = controller.currentExerciseOrNull;
    if (exercise == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            key: const Key('training_back_button'),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'メイン画面へ戻る',
            onPressed:
                widget.onBackPressed ?? () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'トレーニング',
            style: TextStyle(color: AppColors.textPrimary),
          ),
        ),
        body: const Center(
          child: Text(
            '実施可能な種目がありません。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          key: const Key('training_back_button'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'メイン画面へ戻る',
          onPressed: widget.onBackPressed ?? () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          key: const Key('btn_select_exercise'),
          onTap: _showExerciseSwapBottomSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    exercise.machine.name,
                    key: const Key('exercise_title'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.swap_horiz,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxHeight < 600;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0.0, constraints.maxHeight - 16),
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProgressBadge(controller, exercise),
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: ClipRRect(
                                  key: const Key('exercise_image'),
                                  borderRadius: BorderRadius.circular(16),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: isCompact ? 150.0 : 220.0,
                                    ),
                                    child: _buildExerciseImage(
                                      exercise,
                                      isCompact: isCompact,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _buildTargetMusclesBadge(exercise),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: ElevatedButton(
                              key: const Key('btn_next_workout'),
                              onPressed: _handlePrimaryAction,
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
                                controller.isStarted ? '次へ' : '開始',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          _buildCounterCard(
                            cardKey: const Key('card_weight'),
                            label: '重量',
                            valueText: controller.formattedWeightDisplay,
                            downKey: const Key('btn_weight_down'),
                            upKey: const Key('btn_weight_up'),
                            onDown: () => controller.adjustWeight(
                              -TrainingSessionController.weightStepKg,
                            ),
                            onUp: () => controller.adjustWeight(
                              TrainingSessionController.weightStepKg,
                            ),
                          ),
                          _buildCounterCard(
                            cardKey: const Key('card_reps'),
                            label: 'レップ数',
                            valueText: '${controller.reps} 回',
                            downKey: const Key('btn_reps_down'),
                            upKey: const Key('btn_reps_up'),
                            onDown: () => controller.adjustReps(-1),
                            onUp: () => controller.adjustReps(1),
                          ),
                          _buildCounterCard(
                            cardKey: const Key('card_sets'),
                            label: 'セット数',
                            valueText: '${controller.sets} セット',
                            downKey: const Key('btn_sets_down'),
                            upKey: const Key('btn_sets_up'),
                            onDown: () => controller.adjustSets(-1),
                            onUp: () => controller.adjustSets(1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressBadge(
    TrainingSessionController controller,
    PrescribedExercise exercise,
  ) {
    return Container(
      key: const Key('exercise_progress_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              '種目 ${controller.progressText} ・ ${exercise.sets} セット',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.tealAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '本日のメニュー',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseImage(
    PrescribedExercise exercise, {
    required bool isCompact,
  }) {
    final assetPath = exercise.machine.imageAssetPath;
    if (assetPath == null || assetPath.isEmpty) {
      return _buildImageFallback(
        exercise.machine.name,
        null,
        isCompact: isCompact,
      );
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return _buildImageFallback(
          exercise.machine.name,
          assetPath,
          isCompact: isCompact,
        );
      },
    );
  }

  Widget _buildImageFallback(
    String machineName,
    String? assetPath, {
    required bool isCompact,
  }) {
    return Container(
      width: double.infinity,
      height: isCompact ? 140.0 : 180.0,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.fitness_center,
            size: isCompact ? 44 : 56,
            color: AppColors.tealAccent,
          ),
          const SizedBox(height: 8),
          Text(
            machineName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCompact ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          if (assetPath != null) ...[
            const SizedBox(height: 4),
            Text(
              assetPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetMusclesBadge(PrescribedExercise exercise) {
    final primaryText = exercise.primaryMuscleNames.isNotEmpty
        ? exercise.primaryMuscleNames.join('・')
        : 'なし';
    final synergistText = exercise.synergistMuscleNames.join('・');

    return Container(
      key: const Key('target_muscles_badge'),
      margin: const EdgeInsets.only(bottom: 10.0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '〇 主動筋: $primaryText',
            softWrap: true,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.tealAccent,
            ),
          ),
          if (synergistText.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '△ 協働筋: $synergistText',
              softWrap: true,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCounterCard({
    required Key cardKey,
    required String label,
    required String valueText,
    required Key downKey,
    required Key upKey,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return Card(
      key: cardKey,
      color: AppColors.surface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border, width: 1.0),
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
                foregroundColor: AppColors.tealAccent,
                minimumSize: const Size(44, 44),
              ),
            ),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      valueText,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.tealAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              key: upKey,
              icon: const Icon(Icons.add),
              onPressed: onUp,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceVariant,
                foregroundColor: AppColors.tealAccent,
                minimumSize: const Size(44, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
