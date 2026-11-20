import 'package:flutter/material.dart';

import '../data/master_data.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// 画面 B: 機能設定＆カスタム（目的選択・ケガ部位フィルター・部位グループ一括調整・全54筋肉M値マトリクス）
class CustomSettingsScreen extends StatelessWidget {
  final AppState appState;

  const CustomSettingsScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final scores = appState.computeCurrentMuscleScores();
        final states = appState.muscleStates;
        final currentPurpose = appState.profile.purpose;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'のう筋（Noukin） — カスタム設定',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              key: const Key('muscle_matrix_list'),
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPurposeSection(currentPurpose),
                      const SizedBox(height: 20),
                      _buildInjuryFilterSection(states),
                      const SizedBox(height: 20),
                      _buildGroupBatchSection(),
                      const SizedBox(height: 20),
                      _buildMatrixSection(states, scores),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.tealAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPurposeSection(TrainingPurpose currentPurpose) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.flag_outlined,
            title: '1. トレーニング目的',
            subtitle: '目的に応じた優先度テンプレート（P）を全54筋肉へ配分します',
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TrainingPurpose>(
                key: const Key('purpose_selector'),
                value: currentPurpose,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                iconEnabledColor: AppColors.tealAccent,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                items: TrainingPurpose.values
                    .map(
                      (purpose) => DropdownMenuItem<TrainingPurpose>(
                        value: purpose,
                        child: Text(
                          purpose.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (newPurpose) {
                  if (newPurpose != null) {
                    appState.updatePurpose(newPurpose);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInjuryFilterSection(Map<String, MuscleInputState> states) {
    final injuredCount = states.values.where((s) => s.isInjured).length;
    return Container(
      key: const Key('injury_filter_section'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.healing_outlined,
            title: '2. ケガ部位フィルター（選択中: $injuredCount 部位）',
            subtitle: '選択された筋肉は M = 0 となり、対象マシンが候補から完全除外されます',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: MasterData.muscles.map((muscle) {
              final isInjured = states[muscle.id]?.isInjured ?? false;
              return Material(
                color: isInjured
                    ? AppColors.error.withValues(alpha: 0.22)
                    : AppColors.surfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: isInjured ? AppColors.error : AppColors.border,
                    width: isInjured ? 1.5 : 1.0,
                  ),
                ),
                child: InkWell(
                  key: Key('injury_toggle_${muscle.id}'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => appState.toggleMuscleInjury(muscle.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isInjured
                              ? Icons.cancel
                              : Icons.check_circle_outline,
                          size: 14,
                          color: isInjured
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            muscle.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isInjured
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isInjured
                                  ? AppColors.error
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupBatchSection() {
    return Container(
      key: const Key('group_batch_section'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.tune,
            title: '3. 部位グループ別 一括調整（6大カテゴリ）',
            subtitle: 'カテゴリ単位でブランク（B）・優先度（P）・刺激（S）を一括増減します',
          ),
          const SizedBox(height: 12),
          for (final group in MuscleGroup.values) ...[
            _buildGroupBatchCard(group),
            if (group != MuscleGroup.values.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupBatchCard(MuscleGroup group) {
    return Container(
      key: Key('group_batch_${group.name}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            group.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.tealAccent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ブランク (B)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              _buildSmallIconBtn(
                icon: Icons.remove,
                onTap: () => appState.applyGroupBatchAdjustment(
                  group,
                  blankDaysDelta: -1,
                ),
              ),
              const SizedBox(width: 6),
              _buildSmallIconBtn(
                icon: Icons.add,
                onTap: () => appState.applyGroupBatchAdjustment(
                  group,
                  blankDaysDelta: 1,
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => appState.applyGroupBatchAdjustment(
                  group,
                  blankDaysDelta: 5,
                ),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.highlightSelectedSurface,
                  foregroundColor: AppColors.tealAccent,
                  minimumSize: const Size(44, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text(
                  '+5',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '優先度 (P)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              _buildSmallIconBtn(
                icon: Icons.remove,
                onTap: () => appState.applyGroupBatchAdjustment(
                  group,
                  priorityDelta: -1,
                ),
              ),
              const SizedBox(width: 6),
              _buildSmallIconBtn(
                icon: Icons.add,
                onTap: () =>
                    appState.applyGroupBatchAdjustment(group, priorityDelta: 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '刺激 (S)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              _buildSmallIconBtn(
                icon: Icons.remove,
                onTap: () => appState.applyGroupBatchAdjustment(
                  group,
                  stimulationDaysDelta: -0.5,
                ),
              ),
              const SizedBox(width: 6),
              _buildSmallIconBtn(
                icon: Icons.add,
                onTap: () => appState.applyGroupBatchAdjustment(
                  group,
                  stimulationDaysDelta: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixSection(
    Map<String, MuscleInputState> states,
    Map<String, MuscleScoreInfo> scores,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.grid_view_rounded,
            title: '4. 全54筋肉 M値マトリクス ＆ 個別パラメータ編集',
            subtitle: '各筋肉のリアルタイムM値とブランク（B）・刺激（S）を個別調整できます',
          ),
          const SizedBox(height: 12),
          for (final muscle in MasterData.muscles) ...[
            _buildMatrixRow(
              muscle: muscle,
              state:
                  states[muscle.id] ??
                  MuscleInputState(muscleId: muscle.id, priorityP: 10),
              score: scores[muscle.id],
            ),
            if (muscle != MasterData.muscles.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildMatrixRow({
    required Muscle muscle,
    required MuscleInputState state,
    required MuscleScoreInfo? score,
  }) {
    final mValText = (score?.mVal ?? 0.0).toStringAsFixed(1);
    final status = score?.status ?? MuscleScoreStatus.active;
    final statusColor = switch (status) {
      MuscleScoreStatus.active => AppColors.tealAccent,
      MuscleScoreStatus.recovering => AppColors.amberAccent,
      MuscleScoreStatus.untargeted => AppColors.textTertiary,
      MuscleScoreStatus.injured => AppColors.error,
    };

    return Container(
      key: Key('matrix_row_${muscle.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: state.isInjured ? AppColors.error : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${muscle.name}（${muscle.group.label}）',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  'M: $mValText (${status.label})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'P: ${state.priorityP} / R: ${score?.effectiveRecoveryDays ?? muscle.recoveryDays}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'B: ${state.blankDays}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildSmallIconBtn(
                    icon: Icons.remove,
                    onTap: () => appState.updateMuscleState(
                      muscle.id,
                      blankDays: state.blankDays - 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildSmallIconBtn(
                    icon: Icons.add,
                    onTap: () => appState.updateMuscleState(
                      muscle.id,
                      blankDays: state.blankDays + 1,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'S: ${state.stimulationDays.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildSmallIconBtn(
                    icon: Icons.remove,
                    onTap: () => appState.updateMuscleState(
                      muscle.id,
                      stimulationDays: state.stimulationDays - 0.1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildSmallIconBtn(
                    icon: Icons.add,
                    onTap: () => appState.updateMuscleState(
                      muscle.id,
                      stimulationDays: state.stimulationDays + 0.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallIconBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton.filledTonal(
      icon: Icon(icon, size: 16),
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.tealAccent,
        minimumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
