import 'dart:async';

import 'package:flutter/material.dart';

import '../data/master_data.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';

typedef StartWorkoutCallback = FutureOr<bool> Function({
  required WorkoutDurationCourse course,
  required WorkoutCondition condition,
  required String? focusMuscleId,
});

/// 画面 A1: トレーニング開始前のステップ型フォーム
class TrainingPreScreen extends StatefulWidget {
  final DateTime Function() clock;
  final StartWorkoutCallback onStartWorkout;
  final WorkoutDurationCourse initialCourse;
  final WorkoutCondition initialCondition;
  final String? initialFocusMuscleId;

  const TrainingPreScreen({
    super.key,
    required this.clock,
    required this.onStartWorkout,
    this.initialCourse = WorkoutDurationCourse.standard45,
    this.initialCondition = WorkoutCondition.normal,
    this.initialFocusMuscleId,
  });

  @override
  State<TrainingPreScreen> createState() => _TrainingPreScreenState();
}

class _TrainingPreScreenState extends State<TrainingPreScreen> {
  late WorkoutDurationCourse _selectedCourse;
  late WorkoutCondition _selectedCondition;
  String? _focusMuscleId;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _selectedCourse = widget.initialCourse;
    _selectedCondition = widget.initialCondition;
    _focusMuscleId =
        (widget.initialFocusMuscleId != null &&
            MasterData.muscleById.containsKey(widget.initialFocusMuscleId))
        ? widget.initialFocusMuscleId
        : null;
  }

  Future<void> _handleStartPressed() async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
    });
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    try {
      final started = await widget.onStartWorkout(
        course: _selectedCourse,
        condition: _selectedCondition,
        focusMuscleId: _focusMuscleId,
      );
      if (!mounted) return;
      if (!started) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          const SnackBar(content: Text('実施可能な種目がありません。ケガ部位または超回復状態をご確認ください。')),
        );
      }
    } catch (_) {
      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.error,
            content: Text(
              'メニューの生成に失敗しました。もう一度お試しください。',
              style: TextStyle(color: AppColors.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeSlot = resolveTimeSlot(widget.clock());
    final sanitizedFocusId =
        (_focusMuscleId != null &&
            MasterData.muscleById.containsKey(_focusMuscleId))
        ? _focusMuscleId
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'のう筋（Noukin） — トレーニング',
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
            final useHorizontalCards = constraints.maxWidth >= 520;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTimeSlotBadge(timeSlot),
                      const SizedBox(height: 20),
                      _buildSectionTitle('1. 所要時間コース'),
                      const SizedBox(height: 10),
                      _buildCourseSelector(useHorizontalCards),
                      const SizedBox(height: 20),
                      _buildSectionTitle('2. 直前のコンディション'),
                      const SizedBox(height: 10),
                      _buildConditionSelector(useHorizontalCards),
                      const SizedBox(height: 20),
                      _buildSectionTitle('3. 今日フォーカスしたい筋肉（任意）'),
                      const SizedBox(height: 10),
                      _buildFocusMuscleDropdown(sanitizedFocusId),
                      const SizedBox(height: 28),
                      ElevatedButton(
                        key: const Key('btn_start_workout'),
                        onPressed: _isStarting ? null : _handleStartPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryAccent,
                          foregroundColor: AppColors.onPrimaryAccent,
                          minimumSize: const Size.fromHeight(52),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '開始する',
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildTimeSlotBadge(TimeSlot timeSlot) {
    return Container(
      key: const Key('detected_timeslot_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: AppColors.tealAccent, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '実施時間帯（自動判定）',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.highlightSelectedSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.tealAccent),
            ),
            child: Text(
              timeSlot.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.tealAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseSelector(bool horizontal) {
    final items = <Widget>[
      _buildOptionCard(
        optionKey: const Key('course_short'),
        title: WorkoutDurationCourse.short20.label,
        subtitle: '${WorkoutDurationCourse.short20.exerciseCount}種目',
        selected: _selectedCourse == WorkoutDurationCourse.short20,
        onTap: () {
          setState(() {
            _selectedCourse = WorkoutDurationCourse.short20;
          });
        },
      ),
      _buildOptionCard(
        optionKey: const Key('course_standard'),
        title: WorkoutDurationCourse.standard45.label,
        subtitle: '${WorkoutDurationCourse.standard45.exerciseCount}種目',
        selected: _selectedCourse == WorkoutDurationCourse.standard45,
        onTap: () {
          setState(() {
            _selectedCourse = WorkoutDurationCourse.standard45;
          });
        },
      ),
      _buildOptionCard(
        optionKey: const Key('course_full'),
        title: WorkoutDurationCourse.full60.label,
        subtitle: '${WorkoutDurationCourse.full60.exerciseCount}種目',
        selected: _selectedCourse == WorkoutDurationCourse.full60,
        onTap: () {
          setState(() {
            _selectedCourse = WorkoutDurationCourse.full60;
          });
        },
      ),
    ];

    return _buildResponsiveOptionGroup(items, horizontal: horizontal);
  }

  Widget _buildConditionSelector(bool horizontal) {
    final items = <Widget>[
      _buildOptionCard(
        optionKey: const Key('condition_great'),
        title: WorkoutCondition.great.label,
        subtitle: '100%・3セット',
        selected: _selectedCondition == WorkoutCondition.great,
        onTap: () {
          setState(() {
            _selectedCondition = WorkoutCondition.great;
          });
        },
      ),
      _buildOptionCard(
        optionKey: const Key('condition_normal'),
        title: WorkoutCondition.normal.label,
        subtitle: '100%・3セット',
        selected: _selectedCondition == WorkoutCondition.normal,
        onTap: () {
          setState(() {
            _selectedCondition = WorkoutCondition.normal;
          });
        },
      ),
      _buildOptionCard(
        optionKey: const Key('condition_tired'),
        title: WorkoutCondition.tired.label,
        subtitle: '重量-5%・2セット',
        selected: _selectedCondition == WorkoutCondition.tired,
        onTap: () {
          setState(() {
            _selectedCondition = WorkoutCondition.tired;
          });
        },
      ),
    ];

    return _buildResponsiveOptionGroup(items, horizontal: horizontal);
  }

  Widget _buildResponsiveOptionGroup(
    List<Widget> items, {
    required bool horizontal,
  }) {
    if (horizontal) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: items[i]),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          items[i],
        ],
      ],
    );
  }

  Widget _buildOptionCard({
    required Key optionKey,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.highlightSelectedSurface : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.tealAccent : AppColors.border,
          width: selected ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        key: optionKey,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? AppColors.tealAccent
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? AppColors.tealAccent
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusMuscleDropdown(String? currentValue) {
    final prioritizedMuscles = <Muscle>[
      for (final id in MasterData.quickInjuryMuscleIds)
        if (MasterData.muscleById[id] != null) MasterData.muscleById[id]!,
      for (final muscle in MasterData.muscles)
        if (!MasterData.quickInjuryMuscleIds.contains(muscle.id)) muscle,
    ];
    return InputDecorator(
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: const Key('focus_muscle_dropdown'),
          value: currentValue,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          iconEnabledColor: AppColors.tealAccent,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text(
                '指定なし',
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
            for (final muscle in prioritizedMuscles)
              DropdownMenuItem<String?>(
                value: muscle.id,
                child: Text(
                  '${muscle.name}（${muscle.group.label}）',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _focusMuscleId = value;
            });
          },
        ),
      ),
    );
  }
}
