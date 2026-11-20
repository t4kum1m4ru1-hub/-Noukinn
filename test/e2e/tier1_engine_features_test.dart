import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/engine/workout_menu_generator.dart';
import 'package:noukin/models/models.dart';

import 'e2e_test_helpers.dart';

/// Builds a [Map<String, MuscleInputState>] where only [activeMuscleIds] are
/// non-injured, allowing opaque-box evaluation of targeted machines via
/// [WorkoutMenuGenerator.generateMenu].
Map<String, MuscleInputState> _isolateMuscles({
  required TrainingPurpose purpose,
  required Set<String> activeMuscleIds,
  int blankDays = 4,
  double stimulationDays = 2.0,
  Map<String, MuscleInputState> overrides = const <String, MuscleInputState>{},
}) {
  final defaults = buildDefaultMuscleStates(
    purpose,
    blankDays: blankDays,
    stimulationDays: stimulationDays,
  );
  final result = <String, MuscleInputState>{};
  for (final entry in defaults.entries) {
    final override = overrides[entry.key];
    if (override != null) {
      result[entry.key] = override;
    } else if (activeMuscleIds.contains(entry.key)) {
      result[entry.key] = entry.value;
    } else {
      result[entry.key] = entry.value.copyWith(isInjured: true);
    }
  }
  return result;
}

/// Union of primary and synergist muscle IDs for the given [machineIds].
Set<String> _musclesForMachines(Iterable<String> machineIds) {
  final ids = <String>{};
  for (final machineId in machineIds) {
    final spec = kExpectedMachineSpecById[machineId]!;
    ids.addAll(spec.primaryMuscleIds);
    ids.addAll(spec.synergistMuscleIds);
  }
  return ids;
}

/// Builds a [MachineHistoryEntry] map overriding `sessionsSinceUsed` for
/// specific machines while preserving defaults for all others.
Map<String, MachineHistoryEntry> _historyWithOffsets(
  Map<String, int> sessionOffsets,
) {
  final overrides = <String, MachineHistoryEntry>{
    for (final e in sessionOffsets.entries)
      e.key: MachineHistoryEntry(
        machineId: e.key,
        sessionsSinceUsed: e.value,
      ),
  };
  return buildDefaultMachineHistory(overrides: overrides);
}

void main() {
  const generator = WorkoutMenuGenerator();

  // ===========================================================================
  // F1: Lossless Master Data (T1-F1-01 .. T1-F1-06)
  // ===========================================================================
  group('F1: Lossless Master Data', () {
    test('T1-F1-01: 54 muscles m0-m53 with exact names and group counts', () {
      expect(MasterData.muscles, hasLength(54));
      expect(MasterData.muscleById, hasLength(54));

      final seenIds = <String>{};
      final seenNames = <String>{};
      final groupCounts = <MuscleGroup, int>{
        for (final g in MuscleGroup.values) g: 0,
      };

      for (var i = 0; i < 54; i++) {
        final actual = MasterData.muscles[i];
        final expected = kExpectedMuscleSpecs[i];
        expect(actual.id, expected.id);
        expect(actual.name, expected.name);
        expect(actual.group, expected.group);
        expect(MasterData.muscleById[actual.id], actual);

        expect(seenIds.add(actual.id), isTrue);
        expect(seenNames.add(actual.name), isTrue);
        groupCounts[actual.group] = groupCounts[actual.group]! + 1;
      }

      expect(groupCounts[MuscleGroup.legsGlutes], 20);
      expect(groupCounts[MuscleGroup.chest], 5);
      expect(groupCounts[MuscleGroup.back], 7);
      expect(groupCounts[MuscleGroup.shoulders], 4);
      expect(groupCounts[MuscleGroup.arms], 9);
      expect(groupCounts[MuscleGroup.core], 9);
    });

    test('T1-F1-02: exact timeCat counts, nightAvoid set, and recoveryDays', () {
      final timeCatIds = <MuscleTimeCategory, List<String>>{
        for (final c in MuscleTimeCategory.values) c: <String>[],
      };
      final r3Ids = <String>{};
      final r2Ids = <String>{};
      final r1Ids = <String>{};

      for (var i = 0; i < 54; i++) {
        final actual = MasterData.muscles[i];
        final expected = kExpectedMuscleSpecs[i];
        expect(actual.timeCat, expected.timeCat);
        expect(actual.recoveryDays, expected.recoveryDays);
        timeCatIds[actual.timeCat]!.add(actual.id);
        if (actual.recoveryDays == 3) {
          r3Ids.add(actual.id);
        } else if (actual.recoveryDays == 2) {
          r2Ids.add(actual.id);
        } else {
          r1Ids.add(actual.id);
        }
      }

      expect(timeCatIds[MuscleTimeCategory.nightAvoid], <String>[
        'm0',
        'm1',
        'm2',
        'm3',
        'm4',
      ]);
      expect(timeCatIds[MuscleTimeCategory.eveningRec], <String>['m5', 'm6']);
      expect(timeCatIds[MuscleTimeCategory.morningRec], <String>[
        'm7',
        'm8',
        'm9',
        'm10',
        'm11',
        'm12',
      ]);
      expect(timeCatIds[MuscleTimeCategory.other], hasLength(41));

      expect(
        MasterData.nightAvoidMuscleIds,
        equals(kNightAvoidExtendedMuscleIds.toSet()),
      );
      expect(MasterData.nightAvoidMuscleIds, hasLength(8));

      expect(r3Ids, equals(<String>{
        'm0',
        'm1',
        'm2',
        'm3',
        'm4',
        'm9',
        'm13',
        'm14',
        'm16',
        'm17',
      }));
      expect(r2Ids, hasLength(44));
      expect(r1Ids, isEmpty);
    });

    test('T1-F1-03: 29 machines mac1-mac29, categories, and muscle integrity', () {
      expect(MasterData.machines, hasLength(29));
      expect(MasterData.machineById, hasLength(29));

      final categoryCounts = <MuscleGroup, int>{
        for (final g in MuscleGroup.values) g: 0,
      };
      final coveredMuscleIds = <String>{};

      for (var i = 0; i < 29; i++) {
        final actual = MasterData.machines[i];
        final expected = kExpectedMachineSpecs[i];
        expect(actual.id, expected.id);
        expect(actual.name, expected.name);
        expect(actual.category, expected.category);
        expect(actual.baseWeight, expected.baseWeight);
        expect(actual.bwFactor, expected.bwFactor);
        expect(actual.baseReps, expected.baseReps);
        expect(
          actual.defaultSessionsSinceUsed,
          expected.defaultSessionsSinceUsed,
        );
        expect(actual.primaryMuscleIds, expected.primaryMuscleIds);
        expect(actual.synergistMuscleIds, expected.synergistMuscleIds);
        expect(MasterData.machineById[actual.id], actual);

        for (final pId in actual.primaryMuscleIds) {
          expect(MasterData.muscleById.containsKey(pId), isTrue);
          expect(actual.synergistMuscleIds.contains(pId), isFalse);
          coveredMuscleIds.add(pId);
        }
        for (final sId in actual.synergistMuscleIds) {
          expect(MasterData.muscleById.containsKey(sId), isTrue);
          coveredMuscleIds.add(sId);
        }

        categoryCounts[actual.category] = categoryCounts[actual.category]! + 1;
      }

      expect(categoryCounts[MuscleGroup.legsGlutes], 10);
      expect(categoryCounts[MuscleGroup.chest], 5);
      expect(categoryCounts[MuscleGroup.back], 5);
      expect(categoryCounts[MuscleGroup.shoulders], 3);
      expect(categoryCounts[MuscleGroup.arms], 3);
      expect(categoryCounts[MuscleGroup.core], 3);
      expect(coveredMuscleIds, hasLength(54));
    });

    test('T1-F1-04: all 6 purpose priority templates match spec across 54 muscles', () {
      expect(MasterData.purposePriorities.keys, containsAll(TrainingPurpose.values));
      expect(MasterData.purposePriorities, hasLength(6));
      expect(TrainingPurpose.windsurfing.label, 'ウィンドサーフィン');

      for (final purpose in TrainingPurpose.values) {
        final actualMap = MasterData.purposePriorities[purpose]!;
        final expectedMap = kExpectedPurposePriorities[purpose]!;
        expect(actualMap, hasLength(54));

        final defaultStates = MasterData.defaultMuscleStates(purpose);
        expect(defaultStates, hasLength(54));

        for (final muscleId in expectedMap.keys) {
          final p = actualMap[muscleId]!;
          expect(p, expectedMap[muscleId]);
          expect(<int>{0, 10, 14, 18}.contains(p), isTrue);

          final state = defaultStates[muscleId]!;
          expect(state.muscleId, muscleId);
          expect(state.priorityP, p);
          expect(state.blankDays, 4);
          expect(state.stimulationDays, 2.0);
          expect(state.isInjured, isFalse);
        }
      }
    });

    test('T1-F1-05: quick injury, high-volume extend, age coeffs, default history', () {
      expect(MasterData.quickInjuryMuscleIds, hasLength(10));
      expect(
        MasterData.quickInjuryMuscleIds,
        equals(kQuickInjuryMuscleIds.toSet()),
      );

      expect(MasterData.highVolumeExtendMuscleIds, hasLength(9));
      expect(
        MasterData.highVolumeExtendMuscleIds,
        equals(kHighVolumeExtendMuscleIds.toSet()),
      );

      expect(MasterData.ageCoefficients, equals(kExpectedAgeCoefficients));

      final history = MasterData.defaultMachineHistory();
      expect(history, hasLength(29));
      for (final entry in kExpectedDefaultMachineOffsets.entries) {
        expect(history[entry.key]!.machineId, entry.key);
        expect(history[entry.key]!.sessionsSinceUsed, entry.value);
      }
    });

    test('T1-F1-06: isIsolationOrCore matches HTML classification across 29 machines', () {
      var isolationCount = 0;
      for (final machine in MasterData.machines) {
        final expected = kExpectedIsolationOrCoreMachineIds.contains(machine.id);
        expect(
          machine.isIsolationOrCore,
          expected,
          reason: 'Machine ${machine.id} isolation/core mismatch',
        );
        if (machine.isIsolationOrCore) {
          isolationCount++;
        }
      }
      expect(isolationCount, 14);
    });
  });

  // ===========================================================================
  // F2: Step 1 M-Value Engine & Guards (T1-F2-01 .. T1-F2-06)
  // ===========================================================================
  group('F2: Step 1 M-Value Engine & Guards', () {
    test('T1-F2-01: standard active M-score effectiveB + P - R - S', () {
      final profile = buildTestProfile(
        birthYear: 1996, // age 30 in 2026 -> 20_30
        purpose: TrainingPurpose.bodyMakeMale,
      );
      final states = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          'm2': const MuscleInputState(
            muscleId: 'm2',
            blankDays: 3, // B_i == R_i boundary (S1-08)
            stimulationDays: 2.0,
            priorityP: 18,
          ),
        },
      );

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: profile,
        now: kClockEvening1800,
      );

      expect(scores, hasLength(54));

      // S1-01: m0 (B=4, P=18, R=3, S=2 -> 17.0)
      expect(scores['m0']!.mVal, 17.0);
      expect(scores['m0']!.synMVal, 17.0);
      expect(scores['m0']!.effectiveRecoveryDays, 3);
      expect(scores['m0']!.status, MuscleScoreStatus.active);

      // S1-02: m5 (B=4, P=10, R=2, S=2 -> 10.0)
      expect(scores['m5']!.mVal, 10.0);
      expect(scores['m5']!.synMVal, 10.0);
      expect(scores['m5']!.effectiveRecoveryDays, 2);
      expect(scores['m5']!.status, MuscleScoreStatus.active);

      // S1-03: m7 (B=4, P=18, R=2, S=2 -> 18.0)
      expect(scores['m7']!.mVal, 18.0);
      expect(scores['m7']!.synMVal, 18.0);
      expect(scores['m7']!.status, MuscleScoreStatus.active);

      // S1-04: m9 (B=4, P=14, R=3, S=2 -> 13.0)
      expect(scores['m9']!.mVal, 13.0);
      expect(scores['m9']!.synMVal, 13.0);
      expect(scores['m9']!.effectiveRecoveryDays, 3);
      expect(scores['m9']!.status, MuscleScoreStatus.active);

      // S1-08: m2 (B=3 == R=3, P=18, S=2 -> 16.0)
      expect(scores['m2']!.mVal, 16.0);
      expect(scores['m2']!.synMVal, 16.0);
      expect(scores['m2']!.status, MuscleScoreStatus.active);
    });

    test('T1-F2-02: injury guard forces mVal = 0 and synMVal = 0', () {
      final profile = buildTestProfile(
        birthYear: 1996,
        purpose: TrainingPurpose.bodyMakeMale,
      );
      final states = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          // S1-13: injured primary with B=14, S=0, P=18
          'm0': const MuscleInputState(
            muscleId: 'm0',
            blankDays: 14,
            stimulationDays: 0.0,
            priorityP: 18,
            isInjured: true,
          ),
          // S1-14: injured untargeted muscle with P=0
          'm15': const MuscleInputState(
            muscleId: 'm15',
            blankDays: 4,
            stimulationDays: 2.0,
            priorityP: 0,
            isInjured: true,
          ),
        },
      );

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: profile,
        now: kClockEvening1800,
      );

      expect(scores['m0']!.mVal, 0.0);
      expect(scores['m0']!.synMVal, 0.0);
      expect(scores['m0']!.status, MuscleScoreStatus.injured);

      expect(scores['m15']!.mVal, 0.0);
      expect(scores['m15']!.synMVal, 0.0);
      expect(scores['m15']!.status, MuscleScoreStatus.injured);
    });

    test('T1-F2-03: super-recovery guard B < R and high S_i clamp to 0', () {
      final profile = buildTestProfile(
        birthYear: 1996,
        purpose: TrainingPurpose.bodyMakeMale,
      );

      // S1-05 (m1 B=0), S1-07 (m7 B=1), S1-11 (m29 B=14, S=30)
      final statesA = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          'm1': const MuscleInputState(
            muscleId: 'm1',
            blankDays: 0,
            stimulationDays: 2.0,
            priorityP: 18,
          ),
          'm7': const MuscleInputState(
            muscleId: 'm7',
            blankDays: 1,
            stimulationDays: 2.0,
            priorityP: 18,
          ),
          'm29': const MuscleInputState(
            muscleId: 'm29',
            blankDays: 14,
            stimulationDays: 30.0,
            priorityP: 18,
          ),
        },
      );

      final scoresA = generator.computeMuscleScores(
        muscleStates: statesA,
        profile: profile,
        now: kClockEvening1800,
      );

      expect(scoresA['m1']!.mVal, 0.0);
      expect(scoresA['m1']!.synMVal, 0.0);
      expect(scoresA['m1']!.status, MuscleScoreStatus.recovering);

      expect(scoresA['m7']!.mVal, 0.0);
      expect(scoresA['m7']!.synMVal, 0.0);
      expect(scoresA['m7']!.status, MuscleScoreStatus.recovering);

      expect(scoresA['m29']!.mVal, 0.0);
      expect(scoresA['m29']!.synMVal, 0.0);
      expect(scoresA['m29']!.status, MuscleScoreStatus.active);

      // S1-06 (m1 B=2 < R=3) & S1-12 (m29 B=4, S=30 -> negative clamped to 0)
      final statesB = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          'm1': const MuscleInputState(
            muscleId: 'm1',
            blankDays: 2,
            stimulationDays: 2.0,
            priorityP: 18,
          ),
          'm29': const MuscleInputState(
            muscleId: 'm29',
            blankDays: 4,
            stimulationDays: 30.0,
            priorityP: 18,
          ),
        },
      );

      final scoresB = generator.computeMuscleScores(
        muscleStates: statesB,
        profile: profile,
        now: kClockEvening1800,
      );

      expect(scoresB['m1']!.mVal, 0.0);
      expect(scoresB['m1']!.synMVal, 0.0);
      expect(scoresB['m1']!.status, MuscleScoreStatus.recovering);

      expect(scoresB['m29']!.mVal, 0.0);
      expect(scoresB['m29']!.synMVal, 0.0);
      expect(scoresB['m29']!.status, MuscleScoreStatus.active);
    });

    test('T1-F2-04: hardcoded bCap=14 caps blankDays=25 identically to 14', () {
      expect(WorkoutMenuGenerator.bCap, 14);
      final profile = buildTestProfile(
        birthYear: 1996,
        purpose: TrainingPurpose.bodyMakeMale,
      );
      final states = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          // S1-09: B=14
          'm3': const MuscleInputState(
            muscleId: 'm3',
            blankDays: 14,
            stimulationDays: 2.0,
            priorityP: 18,
          ),
          // S1-10: B=25 -> capped at 14
          'm4': const MuscleInputState(
            muscleId: 'm4',
            blankDays: 25,
            stimulationDays: 2.0,
            priorityP: 18,
          ),
        },
      );

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: profile,
        now: kClockEvening1800,
      );

      expect(scores['m3']!.bRaw, 14);
      expect(scores['m3']!.bCapped, 14);
      expect(scores['m3']!.mVal, 27.0);
      expect(scores['m3']!.synMVal, 27.0);

      expect(scores['m4']!.bRaw, 25);
      expect(scores['m4']!.bCapped, 14);
      expect(scores['m4']!.mVal, 27.0);
      expect(scores['m4']!.synMVal, 27.0);
    });

    test('T1-F2-05: dual map P_i=0 sets mVal=0 and synMVal with P_syn=6', () {
      final profile = buildTestProfile(
        birthYear: 1996,
        purpose: TrainingPurpose.bodyMakeMale,
      );

      // S1-15: m18 (P=0, B=4, R=2, S=2 -> synMVal = 6.0)
      final statesRecovered = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
      );
      final scoresRecovered = generator.computeMuscleScores(
        muscleStates: statesRecovered,
        profile: profile,
        now: kClockEvening1800,
      );

      expect(scoresRecovered['m18']!.mVal, 0.0);
      expect(scoresRecovered['m18']!.synMVal, 6.0);
      expect(scoresRecovered['m18']!.status, MuscleScoreStatus.untargeted);

      // S1-16: m18 (P=0, B=1 < R=2 -> synMVal = 0.0, status = untargeted)
      final statesRecovering = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          'm18': const MuscleInputState(
            muscleId: 'm18',
            blankDays: 1,
            stimulationDays: 2.0,
            priorityP: 0,
          ),
        },
      );
      final scoresRecovering = generator.computeMuscleScores(
        muscleStates: statesRecovering,
        profile: profile,
        now: kClockEvening1800,
      );

      expect(scoresRecovering['m18']!.mVal, 0.0);
      expect(scoresRecovering['m18']!.synMVal, 0.0);
      expect(scoresRecovering['m18']!.status, MuscleScoreStatus.untargeted);
    });

    test('T1-F2-06: R+1 extensions for age>=50 and tooHard/highVolume stack', () {
      // S1-17 & S1-18: tooHard at age 30 extends only HIGH_VOLUME_EXTEND_MUSCLES
      final profile30 = buildTestProfile(
        birthYear: 1996,
        purpose: TrainingPurpose.bodyMakeMale,
      );
      final statesA = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          'm34': const MuscleInputState(
            muscleId: 'm34',
            blankDays: 2,
            stimulationDays: 2.0,
            priorityP: 14,
          ),
          'm0': const MuscleInputState(
            muscleId: 'm0',
            blankDays: 3,
            stimulationDays: 2.0,
            priorityP: 18,
          ),
        },
      );

      final scoresTooHard30 = generator.computeMuscleScores(
        muscleStates: statesA,
        profile: profile30,
        lastFeedback: WorkoutFeedback.tooHard,
        now: kClockEvening1800,
      );
      expect(scoresTooHard30['m34']!.effectiveRecoveryDays, 3);
      expect(scoresTooHard30['m34']!.mVal, 0.0);
      expect(scoresTooHard30['m34']!.synMVal, 0.0);
      expect(scoresTooHard30['m34']!.status, MuscleScoreStatus.recovering);
      expect(scoresTooHard30['m0']!.effectiveRecoveryDays, 3);
      expect(scoresTooHard30['m0']!.mVal, 16.0);
      expect(scoresTooHard30['m0']!.status, MuscleScoreStatus.active);

      // highVolumeMode: true also triggers +1 R on m34 without tooHard
      final scoresHighVol30 = generator.computeMuscleScores(
        muscleStates: statesA,
        profile: profile30,
        highVolumeMode: true,
        now: kClockEvening1800,
      );
      expect(scoresHighVol30['m34']!.effectiveRecoveryDays, 3);
      expect(scoresHighVol30['m34']!.status, MuscleScoreStatus.recovering);

      // S1-19 & S1-20: 50s (birthYear 1970) extends ALL 54 muscles by +1 R
      final profile50s = buildTestProfile(
        birthYear: 1970,
        purpose: TrainingPurpose.bodyMakeMale,
      );
      final scores50sJustRight = generator.computeMuscleScores(
        muscleStates: statesA,
        profile: profile50s,
        lastFeedback: WorkoutFeedback.justRight,
        now: kClockEvening1800,
      );
      expect(scores50sJustRight['m0']!.effectiveRecoveryDays, 4);
      expect(scores50sJustRight['m0']!.mVal, 0.0);
      expect(scores50sJustRight['m0']!.status, MuscleScoreStatus.recovering);
      expect(scores50sJustRight['m34']!.effectiveRecoveryDays, 3);
      expect(scores50sJustRight['m34']!.mVal, 0.0);
      expect(scores50sJustRight['m34']!.status, MuscleScoreStatus.recovering);

      // S1-21: stacking tooHard + 50s -> R = 2+1+1 = 4 on m34 (B=3 -> recovering)
      final statesB3 = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: <String, MuscleInputState>{
          'm34': const MuscleInputState(
            muscleId: 'm34',
            blankDays: 3,
            stimulationDays: 2.0,
            priorityP: 14,
          ),
        },
      );
      final scoresStack50s = generator.computeMuscleScores(
        muscleStates: statesB3,
        profile: profile50s,
        lastFeedback: WorkoutFeedback.tooHard,
        now: kClockEvening1800,
      );
      expect(scoresStack50s['m34']!.effectiveRecoveryDays, 4);
      expect(scoresStack50s['m34']!.mVal, 0.0);
      expect(scoresStack50s['m34']!.status, MuscleScoreStatus.recovering);

      // S1-22: stacking tooHard + 60_plus (birthYear 1966) -> B=4 == R=4 -> 12.0
      final profile60Plus = buildTestProfile(
        birthYear: 1966,
        purpose: TrainingPurpose.bodyMakeMale,
      );
      final statesB4 = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final scoresStack60 = generator.computeMuscleScores(
        muscleStates: statesB4,
        profile: profile60Plus,
        lastFeedback: WorkoutFeedback.tooHard,
        now: kClockEvening1800,
      );
      expect(scoresStack60['m34']!.effectiveRecoveryDays, 4);
      expect(scoresStack60['m34']!.mVal, 12.0);
      expect(scoresStack60['m34']!.synMVal, 12.0);
      expect(scoresStack60['m34']!.status, MuscleScoreStatus.active);
    });
  });

  // ===========================================================================
  // F3: Step 2 Raw Score (T1-F3-01 .. T1-F3-06)
  // ===========================================================================
  group('F3: Step 2 Raw Score', () {
    final profile = buildTestProfile(
      birthYear: 1996,
      purpose: TrainingPurpose.bodyMakeMale,
    );

    test('T1-F3-01: primaryScore formula for 1-, 2-, and 3-primary machines', () {
      // S2-01: mac6 (1 primary: m1=17) -> rawScore = 24.25
      final resS201 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac6']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resS201.exercises, hasLength(1));
      expect(resS201.exercises.first.machine.id, 'mac6');
      expect(resS201.exercises.first.rawScore, closeTo(24.25, 1e-9));

      // S2-02: mac2 (2 equal primaries: m0=17, m2=17) -> rawScore = 28.4
      // Use sessionCount = 8 so mac2 wins tie-break over mac4.
      final resS202 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac2']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 8,
      );
      expect(resS202.exercises.first.machine.id, 'mac2');
      expect(resS202.exercises.first.rawScore, closeTo(28.4, 1e-9));

      // S2-03: mac2 asymmetric 2 primaries (m0 B=8 -> 21.0, m2 B=4 -> 17.0) -> 31.8
      final resS203 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac2']),
          overrides: <String, MuscleInputState>{
            'm0': const MuscleInputState(
              muscleId: 'm0',
              blankDays: 8,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 8,
      );
      expect(resS203.exercises.first.machine.id, 'mac2');
      expect(resS203.exercises.first.rawScore, closeTo(31.8, 1e-9));

      // S2-04: mac1 (3 primaries: 17, 17, 9 -> top2 [17, 17]) -> rawScore = 26.2
      // Set subset machines mac2, mac4, mac6 to n=0 so mac1 (n=4) is Pick #1.
      final resS204 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac1']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resS204.exercises.first.machine.id, 'mac1');
      expect(resS204.exercises.first.rawScore, closeTo(26.2, 1e-9));
    });

    test('T1-F3-02: mac7 strips TFL m27 when P_i=0 instead of zeroing mac7', () {
      // S2-05: default bodyMakeMale has m27 P=0 -> stripped, rawScore = 21.65
      final resStripped = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac7']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resStripped.exercises, hasLength(1));
      expect(resStripped.exercises.first.machine.id, 'mac7');
      expect(resStripped.exercises.first.rawScore, closeTo(21.65, 1e-9));
      expect(resStripped.exercises.first.finalScore, closeTo(23.382, 1e-9));

      // S2-06: override m27 P=18 -> m27 kept, rawScore = 23.55
      final resTargeted = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac7']),
          overrides: <String, MuscleInputState>{
            'm27': const MuscleInputState(
              muscleId: 'm27',
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resTargeted.exercises.first.machine.id, 'mac7');
      expect(resTargeted.exercises.first.rawScore, closeTo(23.55, 1e-9));
    });

    test('T1-F3-03: non-TFL primary muscle with P_i=0 zeros finalScore', () {
      // S2-07: mac7 with m2 P=0 (while m27 P=0) -> finalScore = 0.0 -> excluded
      final resMac7Zero = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac7']),
          overrides: <String, MuscleInputState>{
            'm2': const MuscleInputState(
              muscleId: 'm2',
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resMac7Zero.exercises, isEmpty);

      // mac6 with primary m1 P=0 -> excluded
      final resMac6Zero = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac6']),
          overrides: <String, MuscleInputState>{
            'm1': const MuscleInputState(
              muscleId: 'm1',
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resMac6Zero.exercises, isEmpty);
    });

    test('T1-F3-04: synergistScore uses avgTop2(synMVal) * 0.3 including P_syn=6', () {
      // S2-08: mac5 (m0=17, m13=9; syn m18 P=0 -> synMVal=6.0) -> rawScore = 30.1
      final resS208 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac5']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resS208.exercises.first.machine.id, 'mac5');
      expect(resS208.exercises.first.rawScore, closeTo(30.1, 1e-9));

      // S2-09: mac5 with primaries recovering (B=1 < R=3) -> rawScore = finalScore = 1.8
      final resS209 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac5']),
          overrides: <String, MuscleInputState>{
            'm0': const MuscleInputState(
              muscleId: 'm0',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm13': const MuscleInputState(
              muscleId: 'm13',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 10,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resS209.exercises, hasLength(1));
      expect(resS209.exercises.first.machine.id, 'mac5');
      expect(resS209.exercises.first.rawScore, closeTo(1.8, 1e-9));
      expect(resS209.exercises.first.finalScore, closeTo(1.8, 1e-9));
    });

    test('T1-F3-05: rotationBonus 3-stage scaling gated by primaryScore > 0', () {
      const expectedByN = <int, double>{
        0: 19.25,
        4: 22.05,
        5: 22.75,
        6: 24.25,
        8: 30.25, // +3.0 iso structure bonus at n >= 8
        10: 34.25, // +4.0 structure bonus at n >= 10
        11: 36.75,
        15: 46.75,
      };
      final mac6Muscles = _musclesForMachines(<String>['mac6']);

      for (final entry in expectedByN.entries) {
        final res = generator.generateMenu(
          profile: profile,
          muscleStates: _isolateMuscles(
            purpose: TrainingPurpose.bodyMakeMale,
            activeMuscleIds: mac6Muscles,
          ),
          machineHistory: _historyWithOffsets(<String, int>{'mac6': entry.key}),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockEvening1800,
          sessionCount: 1,
        );
        expect(res.exercises.first.machine.id, 'mac6');
        expect(
          res.exercises.first.rawScore,
          closeTo(entry.value, 1e-9),
          reason: 'mac6 step=0 rawScore mismatch at n=${entry.key}',
        );
      }

      // Gating check: primaryScore == 0 gives rotationBonus = 0 even at n = 9
      final resZeroPrimary = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac5']),
          overrides: <String, MuscleInputState>{
            'm0': const MuscleInputState(
              muscleId: 'm0',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm13': const MuscleInputState(
              muscleId: 'm13',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 10,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(resZeroPrimary.exercises.first.rawScore, closeTo(1.8, 1e-9));
    });

    test('T1-F3-06: structureBonus compound, iso/tired/night, and finisher rules', () {
      // 1. Compound mac1 (step=0 normal +2.5 -> 26.2; tired +0.0 -> 23.7; n=10 -> 35.9)
      final mac1States = _isolateMuscles(
        purpose: TrainingPurpose.bodyMakeMale,
        activeMuscleIds: _musclesForMachines(<String>['mac1']),
      );
      final mac1Normal = generator.generateMenu(
        profile: profile,
        muscleStates: mac1States,
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(mac1Normal.exercises.first.machine.id, 'mac1');
      expect(mac1Normal.exercises.first.rawScore, closeTo(26.2, 1e-9));

      final mac1Tired = generator.generateMenu(
        profile: profile,
        muscleStates: mac1States,
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        now: kClockEvening1800,
      );
      expect(mac1Tired.exercises.first.machine.id, 'mac1');
      expect(mac1Tired.exercises.first.rawScore, closeTo(23.7, 1e-9));

      final mac1N10 = generator.generateMenu(
        profile: profile,
        muscleStates: mac1States,
        machineHistory: _historyWithOffsets(<String, int>{
          'mac1': 10,
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(mac1N10.exercises.first.machine.id, 'mac1');
      expect(mac1N10.exercises.first.rawScore, closeTo(35.9, 1e-9));

      // 2. Iso mac6 (n=6): step=0 normal 24.25, tired +3.5 -> 27.75, night +3.5 -> 27.75
      final mac6States = _isolateMuscles(
        purpose: TrainingPurpose.bodyMakeMale,
        activeMuscleIds: _musclesForMachines(<String>['mac6']),
      );
      final mac6Tired = generator.generateMenu(
        profile: profile,
        muscleStates: mac6States,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        now: kClockEvening1800,
      );
      expect(mac6Tired.exercises.first.rawScore, closeTo(27.75, 1e-9));

      final mac6Night = generator.generateMenu(
        profile: profile,
        muscleStates: mac6States,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(mac6Night.exercises.first.rawScore, closeTo(27.75, 1e-9));

      // 3. Disjoint 4-machine pool (mac23, mac27, mac26, mac6) for step=2, step=3, short20
      final multiStates = _isolateMuscles(
        purpose: TrainingPurpose.bodyMakeMale,
        activeMuscleIds: _musclesForMachines(<String>[
          'mac23',
          'mac27',
          'mac26',
          'mac6',
        ]),
      );

      // step=2 (targetCount=4): mac23 & mac27 picked first -> mac6 gets +3.5 -> 27.75
      final step2Res = generator.generateMenu(
        profile: profile,
        muscleStates: multiStates,
        machineHistory: _historyWithOffsets(<String, int>{
          'mac23': 30,
          'mac27': 30,
          'mac26': 0,
        }),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(step2Res.exercises[2].machine.id, 'mac6');
      expect(step2Res.exercises[2].rawScore, closeTo(27.75, 1e-9));

      // step=3 (targetCount=4, catPicked=0): mac23, mac27, mac26 picked first -> +6.5 -> 30.75
      final step3Res = generator.generateMenu(
        profile: profile,
        muscleStates: multiStates,
        machineHistory: _historyWithOffsets(<String, int>{
          'mac23': 30,
          'mac27': 30,
          'mac26': 30,
        }),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(step3Res.exercises[3].machine.id, 'mac6');
      expect(step3Res.exercises[3].rawScore, closeTo(30.75, 1e-9));

      // short20 (targetCount=2): step=1 does NOT award +6.5 finisher -> 24.25
      final shortRes = generator.generateMenu(
        profile: profile,
        muscleStates: multiStates,
        machineHistory: _historyWithOffsets(<String, int>{
          'mac23': 30,
          'mac27': 0,
          'mac26': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(shortRes.exercises[1].machine.id, 'mac6');
      expect(shortRes.exercises[1].rawScore, closeTo(24.25, 1e-9));
    });
  });

  // ===========================================================================
  // F4: Step 3 Time Slot & Multipliers (T1-F4-01 .. T1-F4-06)
  // ===========================================================================
  group('F4: Step 3 Time Slot & Multipliers', () {
    final profile = buildTestProfile(
      birthYear: 1996,
      purpose: TrainingPurpose.bodyMakeMale,
    );

    test('T1-F4-01: resolveTimeSlot & generateMenu.timeSlot cover all 4 slots', () {
      final expectedSlots = <DateTime, TimeSlot>{
        kClockBoundary0500: TimeSlot.morning,
        kClockMorning0800: TimeSlot.morning,
        kClockBoundary115959: TimeSlot.morning,
        kClockBoundary1200: TimeSlot.daytime,
        kClockDaytime1300: TimeSlot.daytime,
        kClockBoundary145959: TimeSlot.daytime,
        kClockBoundary1500: TimeSlot.evening,
        kClockEvening1800: TimeSlot.evening,
        kClockBoundary205959: TimeSlot.evening,
        kClockBoundary2100: TimeSlot.night,
        kClockNight2230: TimeSlot.night,
        kClockBoundary235959: TimeSlot.night,
        kClockBoundary0000: TimeSlot.night,
        kClockBoundary045959: TimeSlot.night,
      };

      for (final entry in expectedSlots.entries) {
        expect(resolveTimeSlot(entry.key), entry.value);
      }

      final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = buildDefaultMachineHistory();
      for (final clock in <DateTime>[
        kClockMorning0800,
        kClockDaytime1300,
        kClockEvening1800,
        kClockNight2230,
      ]) {
        final res = generator.generateMenu(
          profile: profile,
          muscleStates: states,
          machineHistory: history,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: clock,
        );
        expect(res.timeSlot, resolveTimeSlot(clock));
      }
    });

    test('T1-F4-02: morning applies x1.25 primary and x1.10 synergist for morningRec', () {
      // S3-01: mac29 (m9 morningRec primary) in morning -> 20.9 * 1.25 = 26.125
      final mac29States = _isolateMuscles(
        purpose: TrainingPurpose.bodyMakeMale,
        activeMuscleIds: _musclesForMachines(<String>['mac29']),
      );
      final resMorningPrimary = generator.generateMenu(
        profile: profile,
        muscleStates: mac29States,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockMorning0800,
      );
      expect(resMorningPrimary.exercises.first.machine.id, 'mac29');
      expect(resMorningPrimary.exercises.first.rawScore, closeTo(20.9, 1e-9));
      expect(
        resMorningPrimary.exercises.first.finalScore,
        closeTo(26.125, 1e-9),
      );

      // S3-02: mac29 in daytime -> 20.9 * 1.0 = 20.9
      final resDaytime = generator.generateMenu(
        profile: profile,
        muscleStates: mac29States,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
      );
      expect(resDaytime.exercises.first.rawScore, closeTo(20.9, 1e-9));
      expect(resDaytime.exercises.first.finalScore, closeTo(20.9, 1e-9));

      // S3-05: mac28 (m7/m9 morningRec synergist only) in morning -> 18.3 * 1.10 = 20.13
      final resMorningSyn = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac28']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockMorning0800,
      );
      expect(resMorningSyn.exercises.first.machine.id, 'mac28');
      expect(resMorningSyn.exercises.first.rawScore, closeTo(18.3, 1e-9));
      expect(resMorningSyn.exercises.first.finalScore, closeTo(20.13, 1e-9));
    });

    test('T1-F4-03: evening applies x1.08 primary and x1.02 synergist for eveningRec', () {
      // S3-03: mac29 (no eveningRec) in evening -> x1.0 -> 20.9
      final resMac29 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac29']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resMac29.exercises.first.rawScore, closeTo(20.9, 1e-9));
      expect(resMac29.exercises.first.finalScore, closeTo(20.9, 1e-9));

      // S3-14: mac7 (m5 primary) -> 21.65 * 1.08 = 23.382
      final resMac7 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac7']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resMac7.exercises.first.rawScore, closeTo(21.65, 1e-9));
      expect(resMac7.exercises.first.finalScore, closeTo(23.382, 1e-9));

      // S3-15: mac3 (m5 synergist only) -> 24.95 * 1.02 = 25.449
      final resMac3 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac3']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resMac3.exercises.first.machine.id, 'mac3');
      expect(resMac3.exercises.first.rawScore, closeTo(24.95, 1e-9));
      expect(resMac3.exercises.first.finalScore, closeTo(25.449, 1e-9));

      // S3-16: mac17 (m6 primary) -> 25.35 * 1.08 = 27.378
      final resMac17 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac17']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resMac17.exercises.first.machine.id, 'mac17');
      expect(resMac17.exercises.first.rawScore, closeTo(25.35, 1e-9));
      expect(resMac17.exercises.first.finalScore, closeTo(27.378, 1e-9));

      // S3-17: mac21 (m6 synergist only) -> 26.8 * 1.02 = 27.336
      final resMac21 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac21']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac12': 0,
          'mac23': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resMac21.exercises.first.machine.id, 'mac21');
      expect(resMac21.exercises.first.rawScore, closeTo(26.8, 1e-9));
      expect(resMac21.exercises.first.finalScore, closeTo(27.336, 1e-9));
    });

    test('T1-F4-04: night applies x0.30 primary and x0.65 synergist for 8 nightAvoid muscles', () {
      // S3-04: mac29 (m9 primary) -> raw=24.4, final=7.32
      final resMac29 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac29']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac29.exercises.first.rawScore, closeTo(24.4, 1e-9));
      expect(resMac29.exercises.first.finalScore, closeTo(7.32, 1e-9));

      // S3-06: mac28 (m9 synergist only) -> raw=21.8, final=14.17
      final resMac28 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac28']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac28.exercises.first.rawScore, closeTo(21.8, 1e-9));
      expect(resMac28.exercises.first.finalScore, closeTo(14.17, 1e-9));

      // S3-07: mac1 (m0, m2 primary) -> raw=23.7, final=7.11
      final resMac1 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac1']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac1.exercises.first.machine.id, 'mac1');
      expect(resMac1.exercises.first.rawScore, closeTo(23.7, 1e-9));
      expect(resMac1.exercises.first.finalScore, closeTo(7.11, 1e-9));

      // S3-08: mac6 (m1 primary) -> raw=27.75, final=8.325
      final resMac6 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac6']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac6.exercises.first.rawScore, closeTo(27.75, 1e-9));
      expect(resMac6.exercises.first.finalScore, closeTo(8.325, 1e-9));

      // S3-09: mac11 (m3 primary) -> raw=24.0, final=7.2
      final resMac11 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac11']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac11.exercises.first.rawScore, closeTo(24.0, 1e-9));
      expect(resMac11.exercises.first.finalScore, closeTo(7.2, 1e-9));

      // S3-10: mac16 (m4 primary); set m36 P=0 so subset mac22 is excluded
      final resMac16 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac16']),
          overrides: <String, MuscleInputState>{
            'm36': const MuscleInputState(
              muscleId: 'm36',
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac16.exercises.first.machine.id, 'mac16');
      expect(resMac16.exercises.first.rawScore, closeTo(23.55, 1e-9));
      expect(resMac16.exercises.first.finalScore, closeTo(7.065, 1e-9));

      // S3-11: mac12 (m29 primary) -> raw=27.8, final=8.34
      final resMac12 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac12']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac12.exercises.first.rawScore, closeTo(27.8, 1e-9));
      expect(resMac12.exercises.first.finalScore, closeTo(8.34, 1e-9));

      // S3-12: mac21 (m29 synergist only) at n=11 -> raw=39.7, final=25.805 (x0.65 > mac23's 24.5)
      final resMac21Night = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac21']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac21': 11,
          'mac12': 0,
          'mac23': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac21Night.exercises.first.machine.id, 'mac21');
      expect(resMac21Night.exercises.first.rawScore, closeTo(39.7, 1e-9));
      expect(resMac21Night.exercises.first.finalScore, closeTo(25.805, 1e-9));

      // S3-13: mac13 (m30 primary) -> raw=21.65, final=6.495
      final resMac13 = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac13']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockNight2230,
      );
      expect(resMac13.exercises.first.rawScore, closeTo(21.65, 1e-9));
      expect(resMac13.exercises.first.finalScore, closeTo(6.495, 1e-9));
    });

    test('T1-F4-05: focusMuscleId applies x1.25 primary / x1.10 synergist stacking with timeMult', () {
      // S3-18: mac21 + focus m34 (primary) in evening -> 26.8 * 1.02 * 1.25 = 34.17
      final resPrimaryFocus = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac21']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac12': 0,
          'mac23': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        focusMuscleId: 'm34',
        now: kClockEvening1800,
      );
      expect(resPrimaryFocus.exercises.first.machine.id, 'mac21');
      expect(resPrimaryFocus.exercises.first.rawScore, closeTo(26.8, 1e-9));
      expect(resPrimaryFocus.exercises.first.finalScore, closeTo(34.17, 1e-9));

      // S3-19: mac11 + focus m34 (synergist) in evening -> 26.5 * 1.0 * 1.10 = 29.15
      final resSynFocus = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac11']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        focusMuscleId: 'm34',
        now: kClockEvening1800,
      );
      expect(resSynFocus.exercises.first.machine.id, 'mac11');
      expect(resSynFocus.exercises.first.rawScore, closeTo(26.5, 1e-9));
      expect(resSynFocus.exercises.first.finalScore, closeTo(29.15, 1e-9));

      // S3-20: mac1 + focus m34 (uninvolved) in evening -> 26.2 * 1.0 * 1.0 = 26.2
      final resUninvolvedFocus = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac1']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        focusMuscleId: 'm34',
        now: kClockEvening1800,
      );
      expect(resUninvolvedFocus.exercises.first.machine.id, 'mac1');
      expect(resUninvolvedFocus.exercises.first.rawScore, closeTo(26.2, 1e-9));
      expect(resUninvolvedFocus.exercises.first.finalScore, closeTo(26.2, 1e-9));
    });

    test('T1-F4-06: injury in primary OR synergist excludes machine with x0.0', () {
      // S3-21: synergist-only injury (m18) excludes mac5 despite m0/m13 active
      final resSynInjured = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac5']),
          overrides: <String, MuscleInputState>{
            'm18': const MuscleInputState(
              muscleId: 'm18',
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 0,
              isInjured: true,
            ),
          },
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resSynInjured.exercises, isEmpty);

      // S3-22: primary injury (m0) excludes mac1
      final resPrimInjured = generator.generateMenu(
        profile: profile,
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac1']),
          overrides: <String, MuscleInputState>{
            'm0': const MuscleInputState(
              muscleId: 'm0',
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 18,
              isInjured: true,
            ),
          },
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resPrimInjured.exercises, isEmpty);
    });
  });

  // ===========================================================================
  // F5: Step 4 Dynamic Overlap Prevention & Tie-Break (T1-F5-01 .. T1-F5-06)
  // ===========================================================================
  group('F5: Step 4 Dynamic Overlap Prevention & Tie-Break', () {
    final profile = buildTestProfile(
      birthYear: 1996,
      purpose: TrainingPurpose.bodyMakeMale,
    );

    test('T1-F5-01: short20=2, standard45=4, full60=5 unique baseline picks', () {
      final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = buildDefaultMachineHistory();

      final shortRes = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(
        shortRes.exercises.map((e) => e.machine.id).toList(),
        equals(<String>['mac20', 'mac5']),
      );
      expect(shortRes.exercises[0].finalScore, closeTo(32.13, 1e-9));
      expect(shortRes.exercises[1].finalScore, closeTo(30.1, 1e-9));

      final stdRes = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(
        stdRes.exercises.map((e) => e.machine.id).toList(),
        equals(<String>['mac20', 'mac5', 'mac23', 'mac14']),
      );
      expect(stdRes.exercises[2].finalScore, closeTo(29.125, 1e-9));
      expect(stdRes.exercises[3].finalScore, closeTo(31.725, 1e-9));

      final fullRes = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(
        fullRes.exercises.map((e) => e.machine.id).toList(),
        equals(<String>['mac20', 'mac5', 'mac23', 'mac14', 'mac27']),
      );
      expect(fullRes.exercises[3].finalScore, closeTo(28.725, 1e-9));
      expect(fullRes.exercises[4].finalScore, closeTo(29.6, 1e-9));
      expect(
        fullRes.exercises.map((e) => e.machine.id).toSet(),
        hasLength(5),
      );
    });

    test('T1-F5-02: picking machine zeroes primaries in working mMap & synMMap', () {
      // Leg-only eligible trace: mac5 zeroes m0 & m13, so mac4 Pick #2 loses m0
      // (prim = 14.45 instead of 17.0); mac6 zeroes m1 & mac4 zeroes m2, etc.
      final legOnlyStates = <String, MuscleInputState>{
        for (final entry
            in buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale).entries)
          entry.key: kExpectedMuscleSpecById[entry.key]!.group ==
                  MuscleGroup.legsGlutes
              ? entry.value
              : entry.value.copyWith(blankDays: 0),
      };

      final res = generator.generateMenu(
        profile: profile,
        muscleStates: legOnlyStates,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );

      expect(
        res.exercises.map((e) => e.machine.id).toList(),
        equals(<String>['mac5', 'mac4', 'mac6', 'mac10']),
      );
      // mac4 rawScore = 14.45 + 3.9 + 5.0 + 2.5 = 25.85 (only possible with m0=0)
      expect(res.exercises[1].rawScore, closeTo(25.85, 1e-9));
      // mac10 rawScore = 6.8 + 1.8 + 6.5 + 3.5 = 18.6 (m17 zeroed by mac6)
      expect(res.exercises[3].rawScore, closeTo(18.6, 1e-9));
    });

    test('T1-F5-03: picking machine attenuates synergists by x0.75 (1-decimal)', () {
      // Baseline standard45 proves m41 (10.0->7.5) and m33 (10.0->7.5) attenuations
      final stdRes = generator.generateMenu(
        profile: profile,
        muscleStates: buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(stdRes.exercises[2].machine.id, 'mac23');
      expect(stdRes.exercises[2].rawScore, closeTo(29.125, 1e-9));
      expect(stdRes.exercises[3].machine.id, 'mac14');
      expect(stdRes.exercises[3].rawScore, closeTo(31.725, 1e-9));

      // Leg-only trace verifies round1(17.0*0.75)=12.8 on m1 & round1(9.0*0.75)=6.8 on m17
      final legOnlyStates = <String, MuscleInputState>{
        for (final entry
            in buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale).entries)
          entry.key: kExpectedMuscleSpecById[entry.key]!.group ==
                  MuscleGroup.legsGlutes
              ? entry.value
              : entry.value.copyWith(blankDays: 0),
      };
      final legRes = generator.generateMenu(
        profile: profile,
        muscleStates: legOnlyStates,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );
      expect(legRes.exercises[2].machine.id, 'mac6');
      expect(legRes.exercises[2].rawScore, closeTo(23.55, 1e-9));
    });

    test('T1-F5-04: same-category multiplier decays geometrically as 0.45^k', () {
      expect(WorkoutMenuGenerator.sameCategoryAttenuation, 0.45);
      expect(WorkoutMenuGenerator.synergistAttenuation, 0.75);

      final legOnlyStates = <String, MuscleInputState>{
        for (final entry
            in buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale).entries)
          entry.key: kExpectedMuscleSpecById[entry.key]!.group ==
                  MuscleGroup.legsGlutes
              ? entry.value
              : entry.value.copyWith(blankDays: 0),
      };
      final legRes = generator.generateMenu(
        profile: profile,
        muscleStates: legOnlyStates,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );

      expect(legRes.exercises, hasLength(4));
      expect(legRes.exercises[0].finalScore, closeTo(30.1, 1e-9));
      expect(legRes.exercises[1].rawScore, closeTo(25.85, 1e-9));
      expect(legRes.exercises[1].finalScore, closeTo(11.6325, 1e-9));
      expect(legRes.exercises[2].rawScore, closeTo(23.55, 1e-9));
      expect(legRes.exercises[2].finalScore, closeTo(4.768875, 1e-9));
      expect(legRes.exercises[3].rawScore, closeTo(18.6, 1e-9));
      expect(legRes.exercises[3].finalScore, closeTo(1.694925, 1e-9));
    });

    test('T1-F5-05: dynamic step re-scoring shifts finisher bonus and rankings', () {
      final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = buildDefaultMachineHistory();

      final stdRes = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      final fullRes = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );

      // Pick #4 mac14 gets +6.5 in standard45 vs +3.5 in full60 (difference = 3.0)
      expect(stdRes.exercises[3].machine.id, 'mac14');
      expect(fullRes.exercises[3].machine.id, 'mac14');
      expect(
        stdRes.exercises[3].finalScore - fullRes.exercises[3].finalScore,
        closeTo(3.0, 1e-9),
      );
      // Pick #5 mac27 gets finisher +6.5 -> 29.6
      expect(fullRes.exercises[4].machine.id, 'mac27');
      expect(fullRes.exercises[4].finalScore, closeTo(29.6, 1e-9));
    });

    test('T1-F5-06: tie-breaker (idx + sessionCount * 7) % 29 rotates deterministically', () {
      final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = _historyWithOffsets(<String, int>{
        'mac5': 0,
        'mac20': 0,
      });

      final resS1 = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );
      expect(resS1.exercises.first.machine.id, 'mac4');
      expect(resS1.exercises.first.finalScore, closeTo(28.4, 1e-9));

      // sessionCount <= 0 coerces to 1 -> identical tie-break to sessionCount = 1
      final resS0 = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 0,
      );
      expect(resS0.exercises.first.machine.id, 'mac4');

      // sessionCount = 8 -> mac2 ((1+56)%29 = 28) beats mac4 ((3+56)%29 = 1)
      final resS8 = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 8,
      );
      expect(resS8.exercises.first.machine.id, 'mac2');
      expect(resS8.exercises.first.finalScore, closeTo(28.4, 1e-9));
    });
  });

  // ===========================================================================
  // F6: Step 5 Load Prescription & advanceSessionDay (T1-F6-01 .. T1-F6-06)
  // ===========================================================================
  group('F6: Step 5 Load Prescription & advanceSessionDay', () {
    test('T1-F6-01: first-time weight uses bw * bwFactor * gender * exp * age', () {
      // S5-01: mac1, male 1996 beginner 65kg normal -> 82.5kg, 10r, 3s
      final resS501 = generator.generateMenu(
        profile: buildTestProfile(
          gender: Gender.male,
          birthYear: 1996,
          experience: ExperienceLevel.beginner,
          bodyWeightKg: 65.0,
          isFirstTime: true,
        ),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac1']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS501.exercises.first.machine.id, 'mac1');
      expect(resS501.exercises.first.weightKg, 82.5);
      expect(resS501.exercises.first.reps, 10);
      expect(resS501.exercises.first.sets, 3);

      // S5-02: mac1, female 2007 (under_20) beginner 40kg -> 30.0kg
      final resS502 = generator.generateMenu(
        profile: buildTestProfile(
          gender: Gender.female,
          birthYear: 2007,
          experience: ExperienceLevel.beginner,
          bodyWeightKg: 40.0,
          purpose: TrainingPurpose.bodyMakeMale,
          isFirstTime: true,
        ),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac1']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS502.exercises.first.weightKg, 30.0);
      expect(resS502.exercises.first.reps, 10);
      expect(resS502.exercises.first.sets, 3);

      // S5-03: mac1, male 1980 (40s) intermediate 80kg -> 112.5kg
      final resS503 = generator.generateMenu(
        profile: buildTestProfile(
          gender: Gender.male,
          birthYear: 1980,
          experience: ExperienceLevel.intermediate,
          bodyWeightKg: 80.0,
          isFirstTime: true,
        ),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac1']),
        ),
        machineHistory: _historyWithOffsets(<String, int>{
          'mac2': 0,
          'mac4': 0,
          'mac6': 0,
        }),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS503.exercises.first.weightKg, 112.5);
      expect(resS503.exercises.first.reps, 10);
      expect(resS503.exercises.first.sets, 3);

      // S5-04: mac5, male 1970 (50s) beginner 65kg -> 35.0kg, 12r
      final resS504 = generator.generateMenu(
        profile: buildTestProfile(
          gender: Gender.male,
          birthYear: 1970,
          experience: ExperienceLevel.beginner,
          bodyWeightKg: 65.0,
          isFirstTime: true,
        ),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac5']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS504.exercises.first.weightKg, 35.0);
      expect(resS504.exercises.first.reps, 12);
      expect(resS504.exercises.first.sets, 3);

      // S5-05: mac5, female 1966 (60_plus) beginner 40kg -> 10.0kg, 15r
      final resS505 = generator.generateMenu(
        profile: buildTestProfile(
          gender: Gender.female,
          birthYear: 1966,
          experience: ExperienceLevel.beginner,
          bodyWeightKg: 40.0,
          purpose: TrainingPurpose.bodyMakeMale,
          isFirstTime: true,
        ),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac5']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS505.exercises.first.weightKg, 10.0);
      expect(resS505.exercises.first.reps, 15);
      expect(resS505.exercises.first.sets, 3);

      // S5-06: mac23, female 1966 10kg tired -> 2.5kg floor, 15r, 2s
      final resS506 = generator.generateMenu(
        profile: buildTestProfile(
          gender: Gender.female,
          birthYear: 1966,
          experience: ExperienceLevel.beginner,
          bodyWeightKg: 10.0,
          purpose: TrainingPurpose.bodyMakeMale,
          isFirstTime: true,
        ),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac23']),
        ),
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        now: kClockEvening1800,
      );
      expect(resS506.exercises.first.weightKg, 2.5);
      expect(resS506.exercises.first.reps, 15);
      expect(resS506.exercises.first.sets, 2);
    });

    test('T1-F6-02: birthYear maps to all 5 age brackets, 60+ x0.90, and rep shifts', () {
      const bracketCases = <({int birthYear, double weightKg, int reps})>[
        (birthYear: 2007, weightKg: 77.5, reps: 10), // 19 -> under_20 (0.95)
        (birthYear: 2006, weightKg: 82.5, reps: 10), // 20 -> 20_30 (1.00)
        (birthYear: 1987, weightKg: 82.5, reps: 10), // 39 -> 20_30 (1.00)
        (birthYear: 1986, weightKg: 72.5, reps: 10), // 40 -> 40s (0.90)
        (birthYear: 1977, weightKg: 72.5, reps: 10), // 49 -> 40s (0.90)
        (birthYear: 1976, weightKg: 65.0, reps: 12), // 50 -> 50s (0.80, 10->12)
        (birthYear: 1967, weightKg: 65.0, reps: 12), // 59 -> 50s (0.80, 10->12)
        (birthYear: 1966, weightKg: 52.5, reps: 12), // 60 -> 60_plus (0.65, 10->12)
      ];
      final mac1States = _isolateMuscles(
        purpose: TrainingPurpose.bodyMakeMale,
        activeMuscleIds: _musclesForMachines(<String>['mac1']),
      );
      final mac1History = _historyWithOffsets(<String, int>{
        'mac2': 0,
        'mac4': 0,
        'mac6': 0,
      });

      for (final c in bracketCases) {
        final res = generator.generateMenu(
          profile: buildTestProfile(
            birthYear: c.birthYear,
            isFirstTime: true,
          ),
          muscleStates: mac1States,
          machineHistory: mac1History,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockEvening1800,
        );
        expect(res.exercises.first.weightKg, c.weightKg);
        expect(res.exercises.first.reps, c.reps);
      }

      // S5-13 (returning 50s): 85.0kg, 10->12 reps
      final resS513 = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1970, isFirstTime: false),
        muscleStates: mac1States,
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac1': const MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 4,
              lastWeightKg: 85.0,
              lastFeedback: WorkoutFeedback.justRight,
            ),
            'mac2': const MachineHistoryEntry(machineId: 'mac2', sessionsSinceUsed: 0),
            'mac4': const MachineHistoryEntry(machineId: 'mac4', sessionsSinceUsed: 0),
            'mac6': const MachineHistoryEntry(machineId: 'mac6', sessionsSinceUsed: 0),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS513.exercises.first.weightKg, 85.0);
      expect(resS513.exercises.first.reps, 12);

      // S5-14 (returning 60_plus): roundTo25(85.0 * 0.90 = 76.5) = 77.5kg, 10->12 reps
      final resS514 = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1966, isFirstTime: false),
        muscleStates: mac1States,
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac1': const MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 4,
              lastWeightKg: 85.0,
              lastFeedback: WorkoutFeedback.justRight,
            ),
            'mac2': const MachineHistoryEntry(machineId: 'mac2', sessionsSinceUsed: 0),
            'mac4': const MachineHistoryEntry(machineId: 'mac4', sessionsSinceUsed: 0),
            'mac6': const MachineHistoryEntry(machineId: 'mac6', sessionsSinceUsed: 0),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS514.exercises.first.weightKg, 77.5);
      expect(resS514.exercises.first.reps, 12);

      // S5-17 (returning 60_plus, baseReps=15, 60.0 + 2.5 -> 62.5 * 0.90 = 56.25 -> 57.5, 15r)
      final resS517 = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1966, isFirstTime: false),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac10']),
        ),
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac10': const MachineHistoryEntry(
              machineId: 'mac10',
              sessionsSinceUsed: 7,
              lastWeightKg: 60.0,
              lastFeedback: WorkoutFeedback.tooLight,
            ),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS517.exercises.first.machine.id, 'mac10');
      expect(resS517.exercises.first.weightKg, 57.5);
      expect(resS517.exercises.first.reps, 15);
    });

    test('T1-F6-03: great/normal use 3 sets; tired applies x0.95 weight and 2 sets', () {
      final mac1States = _isolateMuscles(
        purpose: TrainingPurpose.bodyMakeMale,
        activeMuscleIds: _musclesForMachines(<String>['mac1']),
      );
      final mac1Hist = buildDefaultMachineHistory(
        overrides: <String, MachineHistoryEntry>{
          'mac1': const MachineHistoryEntry(
            machineId: 'mac1',
            sessionsSinceUsed: 4,
            lastWeightKg: 85.0,
            lastFeedback: WorkoutFeedback.justRight,
          ),
          'mac2': const MachineHistoryEntry(machineId: 'mac2', sessionsSinceUsed: 0),
          'mac4': const MachineHistoryEntry(machineId: 'mac4', sessionsSinceUsed: 0),
          'mac6': const MachineHistoryEntry(machineId: 'mac6', sessionsSinceUsed: 0),
        },
      );

      // S5-07: great -> 85.0kg, 3 sets
      final resGreat = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996, isFirstTime: false),
        muscleStates: mac1States,
        machineHistory: mac1Hist,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.great,
        now: kClockEvening1800,
      );
      expect(resGreat.exercises.first.weightKg, 85.0);
      expect(resGreat.exercises.first.sets, 3);

      // S5-11: tired -> roundTo25(85.0 * 0.95 = 80.75) = 80.0kg, 2 sets
      final resTired = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996, isFirstTime: false),
        muscleStates: mac1States,
        machineHistory: mac1Hist,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        now: kClockEvening1800,
      );
      expect(resTired.exercises.first.weightKg, 80.0);
      expect(resTired.exercises.first.sets, 2);

      // S5-12: mac23 tired (20.0 * 0.95 = 19.0 -> 20.0kg, 2 sets)
      final resMac23Tired = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996, isFirstTime: false),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac23']),
        ),
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac23': const MachineHistoryEntry(
              machineId: 'mac23',
              sessionsSinceUsed: 6,
              lastWeightKg: 20.0,
              lastFeedback: WorkoutFeedback.justRight,
            ),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        now: kClockEvening1800,
      );
      expect(resMac23Tired.exercises.first.weightKg, 20.0);
      expect(resMac23Tired.exercises.first.sets, 2);

      // S5-15: 60_plus tired (roundTo25(85*0.9)=77.5, roundTo25(77.5*0.95=73.625)=72.5kg, 2 sets)
      final res60Tired = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1966, isFirstTime: false),
        muscleStates: mac1States,
        machineHistory: mac1Hist,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        now: kClockEvening1800,
      );
      expect(res60Tired.exercises.first.weightKg, 72.5);
      expect(res60Tired.exercises.first.reps, 12);
      expect(res60Tired.exercises.first.sets, 2);
    });

    test('T1-F6-04: returning feedback adjusts weight by +2.5 / 0.0 / -2.5 kg', () {
      final mac1States = _isolateMuscles(
        purpose: TrainingPurpose.bodyMakeMale,
        activeMuscleIds: _musclesForMachines(<String>['mac1']),
      );

      // S5-08: tooLight -> 85.0 + 2.5 = 87.5kg
      final resLight = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996, isFirstTime: false),
        muscleStates: mac1States,
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac1': const MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 4,
              lastWeightKg: 85.0,
              lastFeedback: WorkoutFeedback.tooLight,
            ),
            'mac2': const MachineHistoryEntry(machineId: 'mac2', sessionsSinceUsed: 0),
            'mac4': const MachineHistoryEntry(machineId: 'mac4', sessionsSinceUsed: 0),
            'mac6': const MachineHistoryEntry(machineId: 'mac6', sessionsSinceUsed: 0),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resLight.exercises.first.weightKg, 87.5);

      // S5-09: tooHard -> 85.0 - 2.5 = 82.5kg
      final resHard = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996, isFirstTime: false),
        muscleStates: mac1States,
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac1': const MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 4,
              lastWeightKg: 85.0,
              lastFeedback: WorkoutFeedback.tooHard,
            ),
            'mac2': const MachineHistoryEntry(machineId: 'mac2', sessionsSinceUsed: 0),
            'mac4': const MachineHistoryEntry(machineId: 'mac4', sessionsSinceUsed: 0),
            'mac6': const MachineHistoryEntry(machineId: 'mac6', sessionsSinceUsed: 0),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resHard.exercises.first.weightKg, 82.5);

      // S5-10: mac23 at 2.5 / tooHard / tired -> 2.5kg floor
      final resFloor = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996, isFirstTime: false),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac23']),
        ),
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac23': const MachineHistoryEntry(
              machineId: 'mac23',
              sessionsSinceUsed: 6,
              lastWeightKg: 2.5,
              lastFeedback: WorkoutFeedback.tooHard,
            ),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        now: kClockEvening1800,
      );
      expect(resFloor.exercises.first.weightKg, 2.5);
      expect(resFloor.exercises.first.sets, 2);

      // S5-16: mac5 45.0 / tooHard / 60_plus -> (45-2.5)=42.5 * 0.90 = 38.25 -> 37.5, 15r
      final resS516 = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1966, isFirstTime: false),
        muscleStates: _isolateMuscles(
          purpose: TrainingPurpose.bodyMakeMale,
          activeMuscleIds: _musclesForMachines(<String>['mac5']),
        ),
        machineHistory: buildDefaultMachineHistory(
          overrides: <String, MachineHistoryEntry>{
            'mac5': const MachineHistoryEntry(
              machineId: 'mac5',
              sessionsSinceUsed: 9,
              lastWeightKg: 45.0,
              lastFeedback: WorkoutFeedback.tooHard,
            ),
          },
        ),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
      );
      expect(resS516.exercises.first.weightKg, 37.5);
      expect(resS516.exercises.first.reps, 15);
      expect(resS516.exercises.first.sets, 3);
    });

    test('T1-F6-05: advanceSessionDay applies 0.92^days decay and B_i/S_i updates', () {
      final initialStates = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final initialHistory = buildDefaultMachineHistory();
      final menu = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996),
        muscleStates: initialStates,
        machineHistory: initialHistory,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );
      expect(
        menu.exercises.map((e) => e.machine.id).toList(),
        equals(<String>['mac20', 'mac5', 'mac23', 'mac14']),
      );

      // daysElapsed = 1
      final adv1 = generator.advanceSessionDay(
        muscleStates: initialStates,
        machineHistory: initialHistory,
        completedExercises: menu.exercises,
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 1,
        daysElapsed: 1,
      );
      // Primary: B = 1, S = round1(2.0 * 0.92 + 1.5) = 3.3
      expect(adv1.muscleStates['m4']!.blankDays, 1);
      expect(adv1.muscleStates['m4']!.stimulationDays, 3.3);
      expect(adv1.muscleStates['m0']!.blankDays, 1);
      expect(adv1.muscleStates['m0']!.stimulationDays, 3.3);
      // Synergist-only: B = 5, S = round1(2.0 * 0.92 + 0.3) = 2.1
      expect(adv1.muscleStates['m11']!.blankDays, 5);
      expect(adv1.muscleStates['m11']!.stimulationDays, 2.1);
      expect(adv1.muscleStates['m18']!.blankDays, 5);
      expect(adv1.muscleStates['m18']!.stimulationDays, 2.1);
      // Unused: B = 5, S = round1(2.0 * 0.92) = 1.8
      expect(adv1.muscleStates['m2']!.blankDays, 5);
      expect(adv1.muscleStates['m2']!.stimulationDays, 1.8);
      expect(adv1.muscleStates['m15']!.blankDays, 5);
      expect(adv1.muscleStates['m15']!.stimulationDays, 1.8);

      // daysElapsed = 3
      final adv3 = generator.advanceSessionDay(
        muscleStates: initialStates,
        machineHistory: initialHistory,
        completedExercises: menu.exercises,
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 1,
        daysElapsed: 3,
      );
      // Primary: B = 3, S = round1(2.0 * 0.92^3 + 1.5) = 3.1
      expect(adv3.muscleStates['m4']!.blankDays, 3);
      expect(adv3.muscleStates['m4']!.stimulationDays, 3.1);
      expect(adv3.muscleStates['m0']!.blankDays, 3);
      expect(adv3.muscleStates['m0']!.stimulationDays, 3.1);
      // Synergist-only: B = 7, S = round1(2.0 * 0.92^3 + 0.3) = 1.9
      expect(adv3.muscleStates['m11']!.blankDays, 7);
      expect(adv3.muscleStates['m11']!.stimulationDays, 1.9);
      expect(adv3.muscleStates['m18']!.blankDays, 7);
      expect(adv3.muscleStates['m18']!.stimulationDays, 1.9);
      // Unused: B = 7, S = round1(2.0 * 0.92^3) = 1.6
      expect(adv3.muscleStates['m2']!.blankDays, 7);
      expect(adv3.muscleStates['m2']!.stimulationDays, 1.6);
      expect(adv3.muscleStates['m15']!.blankDays, 7);
      expect(adv3.muscleStates['m15']!.stimulationDays, 1.6);
    });

    test('T1-F6-06: advanceSessionDay resets picked machineHistory=0, unpicked +1, sessionCount +1', () {
      final initialStates = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final initialHistory = buildDefaultMachineHistory();
      final menu = generator.generateMenu(
        profile: buildTestProfile(birthYear: 1996),
        muscleStates: initialStates,
        machineHistory: initialHistory,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockEvening1800,
        sessionCount: 1,
      );

      final adv = generator.advanceSessionDay(
        muscleStates: initialStates,
        machineHistory: initialHistory,
        completedExercises: menu.exercises,
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 1,
        daysElapsed: 1,
      );

      const pickedIds = <String>{'mac20', 'mac5', 'mac23', 'mac14'};
      expect(adv.sessionCount, 2);
      expect(adv.machineHistory, hasLength(29));

      for (final spec in kExpectedMachineSpecs) {
        final updated = adv.machineHistory[spec.id]!;
        if (pickedIds.contains(spec.id)) {
          expect(updated.sessionsSinceUsed, 0);
        } else {
          expect(
            updated.sessionsSinceUsed,
            initialHistory[spec.id]!.sessionsSinceUsed + 1,
          );
        }
      }
    });
  });
}
