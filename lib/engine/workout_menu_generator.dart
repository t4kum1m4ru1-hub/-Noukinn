import 'dart:math' as math;

import '../data/master_data.dart';
import '../models/models.dart';

/// 端末内で完結する確定型M値トレーニングメニュー生成エンジン（外部通信・LLM非依存）
class WorkoutMenuGenerator {
  const WorkoutMenuGenerator();

  /// B_i 上限キャップ（UI非露出のエンジン固定値）
  static const int bCap = 14;

  /// 協働筋の一時減衰係数（UI非露出のエンジン固定値）
  static const double synergistAttenuation = 0.75;

  /// 同一カテゴリの重複抑制係数（UI非露出のエンジン固定値）
  static const double sameCategoryAttenuation = 0.45;

  static const Map<String, String> _ageLabels = <String, String>{
    'under_20': '10代・20代前半',
    '20_30': '20代後半〜30代',
    '40s': '40代',
    '50s': '50代',
    '60_plus': '60代以上',
  };

  /// 優先度 P_i を正規化ティア（0, 10, 14, 18）へ丸める
  static int normalizePriorityTierVal(int val, [int fallback = 10]) {
    if (val == 0) return 0;
    if (val >= 16) return 18;
    if (val >= 12) return 14;
    return 10;
  }

  /// 誕生年（birthYear）から年齢係数区分キーを解決する
  static String resolveAgeBracket(int birthYear, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final age = effectiveNow.year - birthYear;
    if (age < 20) return 'under_20';
    if (age <= 39) return '20_30';
    if (age <= 49) return '40s';
    if (age <= 59) return '50s';
    return '60_plus';
  }

  static double _round1(double x) {
    if (!x.isFinite) return 0.0;
    final rounded = double.parse(x.toStringAsFixed(1));
    return rounded == 0.0 ? 0.0 : rounded;
  }

  static double _roundTo25(double x) {
    if (!x.isFinite || x <= 0.0) return 2.5;
    final rounded = (x / 2.5).round() * 2.5;
    return math.max(2.5, rounded);
  }

  /// Step 1: 全54筋肉の M値・協働用M値・回復ステータスを算出する
  Map<String, MuscleScoreInfo> computeMuscleScores({
    required Map<String, MuscleInputState> muscleStates,
    required UserProfile profile,
    WorkoutFeedback? lastFeedback,
    bool highVolumeMode = false,
    DateTime? now,
  }) {
    final isHighVolExtend =
        highVolumeMode || lastFeedback == WorkoutFeedback.tooHard;
    final ageBracket = resolveAgeBracket(profile.birthYear, now: now);
    final isAgeExtendR = ageBracket == '50s' || ageBracket == '60_plus';
    final purposeMap =
        MasterData.purposePriorities[profile.purpose] ?? const <String, int>{};

    final result = <String, MuscleScoreInfo>{};
    for (final m in MasterData.muscles) {
      final defaultP = purposeMap[m.id] ?? 10;
      final inp = muscleStates[m.id];
      final bRaw = inp == null ? 4 : math.max(0, inp.blankDays);
      final bCapped = math.min(bRaw, bCap);
      final pVal = inp == null
          ? defaultP
          : normalizePriorityTierVal(inp.priorityP, defaultP);
      final isExtendedR =
          isHighVolExtend && MasterData.highVolumeExtendMuscleIds.contains(m.id);
      final rVal =
          m.recoveryDays + (isExtendedR ? 1 : 0) + (isAgeExtendR ? 1 : 0);
      final rawS = inp == null ? 2.0 : inp.stimulationDays;
      final sVal = (!rawS.isFinite || rawS < 0.0) ? 0.0 : _round1(rawS);
      final isInjured = inp?.isInjured ?? false;
      final isUntargeted = !isInjured && pVal == 0;
      final isRecovering = !isInjured && !isUntargeted && bCapped < rVal;

      late final double mVal;
      late final MuscleScoreStatus status;
      if (isInjured) {
        mVal = 0.0;
        status = MuscleScoreStatus.injured;
      } else if (isUntargeted) {
        mVal = 0.0;
        status = MuscleScoreStatus.untargeted;
      } else if (isRecovering) {
        mVal = 0.0;
        status = MuscleScoreStatus.recovering;
      } else {
        mVal = math.max(0.0, _round1(bCapped + pVal - rVal - sVal));
        status = MuscleScoreStatus.active;
      }

      // 協働筋用基礎スコア: 鍛えない(p==0)部位でも回復完了時は内部優先度 P_syn = 6 で算出
      late final double synMVal;
      if (isInjured || bCapped < rVal) {
        synMVal = 0.0;
      } else if (pVal == 0) {
        synMVal = math.max(0.0, _round1(bCapped + 6 - rVal - sVal));
      } else {
        synMVal = mVal;
      }

      result[m.id] = MuscleScoreInfo(
        muscleId: m.id,
        bRaw: bRaw,
        bCapped: bCapped,
        priorityP: pVal,
        baseRecoveryDays: m.recoveryDays,
        effectiveRecoveryDays: rVal,
        stimulationDays: sVal,
        mVal: mVal,
        synMVal: synMVal,
        status: status,
        muscleName: m.name,
        group: m.group,
        timeCat: m.timeCat,
        isExtendedByVolume: isExtendedR,
        isExtendedByAge: isAgeExtendR,
      );
    }
    return result;
  }

  /// Steps 2–5: 素点・リアルタイム乗算補正・動的重複防止ループ・負荷処方を実行しメニューを生成する
  MenuGenerationResult generateMenu({
    required UserProfile profile,
    required Map<String, MuscleInputState> muscleStates,
    required Map<String, MachineHistoryEntry> machineHistory,
    required WorkoutDurationCourse course,
    required WorkoutCondition condition,
    String? focusMuscleId,
    DateTime? now,
    int sessionCount = 1,
    WorkoutFeedback? lastFeedback,
    bool highVolumeMode = false,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final timeSlot = resolveTimeSlot(effectiveNow);
    final effectiveSessionCount = sessionCount <= 0 ? 1 : sessionCount;
    final normalizedFocusId =
        (focusMuscleId != null && focusMuscleId.isNotEmpty)
            ? focusMuscleId
            : null;
    final effectiveStep1Feedback = lastFeedback ??
        (machineHistory.values.any(
              (e) => e.lastFeedback == WorkoutFeedback.tooHard,
            )
            ? WorkoutFeedback.tooHard
            : null);

    final muscleScores = computeMuscleScores(
      muscleStates: muscleStates,
      profile: profile,
      lastFeedback: effectiveStep1Feedback,
      highVolumeMode: highVolumeMode,
      now: effectiveNow,
    );

    final workingMMap = <String, double>{
      for (final entry in muscleScores.entries) entry.key: entry.value.mVal,
    };
    final workingSynMMap = <String, double>{
      for (final entry in muscleScores.entries) entry.key: entry.value.synMVal,
    };

    final selectedIds = <String>{};
    final pickedCatCounts = <MuscleGroup, int>{};
    final exercises = <PrescribedExercise>[];
    final targetCount = course.exerciseCount;

    for (var step = 0; step < targetCount; step++) {
      final candidates = <_MachineEval>[];
      for (final mac in MasterData.machines) {
        if (selectedIds.contains(mac.id)) continue;
        final ev = _evaluateMachine(
          machine: mac,
          mMap: workingMMap,
          synMMap: workingSynMMap,
          muscleScores: muscleScores,
          machineHistory: machineHistory,
          pickedCatCounts: pickedCatCounts,
          stepIndex: step,
          targetCount: targetCount,
          condition: condition,
          timeSlot: timeSlot,
          focusMuscleId: normalizedFocusId,
        );
        if (ev.finalScore > 0.0) {
          candidates.add(ev);
        }
      }
      if (candidates.isEmpty) break;

      candidates.sort((a, b) {
        final fCmp = b.finalScore.compareTo(a.finalScore);
        if (fCmp != 0) return fCmp;
        final rCmp = b.rawScore.compareTo(a.rawScore);
        if (rCmp != 0) return rCmp;
        return _tieBreakOrder(b.machine.id, effectiveSessionCount)
            .compareTo(_tieBreakOrder(a.machine.id, effectiveSessionCount));
      });

      final winner = candidates.first;
      selectedIds.add(winner.machine.id);
      pickedCatCounts[winner.machine.category] =
          (pickedCatCounts[winner.machine.category] ?? 0) + 1;

      // Step 4: 主動筋 M値を 0 に減衰（p > 0 筋のみ協働マップ同期）、協働筋は ×0.75 に一時減衰
      for (final pId in winner.machine.primaryMuscleIds) {
        workingMMap[pId] = 0.0;
        if ((muscleScores[pId]?.priorityP ?? 0) > 0) {
          workingSynMMap[pId] = 0.0;
        }
      }
      for (final sId in winner.machine.synergistMuscleIds) {
        final beforeM = workingMMap[sId] ?? 0.0;
        if (beforeM > 0.0) {
          workingMMap[sId] = _round1(beforeM * synergistAttenuation);
        }
        final beforeSyn = workingSynMMap[sId] ?? 0.0;
        if (beforeSyn > 0.0) {
          workingSynMMap[sId] = _round1(beforeSyn * synergistAttenuation);
        }
      }

      final rx = _computePrescription(
        machine: winner.machine,
        profile: profile,
        machineHistory: machineHistory,
        condition: condition,
        lastFeedback: lastFeedback,
        now: effectiveNow,
      );

      exercises.add(
        PrescribedExercise(
          machine: winner.machine,
          weightKg: rx.weightKg,
          reps: rx.reps,
          sets: rx.sets,
          primaryMuscleNames: winner.machine.primaryMuscleIds
              .map((id) => MasterData.muscleById[id]?.name ?? id)
              .toList(),
          synergistMuscleNames: winner.machine.synergistMuscleIds
              .map((id) => MasterData.muscleById[id]?.name ?? id)
              .toList(),
          finalScore: winner.finalScore,
          rawScore: winner.rawScore,
          reasons: <String>[...winner.reasons, ...rx.reasons],
        ),
      );
    }

    return MenuGenerationResult(
      exercises: exercises,
      muscleScores: muscleScores,
      timeSlot: timeSlot,
      course: course,
      condition: condition,
      generatedAt: effectiveNow,
      focusMuscleId: normalizedFocusId,
    );
  }

  static int _tieBreakOrder(String machineId, int effectiveSessionCount) {
    final idx = MasterData.machines.indexWhere((m) => m.id == machineId);
    return (idx + effectiveSessionCount * 7) % MasterData.machines.length;
  }

  _MachineEval _evaluateMachine({
    required Machine machine,
    required Map<String, double> mMap,
    required Map<String, double> synMMap,
    required Map<String, MuscleScoreInfo> muscleScores,
    required Map<String, MachineHistoryEntry> machineHistory,
    required Map<MuscleGroup, int> pickedCatCounts,
    required int stepIndex,
    required int targetCount,
    required WorkoutCondition condition,
    required TimeSlot timeSlot,
    required String? focusMuscleId,
  }) {
    final allInvolvedIds = <String>[
      ...machine.primaryMuscleIds,
      ...machine.synergistMuscleIds,
    ];
    final hasInjury = allInvolvedIds.any(
      (id) => muscleScores[id]?.status == MuscleScoreStatus.injured,
    );
    final injuryMultiplier = hasInjury ? 0.0 : 1.0;

    int getP(String id) => muscleScores[id]?.priorityP ?? 10;

    // Step 2.1: 主動筋スコア（最大70% + 上位2部位平均30%）& mac7 大腿筋膜張筋(m27) 例外ルール
    final isMac7 = machine.id == 'mac7';
    final excludedByTfl = isMac7 && getP('m27') == 0;
    final activePrimary = excludedByTfl
        ? machine.primaryMuscleIds.where((id) => id != 'm27').toList()
        : machine.primaryMuscleIds;
    final hasUntargetedPrimary =
        activePrimary.isEmpty || activePrimary.any((id) => getP(id) == 0);
    final untargetedMultiplier = hasUntargetedPrimary ? 0.0 : 1.0;

    var primaryMax = 0.0;
    var primaryScore = 0.0;
    if (!hasUntargetedPrimary) {
      final primaryVals = activePrimary
          .map((id) => mMap[id] ?? 0.0)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      primaryMax = primaryVals.isNotEmpty ? primaryVals.first : 0.0;
      final topCount = math.min(2, primaryVals.length);
      final topSum = primaryVals.take(topCount).fold(0.0, (a, b) => a + b);
      final primaryTop2Avg = topCount > 0 ? topSum / topCount : 0.0;
      primaryScore =
          primaryMax > 0.0 ? (primaryMax * 0.7) + (primaryTop2Avg * 0.3) : 0.0;
    }

    // Step 2.2: 協働筋スコア（上位2部位平均 × 0.3）
    final synVals = machine.synergistMuscleIds
        .map((id) => synMMap[id] ?? 0.0)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final topSynCount = math.min(2, synVals.length);
    final synTopSum = synVals.take(topSynCount).fold(0.0, (a, b) => a + b);
    final synergistTopAvg = topSynCount > 0 ? synTopSum / topSynCount : 0.0;
    final synergistScore = synergistTopAvg * 0.3;

    // Step 2.3: マシン別未実施セッション数ボーナス（3段階スケーリング）
    final rawSessions = machineHistory[machine.id]?.sessionsSinceUsed ??
        machine.defaultSessionsSinceUsed;
    final sessionsSinceUsed = math.max(0, rawSessions);
    final double baseRot;
    if (sessionsSinceUsed <= 5) {
      baseRot = sessionsSinceUsed * 0.7;
    } else if (sessionsSinceUsed <= 10) {
      baseRot = (5 * 0.7) + ((sessionsSinceUsed - 5) * 1.5);
    } else {
      baseRot = (5 * 0.7) + (5 * 1.5) + ((sessionsSinceUsed - 10) * 2.5);
    }
    final rotationBonus = primaryScore > 0.0 ? _round1(baseRot) : 0.0;

    // Step 2.4: 種目タイプ別の基礎適性補正
    final isIsoOrCore = machine.isIsolationOrCore;
    final isCompound5Plus = allInvolvedIds.length >= 5 && !isIsoOrCore;
    final catPickedCount = pickedCatCounts[machine.category] ?? 0;
    var structureBonus = 0.0;
    final reasons = <String>[];

    if (hasUntargetedPrimary) {
      reasons.add('鍛えない主動筋あり（選出対象外）');
    }
    if (primaryScore > 0.0) {
      if (stepIndex >= 2 ||
          condition == WorkoutCondition.tired ||
          timeSlot == TimeSlot.night) {
        if (isIsoOrCore) {
          structureBonus = 3.5;
          if (targetCount >= 4 &&
              stepIndex == targetCount - 1 &&
              catPickedCount == 0) {
            structureBonus += 3.0;
            reasons.add('終盤フィニッシャー未選出カテゴリ適性 (+6.5)');
          } else {
            reasons.add('後半・疲労/就寝前アイソレーション適性 (+3.5)');
          }
        }
      } else if (stepIndex <= 1) {
        if (isCompound5Plus) {
          structureBonus = 2.5;
          reasons.add('序盤コンパウンド適性 (+2.5)');
        } else if (isIsoOrCore && sessionsSinceUsed >= 8) {
          structureBonus = 3.0;
          reasons.add('長期未実施種目ピックアップ適性 (+3.0)');
        }
      }
      if (sessionsSinceUsed >= 10 && structureBonus < 4.0) {
        structureBonus = math.max(structureBonus, 4.0);
        reasons.add('長期未実施ローテーション優先 (+4.0)');
      }
    }

    final rawScore =
        primaryScore + synergistScore + structureBonus + rotationBonus;

    // Step 3: 時間帯・フォーカス・カテゴリ分散・ケガ/対象外乗算補正
    var timeMultiplier = 1.0;
    if (timeSlot == TimeSlot.morning) {
      final pHit = machine.primaryMuscleIds.any(
        (id) =>
            MasterData.muscleById[id]?.timeCat == MuscleTimeCategory.morningRec,
      );
      final sHit = machine.synergistMuscleIds.any(
        (id) =>
            MasterData.muscleById[id]?.timeCat == MuscleTimeCategory.morningRec,
      );
      if (pHit) {
        timeMultiplier = 1.25;
        reasons.add('朝活おすすめ主動筋 (×1.25)');
      } else if (sHit) {
        timeMultiplier = 1.10;
        reasons.add('朝活おすすめ協働筋 (×1.10)');
      }
    } else if (timeSlot == TimeSlot.evening) {
      final pHit = machine.primaryMuscleIds.any(
        (id) =>
            MasterData.muscleById[id]?.timeCat == MuscleTimeCategory.eveningRec,
      );
      final sHit = machine.synergistMuscleIds.any(
        (id) =>
            MasterData.muscleById[id]?.timeCat == MuscleTimeCategory.eveningRec,
      );
      if (pHit) {
        timeMultiplier = 1.08;
        reasons.add('夕方おすすめ主動筋 (×1.08)');
      } else if (sHit) {
        timeMultiplier = 1.02;
        reasons.add('夕方おすすめ協働筋 (×1.02)');
      }
    } else if (timeSlot == TimeSlot.night) {
      final pHit = machine.primaryMuscleIds.any(
        (id) => MasterData.nightAvoidMuscleIds.contains(id),
      );
      final sHit = machine.synergistMuscleIds.any(
        (id) => MasterData.nightAvoidMuscleIds.contains(id),
      );
      if (pHit) {
        timeMultiplier = 0.30;
        reasons.add('就寝前大筋群（主動）抑制 (×0.30)');
      } else if (sHit) {
        timeMultiplier = 0.65;
        reasons.add('就寝前大筋群（協働）配慮 (×0.65)');
      }
    }

    var focusMultiplier = 1.0;
    if (focusMuscleId != null && focusMuscleId.isNotEmpty) {
      final focusName =
          MasterData.muscleById[focusMuscleId]?.name ?? focusMuscleId;
      if (machine.primaryMuscleIds.contains(focusMuscleId)) {
        focusMultiplier = 1.25;
        reasons.add('フォーカス主動筋「$focusName」(×1.25)');
      } else if (machine.synergistMuscleIds.contains(focusMuscleId)) {
        focusMultiplier = 1.10;
        reasons.add('フォーカス協働筋「$focusName」(×1.10)');
      }
    }

    final catMultiplier = catPickedCount > 0
        ? math.pow(sameCategoryAttenuation, catPickedCount).toDouble()
        : 1.0;
    if (catPickedCount > 0) {
      reasons.add(
        '同カテゴリ重複抑制「${machine.category.label}」(×${catMultiplier.toStringAsFixed(2)})',
      );
    }

    final combinedMultiplier =
        timeMultiplier * focusMultiplier * catMultiplier;
    final adjusted = math.max(0.0, rawScore * combinedMultiplier);
    final finalScore = adjusted * injuryMultiplier * untargetedMultiplier;

    return _MachineEval(
      machine: machine,
      rawScore: rawScore,
      finalScore: finalScore,
      reasons: reasons,
    );
  }

  /// Step 5: 負荷決定（初回体重比推定 / 前回履歴±2.5kg / 年齢係数・疲労補正）
  _Prescription _computePrescription({
    required Machine machine,
    required UserProfile profile,
    required Map<String, MachineHistoryEntry> machineHistory,
    required WorkoutCondition condition,
    required WorkoutFeedback? lastFeedback,
    required DateTime now,
  }) {
    final reasons = <String>[];
    final ageBracket = resolveAgeBracket(profile.birthYear, now: now);
    final ageMul = MasterData.ageCoefficients[ageBracket] ?? 1.0;
    final ageLabel = _ageLabels[ageBracket] ?? '20代後半〜30代';

    double baseW;
    if (profile.isFirstTime) {
      final genderMul = profile.gender.firstTimeWeightFactor;
      final expMul = profile.experience.firstTimeWeightFactor;
      baseW = _roundTo25(
        profile.bodyWeightKg * machine.bwFactor * genderMul * expMul * ageMul,
      );
      reasons.add(
        '初回推定 (${profile.bodyWeightKg}kg × ${profile.gender.label}・${profile.experience.label}・$ageLabel ×${ageMul.toStringAsFixed(2)})',
      );
    } else {
      final entry = machineHistory[machine.id];
      final rawLast = entry?.lastWeightKg;
      baseW = (rawLast == null || !rawLast.isFinite || rawLast <= 0.0)
          ? machine.baseWeight
          : rawLast;
      final machineFb = entry?.lastFeedback ?? lastFeedback;
      if (machineFb == WorkoutFeedback.tooLight) {
        baseW += 2.5;
        reasons.add('前回軽すぎ +2.5kg');
      } else if (machineFb == WorkoutFeedback.tooHard) {
        baseW = math.max(2.5, baseW - 2.5);
        reasons.add('前回キツすぎ −2.5kg');
      } else {
        reasons.add('前回ちょうど維持');
      }

      if (ageBracket == '60_plus') {
        baseW = _roundTo25(baseW * 0.90);
        reasons.add('60代以上関節保護: 基準重量×0.90');
      }
    }

    var finalW = baseW;
    final sets = condition.sets;
    if (condition == WorkoutCondition.tired) {
      finalW = _roundTo25(baseW * condition.weightMultiplier);
      reasons.add('疲労気味: 重量−5% ＆ 2セット短縮');
    } else if (condition == WorkoutCondition.great) {
      reasons.add('絶好調: 通常負荷 3セット');
    } else {
      reasons.add('体調普通: 通常負荷 3セット');
    }

    var targetReps = machine.baseReps;
    if (ageBracket == '50s' && machine.baseReps == 10) {
      targetReps = 12;
      reasons.add('50代関節保護: 10回→12回シフト');
    } else if (ageBracket == '60_plus') {
      if (machine.baseReps == 10) {
        targetReps = 12;
        reasons.add('60代以上関節保護: 10回→12回シフト');
      } else if (machine.baseReps == 12) {
        targetReps = 15;
        reasons.add('60代以上関節保護: 12回→15回シフト');
      }
    }

    final safeFinalW =
        (!finalW.isFinite || finalW <= 0.0) ? 2.5 : math.max(2.5, finalW);

    return _Prescription(
      weightKg: safeFinalW,
      reps: targetReps,
      sets: sets,
      reasons: reasons,
    );
  }

  /// セッション完了後に各筋肉の B_i / S_i・マシン履歴・セッション回数を進める
  SessionAdvanceResult advanceSessionDay({
    required Map<String, MuscleInputState> muscleStates,
    required Map<String, MachineHistoryEntry> machineHistory,
    required List<PrescribedExercise> completedExercises,
    required WorkoutFeedback overallFeedback,
    required int sessionCount,
    int daysElapsed = 1,
  }) {
    final days = daysElapsed < 1 ? 1 : daysElapsed;
    final effectiveSessionCount = sessionCount <= 0 ? 1 : sessionCount;
    final decayFactor = math.pow(0.92, days).toDouble();

    final pickedMacIds = <String>{};
    final pickedByMachineId = <String, PrescribedExercise>{};
    final trainedPrimaryIds = <String>{};
    final trainedSynergistIds = <String>{};
    for (final ex in completedExercises) {
      pickedMacIds.add(ex.machine.id);
      pickedByMachineId[ex.machine.id] = ex;
      trainedPrimaryIds.addAll(ex.machine.primaryMuscleIds);
      trainedSynergistIds.addAll(ex.machine.synergistMuscleIds);
    }

    final updatedMuscleStates = <String, MuscleInputState>{};
    for (final m in MasterData.muscles) {
      final existing = muscleStates[m.id] ?? MuscleInputState(muscleId: m.id);
      final curB = math.max(0, existing.blankDays);
      final curS =
          (!existing.stimulationDays.isFinite || existing.stimulationDays < 0.0)
              ? 0.0
              : existing.stimulationDays;

      late final int nextB;
      late final double nextS;
      if (trainedPrimaryIds.contains(m.id)) {
        nextB = math.min(30, days);
        nextS = math.min(12.0, _round1((curS * decayFactor) + 1.5));
      } else if (trainedSynergistIds.contains(m.id)) {
        nextB = math.min(30, math.min(30, curB) + math.min(30, days));
        nextS = math.max(0.0, _round1((curS * decayFactor) + 0.3));
      } else {
        nextB = math.min(30, math.min(30, curB) + math.min(30, days));
        nextS = math.max(0.0, _round1(curS * decayFactor));
      }

      updatedMuscleStates[m.id] = existing.copyWith(
        blankDays: nextB,
        stimulationDays: nextS,
      );
    }

    final updatedMachineHistory = <String, MachineHistoryEntry>{};
    for (final mac in MasterData.machines) {
      final existing = machineHistory[mac.id] ??
          MachineHistoryEntry(
            machineId: mac.id,
            sessionsSinceUsed: mac.defaultSessionsSinceUsed,
          );
      if (pickedMacIds.contains(mac.id)) {
        final ex = pickedByMachineId[mac.id]!;
        updatedMachineHistory[mac.id] = existing.copyWith(
          sessionsSinceUsed: 0,
          lastWeightKg: ex.weightKg,
          lastFeedback: overallFeedback,
        );
      } else {
        final curSessions = math.max(0, existing.sessionsSinceUsed);
        updatedMachineHistory[mac.id] = existing.copyWith(
          sessionsSinceUsed: curSessions + 1,
        );
      }
    }

    return SessionAdvanceResult(
      muscleStates: updatedMuscleStates,
      machineHistory: updatedMachineHistory,
      sessionCount: effectiveSessionCount + 1,
    );
  }
}

class _MachineEval {
  final Machine machine;
  final double rawScore;
  final double finalScore;
  final List<String> reasons;

  const _MachineEval({
    required this.machine,
    required this.rawScore,
    required this.finalScore,
    required this.reasons,
  });
}

class _Prescription {
  final double weightKg;
  final int reps;
  final int sets;
  final List<String> reasons;

  const _Prescription({
    required this.weightKg,
    required this.reps,
    required this.sets,
    required this.reasons,
  });
}
