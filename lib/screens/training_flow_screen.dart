import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../controllers/training_session_controller.dart';
import '../engine/workout_menu_generator.dart';
import '../models/models.dart';
import 'review_screen.dart';
import 'training_pre_screen.dart';
import 'training_screen.dart';

/// ワークアウト完了時に確定・保存すべき結果一式
class WorkoutCompletionResult {
  final WorkoutSessionRecord sessionRecord;
  final SessionAdvanceResult advanceResult;
  final MenuGenerationResult menuResult;

  const WorkoutCompletionResult({
    required this.sessionRecord,
    required this.advanceResult,
    required this.menuResult,
  });
}

/// 画面 A1 -> A2 -> A3 の一連のトレーニングフローを統括するコンテナ画面
class TrainingFlowScreen extends StatefulWidget {
  final UserProfile profile;
  final Map<String, MuscleInputState> muscleStates;
  final Map<String, MachineHistoryEntry> machineHistory;
  final int sessionCount;
  final DateTime Function()? clock;
  final WorkoutMenuGenerator generator;
  final ValueChanged<MenuGenerationResult>? onMenuGenerated;
  final FutureOr<void> Function(WorkoutCompletionResult result)?
  onWorkoutCompleted;

  const TrainingFlowScreen({
    super.key,
    required this.profile,
    required this.muscleStates,
    required this.machineHistory,
    this.sessionCount = 1,
    this.clock,
    this.generator = const WorkoutMenuGenerator(),
    this.onMenuGenerated,
    this.onWorkoutCompleted,
  });

  @override
  State<TrainingFlowScreen> createState() => _TrainingFlowScreenState();
}

class _TrainingFlowScreenState extends State<TrainingFlowScreen> {
  static const Uuid _uuid = Uuid();

  DateTime _resolveClock() => (widget.clock ?? DateTime.now)();

  Future<bool> _handleStartWorkout({
    required WorkoutDurationCourse course,
    required WorkoutCondition condition,
    required String? focusMuscleId,
  }) async {
    final now = _resolveClock();
    final menuResult = widget.generator.generateMenu(
      profile: widget.profile,
      muscleStates: widget.muscleStates,
      machineHistory: widget.machineHistory,
      course: course,
      condition: condition,
      focusMuscleId: focusMuscleId,
      now: now,
      sessionCount: widget.sessionCount,
    );

    if (menuResult.exercises.isEmpty) {
      return false;
    }

    widget.onMenuGenerated?.call(menuResult);

    if (!mounted) return false;
    final flowRoute = ModalRoute.of(context);
    final route = MaterialPageRoute<void>(
      builder: (_) => _TrainingSessionRouteHost(
        menuResult: menuResult,
        onCompleted: (a2Context, controller) => _openReviewScreen(
          a2Context: a2Context,
          flowRoute: flowRoute,
          controller: controller,
          menuResult: menuResult,
          course: course,
          condition: condition,
        ),
      ),
    );

    await Navigator.of(context).push<void>(route);
    return true;
  }

  Future<void> _openReviewScreen({
    required BuildContext a2Context,
    required ModalRoute<dynamic>? flowRoute,
    required TrainingSessionController controller,
    required MenuGenerationResult menuResult,
    required WorkoutDurationCourse course,
    required WorkoutCondition condition,
  }) {
    var hasSubmitted = false;
    return Navigator.of(a2Context).push<void>(
      MaterialPageRoute<void>(
        builder: (a3Context) => ReviewScreen(
          exercises: controller.updatedPrescribedExercises,
          onSubmitFeedback: (feedback) async {
            if (hasSubmitted) return;
            hasSubmitted = true;
            try {
              final completedAt = _resolveClock();
              final updatedExercises = controller.updatedPrescribedExercises;
              final advanceResult = widget.generator.advanceSessionDay(
                muscleStates: widget.muscleStates,
                machineHistory: widget.machineHistory,
                completedExercises: updatedExercises,
                overallFeedback: feedback,
                sessionCount: widget.sessionCount,
              );
              final sessionRecord = WorkoutSessionRecord(
                id: _uuid.v4().toLowerCase(),
                completedAt: completedAt,
                durationCourse: course,
                condition: condition,
                timeSlot: menuResult.timeSlot,
                focusMuscleId: menuResult.focusMuscleId,
                exercises: controller.toCompletedRecords(),
                feedback: feedback,
                createdAt: completedAt,
              );

              await widget.onWorkoutCompleted?.call(
                WorkoutCompletionResult(
                  sessionRecord: sessionRecord,
                  advanceResult: advanceResult,
                  menuResult: menuResult,
                ),
              );

              if (a3Context.mounted) {
                Navigator.of(a3Context).popUntil(
                  (route) => route == flowRoute || route.isFirst,
                );
              }
            } catch (_) {
              hasSubmitted = false;
              rethrow;
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TrainingPreScreen(
      clock: _resolveClock,
      onStartWorkout: _handleStartWorkout,
    );
  }
}

/// Pushed A2 ルートのライフサイクルに合わせて TrainingSessionController を所有・破棄するホスト
class _TrainingSessionRouteHost extends StatefulWidget {
  final MenuGenerationResult menuResult;
  final FutureOr<void> Function(
    BuildContext context,
    TrainingSessionController controller,
  )
  onCompleted;

  const _TrainingSessionRouteHost({
    required this.menuResult,
    required this.onCompleted,
  });

  @override
  State<_TrainingSessionRouteHost> createState() =>
      _TrainingSessionRouteHostState();
}

class _TrainingSessionRouteHostState extends State<_TrainingSessionRouteHost> {
  late final TrainingSessionController _controller = TrainingSessionController(
    menuResult: widget.menuResult,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrainingScreen(
      controller: _controller,
      onCompleted: () => widget.onCompleted(context, _controller),
    );
  }
}
