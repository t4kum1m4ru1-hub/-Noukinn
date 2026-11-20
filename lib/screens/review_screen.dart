import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

/// 画面 A3: トレーニング終了後のフィードバック入力画面
class ReviewScreen extends StatefulWidget {
  final List<PrescribedExercise> exercises;
  final FutureOr<void> Function(WorkoutFeedback feedback)? onSubmitFeedback;

  const ReviewScreen({
    super.key,
    this.exercises = const <PrescribedExercise>[],
    this.onSubmitFeedback,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  WorkoutFeedback? _selectedFeedback;
  bool _isSubmitting = false;
  bool _hasSubmitted = false;

  Future<void> _handleSubmit() async {
    final feedback = _selectedFeedback;
    if (feedback == null || _isSubmitting || _hasSubmitted) return;
    setState(() {
      _isSubmitting = true;
    });
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    try {
      if (widget.onSubmitFeedback != null) {
        await widget.onSubmitFeedback!(feedback);
      } else if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      if (mounted) {
        setState(() {
          _hasSubmitted = true;
          _isSubmitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.error,
            content: Text(
              '保存に失敗しました。もう一度お試しください。',
              style: TextStyle(color: AppColors.onError),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFinishEnabled =
        _selectedFeedback != null && !_isSubmitting && !_hasSubmitted;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          'レビューページ',
          key: Key('review_page_title'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0.0, constraints.maxHeight - 48.0),
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Spacer(),
                          const Center(
                            child: Text(
                              'レビューページ',
                              key: Key('review_page_text'),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Center(
                            child: Text(
                              'すべてのワークアウトが完了しました！',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildFeedbackOption(
                            optionKey: const Key('feedback_too_light'),
                            feedback: WorkoutFeedback.tooLight,
                          ),
                          const SizedBox(height: 10),
                          _buildFeedbackOption(
                            optionKey: const Key('feedback_just_right'),
                            feedback: WorkoutFeedback.justRight,
                          ),
                          const SizedBox(height: 10),
                          _buildFeedbackOption(
                            optionKey: const Key('feedback_too_hard'),
                            feedback: WorkoutFeedback.tooHard,
                          ),
                          const Spacer(),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            key: const Key('btn_finish_workout'),
                            onPressed: isFinishEnabled ? _handleSubmit : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryAccent,
                              foregroundColor: AppColors.onPrimaryAccent,
                              disabledBackgroundColor: AppColors.surfaceVariant,
                              disabledForegroundColor: AppColors.textTertiary,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'ワークアウトを終了',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  Widget _buildFeedbackOption({
    required Key optionKey,
    required WorkoutFeedback feedback,
  }) {
    final isSelected = _selectedFeedback == feedback;
    return Material(
      color: isSelected
          ? AppColors.highlightEditingSurface
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? AppColors.primaryAccent : AppColors.border,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        key: optionKey,
        borderRadius: BorderRadius.circular(14),
        onTap: (_isSubmitting || _hasSubmitted)
            ? null
            : () {
                setState(() {
                  _selectedFeedback = feedback;
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? AppColors.primaryAccent
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  feedback.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
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
