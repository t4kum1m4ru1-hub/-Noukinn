import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/engine/workout_menu_generator.dart';
import 'package:noukin/models/models.dart';

import 'e2e_test_helpers.dart';

/// Builds a [MuscleInputState] map where all muscles EXCEPT those required
/// (primary + synergist) by [machineIds] are marked injured.
Map<String, MuscleInputState> _isolateMusclesFor(
  List<String> machineIds, {
  TrainingPurpose purpose = TrainingPurpose.bodyMakeMale,
  int blankDays = 4,
  double stimulationDays = 2.0,
  Map<String, MuscleInputState> overrides = const <String, MuscleInputState>{},
}) {
  final allowed = <String>{};
  for (final id in machineIds) {
    final spec = kExpectedMachineSpecById[id]!;
    allowed.addAll(spec.primaryMuscleIds);
    allowed.addAll(spec.synergistMuscleIds);
  }
  final allIds = <String>{for (final m in kExpectedMuscleSpecs) m.id};
  final injuredIds = allIds.difference(allowed);
  return buildDefaultMuscleStates(
    purpose,
    injuredIds: injuredIds,
    blankDays: blankDays,
    stimulationDays: stimulationDays,
    overrides: overrides,
  );
}

void main() {
  const generator = WorkoutMenuGenerator();

  // ===========================================================================
  // F1: Lossless Master Data & Model Boundaries (T2-F1-01 .. T2-F1-06)
  // ===========================================================================
  group('Tier 2 F1: Master Data & Model Boundaries', () {
    test(
      'T2-F1-01: no muscle has recoveryDays <= 1 or > 3 and no machine has empty muscle lists',
      () {
        expect(MasterData.muscles.length, 54);
        for (final muscle in MasterData.muscles) {
          expect(
            muscle.recoveryDays,
            inInclusiveRange(2, 3),
            reason:
                'Muscle ${muscle.id} (${muscle.name}) recoveryDays must be 2 or 3',
          );
        }

        expect(MasterData.machines.length, 29);
        for (final machine in MasterData.machines) {
          expect(
            machine.primaryMuscleIds,
            isNotEmpty,
            reason: 'Machine ${machine.id} must have >= 1 primary muscle',
          );
          expect(
            machine.synergistMuscleIds,
            isNotEmpty,
            reason: 'Machine ${machine.id} must have >= 1 synergist muscle',
          );
          expect(machine.baseWeight, greaterThan(0));
          expect(machine.bwFactor, greaterThan(0));
          expect(machine.baseReps, greaterThanOrEqualTo(10));
        }
      },
    );

    test(
      'T2-F1-02: mac7 TFL (m27) has P_i = 0 across all 6 purposes without deadlocking mac7',
      () {
        for (final purpose in TrainingPurpose.values) {
          final priorities = MasterData.purposePriorities[purpose]!;
          expect(
            priorities['m27'],
            0,
            reason: 'm27 must have P_i = 0 under ${purpose.name}',
          );

          final result = generator.generateMenu(
            profile: buildTestProfile(purpose: purpose),
            muscleStates: _isolateMusclesFor(<String>['mac7'], purpose: purpose),
            machineHistory: buildDefaultMachineHistory(),
            course: WorkoutDurationCourse.short20,
            condition: WorkoutCondition.normal,
            now: kClockDaytime1300,
          );

          expect(
            result.exercises,
            hasLength(1),
            reason: 'mac7 must remain eligible under ${purpose.name}',
          );
          expect(result.exercises.first.machine.id, 'mac7');
          expect(result.exercises.first.finalScore, greaterThan(0.0));
        }
      },
    );

    test(
      'T2-F1-03: zero primary/synergist self-overlap or duplicate IDs within any of the 29 machines',
      () {
        for (final machine in MasterData.machines) {
          final primarySet = machine.primaryMuscleIds.toSet();
          final synergistSet = machine.synergistMuscleIds.toSet();

          expect(
            primarySet.length,
            machine.primaryMuscleIds.length,
            reason: 'Duplicate primary muscle IDs in ${machine.id}',
          );
          expect(
            synergistSet.length,
            machine.synergistMuscleIds.length,
            reason: 'Duplicate synergist muscle IDs in ${machine.id}',
          );
          expect(
            primarySet.intersection(synergistSet),
            isEmpty,
            reason: 'Primary/synergist self-overlap in ${machine.id}',
          );

          for (final muscleId in primarySet.union(synergistSet)) {
            expect(
              MasterData.muscleById.containsKey(muscleId),
              isTrue,
              reason: 'Unresolved muscleId $muscleId in ${machine.id}',
            );
          }
        }
      },
    );

    test(
      'T2-F1-04: default MuscleInputState (B=4, S=2) produces valid non-negative scores across all 6 purposes',
      () {
        for (final purpose in TrainingPurpose.values) {
          final states = MasterData.defaultMuscleStates(purpose);
          expect(states.length, 54);
          for (final entry in states.entries) {
            expect(entry.value.blankDays, 4);
            expect(entry.value.stimulationDays, 2.0);
            expect(entry.value.isInjured, isFalse);
            expect(
              entry.value.priorityP,
              kExpectedPurposePriorities[purpose]![entry.key],
            );
          }

          final profile = buildTestProfile(purpose: purpose);
          final scores = generator.computeMuscleScores(
            muscleStates: states,
            profile: profile,
            now: kClockDaytime1300,
          );
          expect(scores.length, 54);
          for (final info in scores.values) {
            expect(info.mVal.isNaN, isFalse);
            expect(info.synMVal.isNaN, isFalse);
            expect(info.mVal, greaterThanOrEqualTo(0.0));
            expect(info.synMVal, greaterThanOrEqualTo(0.0));
          }

          final menu = generator.generateMenu(
            profile: profile,
            muscleStates: states,
            machineHistory: MasterData.defaultMachineHistory(),
            course: WorkoutDurationCourse.full60,
            condition: WorkoutCondition.normal,
            now: kClockEvening1800,
          );
          expect(menu.exercises, hasLength(5));
          for (final ex in menu.exercises) {
            expect(ex.finalScore, greaterThan(0.0));
            expect(ex.rawScore, greaterThan(0.0));
          }
        }
      },
    );

    test(
      'T2-F1-05: priorityP normalization boundaries (0->0, 1->10, 11->10, 12->14, 15->14, 16->18, 18->18, -5->10)',
      () {
        final cases =
            <({int inputP, int expectedP, double expectedM, MuscleScoreStatus status})>[
          (
            inputP: 0,
            expectedP: 0,
            expectedM: 0.0,
            status: MuscleScoreStatus.untargeted,
          ),
          (
            inputP: 1,
            expectedP: 10,
            expectedM: 11.0,
            status: MuscleScoreStatus.active,
          ),
          (
            inputP: 11,
            expectedP: 10,
            expectedM: 11.0,
            status: MuscleScoreStatus.active,
          ),
          (
            inputP: 12,
            expectedP: 14,
            expectedM: 15.0,
            status: MuscleScoreStatus.active,
          ),
          (
            inputP: 15,
            expectedP: 14,
            expectedM: 15.0,
            status: MuscleScoreStatus.active,
          ),
          (
            inputP: 16,
            expectedP: 18,
            expectedM: 19.0,
            status: MuscleScoreStatus.active,
          ),
          (
            inputP: 18,
            expectedP: 18,
            expectedM: 19.0,
            status: MuscleScoreStatus.active,
          ),
          (
            inputP: -5,
            expectedP: 10,
            expectedM: 11.0,
            status: MuscleScoreStatus.active,
          ),
        ];

        final profile = buildTestProfile(birthYear: 1995);
        for (final c in cases) {
          final states = buildDefaultMuscleStates(
            TrainingPurpose.bodyMakeMale,
            overrides: <String, MuscleInputState>{
              'm0': MuscleInputState(
                muscleId: 'm0',
                blankDays: 6,
                stimulationDays: 2.0,
                priorityP: c.inputP,
              ),
            },
          );

          final scores = generator.computeMuscleScores(
            muscleStates: states,
            profile: profile,
            now: kClockDaytime1300,
          );
          final info = scores['m0']!;
          expect(
            info.priorityP,
            c.expectedP,
            reason: 'priorityP=${c.inputP} should normalize to ${c.expectedP}',
          );
          expect(
            info.mVal,
            closeTo(c.expectedM, 1e-9),
            reason: 'mVal for priorityP=${c.inputP}',
          );
          expect(info.status, c.status);
          if (c.inputP == 0) {
            expect(info.synMVal, closeTo(7.0, 1e-9)); // 6 + 6 - 3 - 2 = 7.0
          }
        }
      },
    );

    test(
      'T2-F1-06: JSON toJson/fromJson lossless round-trips on domain models',
      () {
        const profileWithEmail = UserProfile(
          id: 'uid_123',
          gender: Gender.female,
          birthYear: 1966,
          experience: ExperienceLevel.intermediate,
          bodyWeightKg: 54.5,
          purpose: TrainingPurpose.windsurfing,
          isFirstTime: false,
          email: 'athlete@example.com',
        );
        expect(
          UserProfile.fromJson(profileWithEmail.toJson()),
          profileWithEmail,
        );

        const profileNoEmail = UserProfile(
          id: 'local_user',
          gender: Gender.male,
          birthYear: 2007,
          experience: ExperienceLevel.beginner,
          bodyWeightKg: 68.0,
          purpose: TrainingPurpose.tennis,
          isFirstTime: true,
        );
        expect(UserProfile.fromJson(profileNoEmail.toJson()), profileNoEmail);

        const muscleState = MuscleInputState(
          muscleId: 'm29',
          blankDays: 14,
          stimulationDays: 3.7,
          priorityP: 18,
          isInjured: true,
        );
        expect(MuscleInputState.fromJson(muscleState.toJson()), muscleState);

        const histPopulated = MachineHistoryEntry(
          machineId: 'mac14',
          sessionsSinceUsed: 11,
          lastWeightKg: 42.5,
          lastFeedback: WorkoutFeedback.tooHard,
        );
        expect(
          MachineHistoryEntry.fromJson(histPopulated.toJson()),
          histPopulated,
        );

        const histMinimal = MachineHistoryEntry(
          machineId: 'mac1',
          sessionsSinceUsed: 0,
        );
        expect(MachineHistoryEntry.fromJson(histMinimal.toJson()), histMinimal);

        final session = WorkoutSessionRecord(
          id: 'sess-001',
          completedAt: DateTime.utc(2026, 11, 19, 13, 30, 0),
          durationCourse: WorkoutDurationCourse.standard45,
          condition: WorkoutCondition.tired,
          timeSlot: TimeSlot.daytime,
          focusMuscleId: 'm34',
          exercises: const <CompletedExerciseRecord>[
            CompletedExerciseRecord(
              machineId: 'mac20',
              machineName: 'チェストサポート式Tバーロウ',
              weightKg: 37.5,
              reps: 10,
              sets: 2,
            ),
            CompletedExerciseRecord(
              machineId: 'mac5',
              machineName: 'レッグエクステンション',
              weightKg: 42.5,
              reps: 12,
              sets: 2,
            ),
          ],
          feedback: WorkoutFeedback.tooLight,
          createdAt: DateTime.utc(2026, 11, 19, 13, 31, 0),
        );
        expect(WorkoutSessionRecord.fromJson(session.toJson()), session);

        final sessionNullFocus = session.copyWith(clearFocusMuscleId: true);
        expect(
          WorkoutSessionRecord.fromJson(sessionNullFocus.toJson()),
          sessionNullFocus,
        );
      },
    );
  });

  // ===========================================================================
  // F2: Step 1 M-Value Engine & Guards Boundaries (T2-F2-01 .. T2-F2-06)
  // ===========================================================================
  group('Tier 2 F2: Step 1 M-Value Engine & Guards Boundaries', () {
    test(
      'T2-F2-01: boundary blankDays == effectiveR is active vs effectiveR - 1 is recovering',
      () {
        final profile = buildTestProfile(birthYear: 1996);
        final states = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: 2, // R=3 -> B < R
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm2': MuscleInputState(
              muscleId: 'm2',
              blankDays: 3, // R=3 -> B == R
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm7': MuscleInputState(
              muscleId: 'm7',
              blankDays: 1, // R=2 -> B < R
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm8': MuscleInputState(
              muscleId: 'm8',
              blankDays: 2, // R=2 -> B == R
              stimulationDays: 2.0,
              priorityP: 14,
            ),
          },
        );

        final scores = generator.computeMuscleScores(
          muscleStates: states,
          profile: profile,
          now: kClockDaytime1300,
        );

        expect(scores['m0']!.status, MuscleScoreStatus.recovering);
        expect(scores['m0']!.mVal, 0.0);
        expect(scores['m0']!.synMVal, 0.0);

        expect(scores['m2']!.status, MuscleScoreStatus.active);
        expect(scores['m2']!.mVal, closeTo(16.0, 1e-9)); // 3+18-3-2
        expect(scores['m2']!.synMVal, closeTo(16.0, 1e-9));

        expect(scores['m7']!.status, MuscleScoreStatus.recovering);
        expect(scores['m7']!.mVal, 0.0);
        expect(scores['m7']!.synMVal, 0.0);

        expect(scores['m8']!.status, MuscleScoreStatus.active);
        expect(scores['m8']!.mVal, closeTo(12.0, 1e-9)); // 2+14-2-2
        expect(scores['m8']!.synMVal, closeTo(12.0, 1e-9));
      },
    );

    test(
      'T2-F2-02: R+1 tipping point (B=2, baseR=2) flips active at age 30 to recovering at age 55 or tooHard',
      () {
        final states = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm34': MuscleInputState(
              muscleId: 'm34',
              blankDays: 2,
              stimulationDays: 2.0,
              priorityP: 14,
            ),
            'm7': MuscleInputState(
              muscleId: 'm7',
              blankDays: 2,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
          },
        );

        // Baseline: age 30, justRight -> both active (R=2)
        final youngNormal = generator.computeMuscleScores(
          muscleStates: states,
          profile: buildTestProfile(birthYear: 1996),
          lastFeedback: WorkoutFeedback.justRight,
          now: kClockDaytime1300,
        );
        expect(youngNormal['m34']!.effectiveRecoveryDays, 2);
        expect(youngNormal['m34']!.status, MuscleScoreStatus.active);
        expect(youngNormal['m34']!.mVal, closeTo(12.0, 1e-9));
        expect(youngNormal['m7']!.status, MuscleScoreStatus.active);

        // Tipping point 1: age 55 -> R+1 on ALL 54 muscles -> both recovering
        final age55 = generator.computeMuscleScores(
          muscleStates: states,
          profile: buildTestProfile(birthYear: 1971),
          lastFeedback: WorkoutFeedback.justRight,
          now: kClockDaytime1300,
        );
        expect(age55['m34']!.effectiveRecoveryDays, 3);
        expect(age55['m34']!.status, MuscleScoreStatus.recovering);
        expect(age55['m34']!.mVal, 0.0);
        expect(age55['m34']!.synMVal, 0.0);
        expect(age55['m7']!.effectiveRecoveryDays, 3);
        expect(age55['m7']!.status, MuscleScoreStatus.recovering);

        // Tipping point 2: age 30 + tooHard -> R+1 ONLY on HIGH_VOLUME_EXTEND_MUSCLES
        final youngTooHard = generator.computeMuscleScores(
          muscleStates: states,
          profile: buildTestProfile(birthYear: 1996),
          lastFeedback: WorkoutFeedback.tooHard,
          now: kClockDaytime1300,
        );
        expect(youngTooHard['m34']!.effectiveRecoveryDays, 3);
        expect(youngTooHard['m34']!.status, MuscleScoreStatus.recovering);
        expect(youngTooHard['m34']!.mVal, 0.0);
        expect(youngTooHard['m34']!.synMVal, 0.0);
        expect(youngTooHard['m7']!.effectiveRecoveryDays, 2);
        expect(youngTooHard['m7']!.status, MuscleScoreStatus.active);
      },
    );

    test(
      'T2-F2-03: high S_i causing negative difference clamps mVal and synMVal to 0.0 while remaining active',
      () {
        final states = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm29': MuscleInputState(
              muscleId: 'm29',
              blankDays: 4,
              stimulationDays: 30.0,
              priorityP: 18,
            ),
            'm34': MuscleInputState(
              muscleId: 'm34',
              blankDays: 14,
              stimulationDays: 30.0,
              priorityP: 14,
            ),
          },
        );

        final scores = generator.computeMuscleScores(
          muscleStates: states,
          profile: buildTestProfile(birthYear: 1996),
          now: kClockDaytime1300,
        );

        expect(scores['m29']!.status, MuscleScoreStatus.active);
        expect(scores['m29']!.mVal, 0.0);
        expect(scores['m29']!.synMVal, 0.0);

        expect(scores['m34']!.status, MuscleScoreStatus.active);
        expect(scores['m34']!.mVal, 0.0);
        expect(scores['m34']!.synMVal, 0.0);
      },
    );

    test(
      'T2-F2-04: negative blankDays or stimulationDays clamps safely without throwing or NaN',
      () {
        final states = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: -5,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm2': MuscleInputState(
              muscleId: 'm2',
              blankDays: 4,
              stimulationDays: -2.0,
              priorityP: 18,
            ),
          },
        );

        final scores = generator.computeMuscleScores(
          muscleStates: states,
          profile: buildTestProfile(birthYear: 1996),
          now: kClockDaytime1300,
        );

        final m0 = scores['m0']!;
        expect(m0.bRaw, 0);
        expect(m0.bCapped, 0);
        expect(m0.status, MuscleScoreStatus.recovering);
        expect(m0.mVal, 0.0);
        expect(m0.synMVal, 0.0);

        final m2 = scores['m2']!;
        expect(m2.stimulationDays, 0.0);
        expect(m2.mVal.isNaN, isFalse);
        expect(m2.status, MuscleScoreStatus.active);
        expect(m2.mVal, closeTo(19.0, 1e-9)); // 4 + 18 - 3 - 0 = 19.0
      },
    );

    test(
      'T2-F2-05: synMVal (P_syn=6) clamps/caps and generateMenu applies R+1 via highVolumeMode or machineHistory tooHard',
      () {
        final states = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm18': MuscleInputState(
              muscleId: 'm18',
              blankDays: 4,
              stimulationDays: 20.0,
              priorityP: 0,
            ),
            'm15': MuscleInputState(
              muscleId: 'm15',
              blankDays: 14,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
            'm24': MuscleInputState(
              muscleId: 'm24',
              blankDays: 25,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
            'm25': MuscleInputState(
              muscleId: 'm25',
              blankDays: 1,
              stimulationDays: 0.0,
              priorityP: 0,
            ),
          },
        );

        final scores = generator.computeMuscleScores(
          muscleStates: states,
          profile: buildTestProfile(birthYear: 1996),
          now: kClockDaytime1300,
        );

        expect(scores['m18']!.status, MuscleScoreStatus.untargeted);
        expect(scores['m18']!.mVal, 0.0);
        expect(scores['m18']!.synMVal, 0.0);

        expect(scores['m15']!.bCapped, 14);
        expect(scores['m15']!.mVal, 0.0);
        expect(scores['m15']!.synMVal, closeTo(16.0, 1e-9)); // 14+6-2-2

        expect(scores['m24']!.bCapped, 14);
        expect(scores['m24']!.mVal, 0.0);
        expect(scores['m24']!.synMVal, closeTo(16.0, 1e-9));

        expect(scores['m25']!.status, MuscleScoreStatus.untargeted);
        expect(scores['m25']!.mVal, 0.0);
        expect(scores['m25']!.synMVal, 0.0);

        // Full 54-muscle check at B_i = 2: all 9 kHighVolumeExtendMuscleIds
        // (R=2, P>=10 under bodyMakeMale) stay active under baseline, but flip
        // to R=3 / mVal=0.0 / recovering when generateMenu receives
        // highVolumeMode: true or auto-detects tooHard from machineHistory.
        final youngProfile = buildTestProfile(
          birthYear: 1996,
          purpose: TrainingPurpose.bodyMakeMale,
        );
        final allB2States = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          blankDays: 2,
        );
        final neutralHist = buildDefaultMachineHistory();
        final tooHardHist = buildDefaultMachineHistory(
          overrides: const <String, MachineHistoryEntry>{
            'mac1': MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 4,
              lastFeedback: WorkoutFeedback.tooHard,
            ),
          },
        );

        final fullBaseline = generator.generateMenu(
          profile: youngProfile,
          muscleStates: allB2States,
          machineHistory: neutralHist,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          lastFeedback: null,
          highVolumeMode: false,
          now: kClockDaytime1300,
        );
        for (final id in kHighVolumeExtendMuscleIds) {
          final info = fullBaseline.muscleScores[id]!;
          expect(info.effectiveRecoveryDays, 2, reason: 'baseline R for $id');
          expect(info.status, MuscleScoreStatus.active);
          expect(info.mVal, greaterThan(0.0));
        }

        final fullHighVol = generator.generateMenu(
          profile: youngProfile,
          muscleStates: allB2States,
          machineHistory: neutralHist,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          lastFeedback: null,
          highVolumeMode: true,
          now: kClockDaytime1300,
        );
        for (final id in kHighVolumeExtendMuscleIds) {
          final info = fullHighVol.muscleScores[id]!;
          expect(info.effectiveRecoveryDays, 3, reason: 'highVol R+1 for $id');
          expect(info.status, MuscleScoreStatus.recovering);
          expect(info.mVal, 0.0);
          expect(info.synMVal, 0.0);
        }
        // Non-extend R=2 muscle remains active
        expect(fullHighVol.muscleScores['m7']!.effectiveRecoveryDays, 2);
        expect(fullHighVol.muscleScores['m7']!.status, MuscleScoreStatus.active);
        expect(fullHighVol.muscleScores['m7']!.mVal, closeTo(16.0, 1e-9));

        final fullAutoTooHard = generator.generateMenu(
          profile: youngProfile,
          muscleStates: allB2States,
          machineHistory: tooHardHist,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          lastFeedback: null,
          highVolumeMode: false,
          now: kClockDaytime1300,
        );
        for (final id in kHighVolumeExtendMuscleIds) {
          final info = fullAutoTooHard.muscleScores[id]!;
          expect(info.effectiveRecoveryDays, 3, reason: 'auto tooHard R+1 for $id');
          expect(info.status, MuscleScoreStatus.recovering);
          expect(info.mVal, 0.0);
          expect(info.synMVal, 0.0);
        }
        expect(fullAutoTooHard.muscleScores['m7']!.effectiveRecoveryDays, 2);
        expect(
          fullAutoTooHard.muscleScores['m7']!.status,
          MuscleScoreStatus.active,
        );
        expect(fullAutoTooHard.muscleScores['m7']!.mVal, closeTo(16.0, 1e-9));

        // Isolated menu-pick check: mac23 (primary m35, syn m41 in extend set;
        // m33/m37 recovering at B=1) vs mac27 (non-extend m7/m49/m50/m51).
        final isolatedB2 = _isolateMusclesFor(
          <String>['mac23', 'mac27'],
          blankDays: 2,
          overrides: const <String, MuscleInputState>{
            'm33': MuscleInputState(
              muscleId: 'm33',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 10,
            ),
            'm37': MuscleInputState(
              muscleId: 'm37',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
          },
        );

        final menuBaseline = generator.generateMenu(
          profile: youngProfile,
          muscleStates: isolatedB2,
          machineHistory: neutralHist,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          lastFeedback: null,
          highVolumeMode: false,
          now: kClockDaytime1300,
        );
        expect(
          menuBaseline.exercises.map((e) => e.machine.id).toSet(),
          equals(<String>{'mac23', 'mac27'}),
        );

        final menuHighVol = generator.generateMenu(
          profile: youngProfile,
          muscleStates: isolatedB2,
          machineHistory: neutralHist,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          lastFeedback: null,
          highVolumeMode: true,
          now: kClockDaytime1300,
        );
        expect(menuHighVol.muscleScores['m35']!.mVal, 0.0);
        expect(menuHighVol.muscleScores['m41']!.synMVal, 0.0);
        expect(
          menuHighVol.exercises.map((e) => e.machine.id).toList(),
          equals(<String>['mac27']),
        );

        final menuAutoTooHard = generator.generateMenu(
          profile: youngProfile,
          muscleStates: isolatedB2,
          machineHistory: tooHardHist,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          lastFeedback: null,
          highVolumeMode: false,
          now: kClockDaytime1300,
        );
        expect(menuAutoTooHard.muscleScores['m35']!.mVal, 0.0);
        expect(menuAutoTooHard.muscleScores['m41']!.synMVal, 0.0);
        expect(
          menuAutoTooHard.exercises.map((e) => e.machine.id).toList(),
          equals(<String>['mac27']),
        );
      },
    );

    test(
      'T2-F2-06: 1-decimal rounding stability on fractional S_i (2.3, 4.7, 2.14, 2.16)',
      () {
        final states = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: 4,
              stimulationDays: 2.3,
              priorityP: 18,
            ),
            'm1': MuscleInputState(
              muscleId: 'm1',
              blankDays: 5,
              stimulationDays: 4.7,
              priorityP: 18,
            ),
            'm18': MuscleInputState(
              muscleId: 'm18',
              blankDays: 5,
              stimulationDays: 2.3,
              priorityP: 0,
            ),
            'm2': MuscleInputState(
              muscleId: 'm2',
              blankDays: 4,
              stimulationDays: 2.14,
              priorityP: 18,
            ),
            'm3': MuscleInputState(
              muscleId: 'm3',
              blankDays: 4,
              stimulationDays: 2.16,
              priorityP: 18,
            ),
          },
        );

        final scores = generator.computeMuscleScores(
          muscleStates: states,
          profile: buildTestProfile(birthYear: 1996),
          now: kClockDaytime1300,
        );

        expect(scores['m0']!.mVal, 16.7);
        expect(scores['m1']!.mVal, 15.3);
        expect(scores['m18']!.synMVal, 6.7);
        expect(scores['m2']!.mVal, 16.9); // 4+18-3-2.1
        expect(scores['m3']!.mVal, 16.8); // 4+18-3-2.2
      },
    );
  });

  // ===========================================================================
  // F3: Step 2 Raw Score Boundaries (T2-F3-01 .. T2-F3-06)
  // ===========================================================================
  group('Tier 2 F3: Step 2 Raw Score Boundaries', () {
    test(
      'T2-F3-01: all primaries recovering (primaryMax=0, P>0) keeps synergistScore > 0 eligible with rot=0 and str=0',
      () {
        // S2-09: isolate mac5; m0 & m13 recovering (B=1 < R=3), m18 synMVal=6.0
        final states = _isolateMusclesFor(
          <String>['mac5'],
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm13': MuscleInputState(
              muscleId: 'm13',
              blankDays: 1,
              stimulationDays: 2.0,
              priorityP: 10,
            ),
            'm18': MuscleInputState(
              muscleId: 'm18',
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
          },
        );

        final result = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: states,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );

        expect(result.exercises, hasLength(1));
        final ex = result.exercises.first;
        expect(ex.machine.id, 'mac5');
        expect(ex.rawScore, closeTo(1.8, 1e-9)); // 6.0 * 0.3, rot=0, str=0
        expect(ex.finalScore, closeTo(1.8, 1e-9));
      },
    );

    test(
      'T2-F3-02: mac7 yields empty menu (finalScore=0) when all 4 primaries or any non-TFL primary has P=0',
      () {
        // Case A: all 4 primaries (m2, m5, m14, m27) have P=0
        final allZeroStates = _isolateMusclesFor(
          <String>['mac7'],
          overrides: const <String, MuscleInputState>{
            'm2': MuscleInputState(muscleId: 'm2', priorityP: 0),
            'm5': MuscleInputState(muscleId: 'm5', priorityP: 0),
            'm14': MuscleInputState(muscleId: 'm14', priorityP: 0),
            'm27': MuscleInputState(muscleId: 'm27', priorityP: 0),
          },
        );
        final resAllZero = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: allZeroStates,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );
        expect(resAllZero.exercises, isEmpty);

        // Case B: S2-07 non-TFL primary m2 has P=0 while m5/m14 have P>0 and m27 has P=0
        final nonTflZeroStates = _isolateMusclesFor(
          <String>['mac7'],
          overrides: const <String, MuscleInputState>{
            'm2': MuscleInputState(muscleId: 'm2', priorityP: 0),
          },
        );
        final resNonTfl = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: nonTflZeroStates,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );
        expect(resNonTfl.exercises, isEmpty);
      },
    );

    test(
      'T2-F3-03: mac7 with m27 explicitly injured is excluded (injury guard overrides TFL exception)',
      () {
        final states = _isolateMusclesFor(
          <String>['mac7'],
          overrides: const <String, MuscleInputState>{
            'm27': MuscleInputState(
              muscleId: 'm27',
              priorityP: 0,
              isInjured: true,
            ),
          },
        );

        final result = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: states,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );

        expect(result.exercises, isEmpty);
      },
    );

    test(
      'T2-F3-04: rotationBonus exact stage boundaries (n=0, 5, 6, 10, 11, 20 uncapped)',
      () {
        // Isolated mac6 at daytime/normal/step=0:
        // primary=17.0, syn=2.25 -> base = 19.25
        final expectedByN = <int, double>{
          0: 19.25 + 0.0 + 0.0, // rot=0.0, str=0.0
          5: 19.25 + 3.5 + 0.0, // rot=3.5, str=0.0
          6: 19.25 + 5.0 + 0.0, // rot=5.0, str=0.0
          10: 19.25 + 11.0 + 4.0, // rot=11.0, str=4.0
          11: 19.25 + 13.5 + 4.0, // rot=13.5, str=4.0
          20: 19.25 + 36.0 + 4.0, // rot=36.0 (11 + 10*2.5), str=4.0
        };

        final states = _isolateMusclesFor(<String>['mac6']);
        final profile = buildTestProfile();

        for (final entry in expectedByN.entries) {
          final result = generator.generateMenu(
            profile: profile,
            muscleStates: states,
            machineHistory: buildDefaultMachineHistory(
              overrides: <String, MachineHistoryEntry>{
                'mac6': MachineHistoryEntry(
                  machineId: 'mac6',
                  sessionsSinceUsed: entry.key,
                ),
              },
            ),
            course: WorkoutDurationCourse.short20,
            condition: WorkoutCondition.normal,
            now: kClockDaytime1300,
          );
          expect(result.exercises, hasLength(1));
          expect(
            result.exercises.first.rawScore,
            closeTo(entry.value, 1e-9),
            reason: 'mac6 rawScore mismatch at n=${entry.key}',
          );
        }
      },
    );

    test(
      'T2-F3-05: structureBonus thresholds (n=7 vs 8, n=9 vs 10, short20 denies +6.5 finisher)',
      () {
        final statesMac6 = _isolateMusclesFor(<String>['mac6']);
        final profile = buildTestProfile();

        double mac6RawAt(int n) {
          return generator
              .generateMenu(
                profile: profile,
                muscleStates: statesMac6,
                machineHistory: buildDefaultMachineHistory(
                  overrides: <String, MachineHistoryEntry>{
                    'mac6': MachineHistoryEntry(
                      machineId: 'mac6',
                      sessionsSinceUsed: n,
                    ),
                  },
                ),
                course: WorkoutDurationCourse.short20,
                condition: WorkoutCondition.normal,
                now: kClockDaytime1300,
              )
              .exercises
              .first
              .rawScore;
        }

        // n=7 (rot=6.5, str=0.0) -> 25.75 vs n=8 (rot=8.0, str=+3.0) -> 30.25
        expect(mac6RawAt(7), closeTo(25.75, 1e-9));
        expect(mac6RawAt(8), closeTo(30.25, 1e-9));
        // n=9 (rot=9.5, str=+3.0) -> 31.75 vs n=10 (rot=11.0, str=+4.0) -> 34.25
        expect(mac6RawAt(9), closeTo(31.75, 1e-9));
        expect(mac6RawAt(10), closeTo(34.25, 1e-9));

        // short20 (targetCount=2) stepIndex=1 must NOT award +6.5 finisher
        final twoMachineStates = _isolateMusclesFor(<String>['mac27', 'mac6']);
        final shortRes = generator.generateMenu(
          profile: profile,
          muscleStates: twoMachineStates,
          machineHistory: buildDefaultMachineHistory(
            overrides: <String, MachineHistoryEntry>{
              'mac27': const MachineHistoryEntry(
                machineId: 'mac27',
                sessionsSinceUsed: 15,
              ),
              'mac6': const MachineHistoryEntry(
                machineId: 'mac6',
                sessionsSinceUsed: 6,
              ),
            },
          ),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );
        expect(shortRes.exercises.map((e) => e.machine.id).toList(), <String>[
          'mac27',
          'mac6',
        ]);
        // At stepIndex=1 of short20: mac6 str=0.0 -> 17.0 + 2.25 + 5.0 = 24.25
        expect(shortRes.exercises[1].rawScore, closeTo(24.25, 1e-9));
      },
    );

    test(
      'T2-F3-06: missing machineHistory entries fall back cleanly without Null errors',
      () {
        final fullResult = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale),
          machineHistory: const <String, MachineHistoryEntry>{},
          course: WorkoutDurationCourse.standard45,
          condition: WorkoutCondition.normal,
          now: kClockEvening1800,
        );
        expect(fullResult.exercises, hasLength(4));

        // Isolate mac29 (defaultSessionsSinceUsed == 4) to check exact parity
        final mac29States = _isolateMusclesFor(<String>['mac29']);
        final missingRes = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: mac29States,
          machineHistory: const <String, MachineHistoryEntry>{},
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );
        final explicitRes = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: mac29States,
          machineHistory: const <String, MachineHistoryEntry>{
            'mac29': MachineHistoryEntry(
              machineId: 'mac29',
              sessionsSinceUsed: 4,
            ),
          },
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );

        expect(missingRes.exercises, hasLength(1));
        expect(
          missingRes.exercises.first.rawScore,
          closeTo(explicitRes.exercises.first.rawScore, 1e-9),
        );
        expect(
          missingRes.exercises.first.finalScore,
          closeTo(explicitRes.exercises.first.finalScore, 1e-9),
        );
      },
    );
  });

  // ===========================================================================
  // F4: Step 3 Time Slot & Multipliers Boundaries (T2-F4-01 .. T2-F4-06)
  // ===========================================================================
  group('Tier 2 F4: Step 3 Time Slot & Multipliers Boundaries', () {
    test(
      'T2-F4-01: resolveTimeSlot covers all exact minute boundaries across 24h',
      () {
        final cases = <(DateTime, TimeSlot)>[
          (kClockBoundary0000, TimeSlot.night),
          (kClockBoundary045959, TimeSlot.night),
          (kClockBoundary0500, TimeSlot.morning),
          (kClockBoundary115959, TimeSlot.morning),
          (kClockBoundary1200, TimeSlot.daytime),
          (kClockBoundary145959, TimeSlot.daytime),
          (kClockBoundary1500, TimeSlot.evening),
          (kClockBoundary205959, TimeSlot.evening),
          (kClockBoundary2100, TimeSlot.night),
          (kClockBoundary235959, TimeSlot.night),
        ];

        final states = _isolateMusclesFor(<String>['mac29']);
        final hist = buildDefaultMachineHistory();
        final profile = buildTestProfile();

        for (final (dt, expectedSlot) in cases) {
          expect(
            resolveTimeSlot(dt),
            expectedSlot,
            reason: 'resolveTimeSlot($dt) mismatch',
          );
          final res = generator.generateMenu(
            profile: profile,
            muscleStates: states,
            machineHistory: hist,
            course: WorkoutDurationCourse.short20,
            condition: WorkoutCondition.normal,
            now: dt,
          );
          expect(
            res.timeSlot,
            expectedSlot,
            reason: 'generateMenu(now: $dt).timeSlot mismatch',
          );
        }
      },
    );

    test(
      'T2-F4-02: m9 (脊柱起立筋群) dual boundary gives mac29 x1.25 in morning and x0.30 in night',
      () {
        final states = _isolateMusclesFor(<String>['mac29']);
        final hist = buildDefaultMachineHistory();
        final profile = buildTestProfile();

        final daytimeEx = generator
            .generateMenu(
              profile: profile,
              muscleStates: states,
              machineHistory: hist,
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockDaytime1300,
            )
            .exercises
            .first;
        expect(daytimeEx.rawScore, closeTo(20.9, 1e-9));
        expect(daytimeEx.finalScore, closeTo(20.9, 1e-9));

        final morningEx = generator
            .generateMenu(
              profile: profile,
              muscleStates: states,
              machineHistory: hist,
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockMorning0800,
            )
            .exercises
            .first;
        expect(morningEx.rawScore, closeTo(20.9, 1e-9));
        expect(morningEx.finalScore, closeTo(26.125, 1e-9)); // 20.9 * 1.25

        final nightEx = generator
            .generateMenu(
              profile: profile,
              muscleStates: states,
              machineHistory: hist,
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockNight2230,
            )
            .exercises
            .first;
        expect(nightEx.rawScore, closeTo(24.4, 1e-9)); // +3.5 iso at night
        expect(nightEx.finalScore, closeTo(7.32, 1e-9)); // 24.4 * 0.30
      },
    );

    test(
      'T2-F4-03: m29 & m30 receive x0.30 night penalty despite timeCat == other',
      () {
        expect(MasterData.muscleById['m29']!.timeCat, MuscleTimeCategory.other);
        expect(MasterData.muscleById['m30']!.timeCat, MuscleTimeCategory.other);
        expect(
          MasterData.nightAvoidMuscleIds,
          containsAll(<String>['m29', 'm30']),
        );

        final hist = buildDefaultMachineHistory();
        final profile = buildTestProfile();

        // S3-11: mac12 (primary m29)
        final mac12Night = generator
            .generateMenu(
              profile: profile,
              muscleStates: _isolateMusclesFor(<String>['mac12']),
              machineHistory: hist,
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockNight2230,
            )
            .exercises
            .first;
        expect(mac12Night.rawScore, closeTo(27.8, 1e-9));
        expect(mac12Night.finalScore, closeTo(8.34, 1e-9)); // 27.8 * 0.30

        // S3-13: mac13 (primary m30)
        final mac13Night = generator
            .generateMenu(
              profile: profile,
              muscleStates: _isolateMusclesFor(<String>['mac13']),
              machineHistory: hist,
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockNight2230,
            )
            .exercises
            .first;
        expect(mac13Night.rawScore, closeTo(21.65, 1e-9));
        expect(mac13Night.finalScore, closeTo(6.495, 1e-9)); // 21.65 * 0.30
      },
    );

    test(
      'T2-F4-04: synergist-only injury (m18) completely excludes mac5 despite max-M primaries',
      () {
        final maxPrimaryHealthy = _isolateMusclesFor(
          <String>['mac5'],
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: 14,
              stimulationDays: 0.0,
              priorityP: 18,
            ),
            'm13': MuscleInputState(
              muscleId: 'm13',
              blankDays: 14,
              stimulationDays: 0.0,
              priorityP: 10,
            ),
          },
        );
        final eligibleRes = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: maxPrimaryHealthy,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );
        expect(eligibleRes.exercises, hasLength(1));

        final synInjured = Map<String, MuscleInputState>.of(maxPrimaryHealthy)
          ..['m18'] = const MuscleInputState(
            muscleId: 'm18',
            priorityP: 0,
            isInjured: true,
          );
        final excludedRes = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: synInjured,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );
        expect(excludedRes.exercises, isEmpty);
      },
    );

    test(
      'T2-F4-05: invalid, empty, or null focusMuscleId applies neutral x1.0 without error',
      () {
        final states = _isolateMusclesFor(<String>['mac5']);
        final hist = buildDefaultMachineHistory();
        final profile = buildTestProfile();

        double scoreWithFocus(String? focusId) {
          return generator
              .generateMenu(
                profile: profile,
                muscleStates: states,
                machineHistory: hist,
                course: WorkoutDurationCourse.short20,
                condition: WorkoutCondition.normal,
                focusMuscleId: focusId,
                now: kClockDaytime1300,
              )
              .exercises
              .first
              .finalScore;
        }

        final nullScore = scoreWithFocus(null);
        expect(nullScore, closeTo(30.1, 1e-9));
        expect(scoreWithFocus(''), closeTo(nullScore, 1e-9));
        expect(scoreWithFocus('nonexistent_muscle_99'), closeTo(nullScore, 1e-9));
        expect(scoreWithFocus('m0'), closeTo(nullScore * 1.25, 1e-9));
      },
    );

    test(
      'T2-F4-06: daytime (12:00-14:59) applies neutral x1.0 across all 29 machines',
      () {
        final profile = buildTestProfile();
        for (final spec in kExpectedMachineSpecs) {
          final states = _isolateMusclesFor(<String>[spec.id]);
          final hist = buildDefaultMachineHistory(
            overrides: <String, MachineHistoryEntry>{
              spec.id: MachineHistoryEntry(
                machineId: spec.id,
                sessionsSinceUsed: 30, // Guarantees spec.id wins pick #1
              ),
            },
          );
          final res = generator.generateMenu(
            profile: profile,
            muscleStates: states,
            machineHistory: hist,
            course: WorkoutDurationCourse.short20,
            condition: WorkoutCondition.normal,
            now: kClockDaytime1300,
          );
          expect(res.timeSlot, TimeSlot.daytime);
          expect(res.exercises.first.machine.id, spec.id);
          expect(
            res.exercises.first.finalScore,
            closeTo(res.exercises.first.rawScore, 1e-9),
            reason: 'daytime must apply x1.0 multiplier to ${spec.id}',
          );
        }
      },
    );
  });

  // ===========================================================================
  // F5: Step 4 Dynamic Overlap Prevention & Constants (T2-F5-01 .. T2-F5-06)
  // ===========================================================================
  group('Tier 2 F5: Step 4 Dynamic Overlap & Boundary Cases', () {
    test(
      'T2-F5-01: all 54 muscles injured returns empty menu across all courses and slots',
      () {
        final allInjured = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          injuredIds: <String>{for (final m in kExpectedMuscleSpecs) m.id},
        );
        final profile = buildTestProfile();
        final hist = buildDefaultMachineHistory();

        for (final course in WorkoutDurationCourse.values) {
          for (final clock in <DateTime>[
            kClockMorning0800,
            kClockDaytime1300,
            kClockEvening1800,
            kClockNight2230,
          ]) {
            final res = generator.generateMenu(
              profile: profile,
              muscleStates: allInjured,
              machineHistory: hist,
              course: course,
              condition: WorkoutCondition.normal,
              now: clock,
            );
            expect(res.exercises, isEmpty);
            expect(res.muscleScores.length, 54);
            for (final info in res.muscleScores.values) {
              expect(info.status, MuscleScoreStatus.injured);
              expect(info.mVal, 0.0);
              expect(info.synMVal, 0.0);
            }
          }
        }
      },
    );

    test(
      'T2-F5-02: all 54 muscles in super-recovery (blankDays=0) returns empty menu',
      () {
        final recoveringStates = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          blankDays: 0,
        );
        final res = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: recoveringStates,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.full60,
          condition: WorkoutCondition.normal,
          now: kClockEvening1800,
        );

        expect(res.exercises, isEmpty);
        for (final info in res.muscleScores.values) {
          expect(info.mVal, 0.0);
          expect(info.synMVal, 0.0);
          expect(
            info.status,
            info.priorityP == 0
                ? MuscleScoreStatus.untargeted
                : MuscleScoreStatus.recovering,
          );
        }
      },
    );

    test(
      'T2-F5-03: partial eligibility (2 eligible machines for full60) breaks early with 2 exercises',
      () {
        final twoOnlyStates = _isolateMusclesFor(<String>['mac27', 'mac6']);
        final res = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: twoOnlyStates,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.full60, // requests 5
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
        );

        expect(res.exercises, hasLength(2));
        expect(
          res.exercises.map((e) => e.machine.id).toSet(),
          equals(<String>{'mac27', 'mac6'}),
        );
      },
    );

    test(
      'T2-F5-04: hardcoded engine constants (bCap=14, synergist=0.75, category=0.45) govern Step 4',
      () {
        expect(WorkoutMenuGenerator.bCap, 14);
        expect(WorkoutMenuGenerator.synergistAttenuation, 0.75);
        expect(WorkoutMenuGenerator.sameCategoryAttenuation, 0.45);

        // Leg-only eligible trace (oracle_vectors.md §6.2) verifies 0.45^k & 0.75
        final legOnlyStates = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
        ).map(
          (id, st) => MapEntry(
            id,
            kExpectedMuscleSpecById[id]!.group == MuscleGroup.legsGlutes
                ? st
                : st.copyWith(blankDays: 0),
          ),
        );

        final res = generator.generateMenu(
          profile: buildTestProfile(),
          muscleStates: legOnlyStates,
          machineHistory: buildDefaultMachineHistory(),
          course: WorkoutDurationCourse.standard45,
          condition: WorkoutCondition.normal,
          now: kClockDaytime1300,
          sessionCount: 1,
        );

        expect(
          res.exercises.map((e) => e.machine.id).toList(),
          // mac4 tie-break (3+7)%29=10 > mac2 (1+7)%29=8 at sessionCount=1
          <String>['mac5', 'mac4', 'mac6', 'mac10'],
        );
        expect(res.exercises[0].finalScore, closeTo(30.1, 1e-9));
        expect(res.exercises[1].finalScore, closeTo(11.6325, 1e-9)); // 25.85*0.45
        expect(res.exercises[2].finalScore, closeTo(4.768875, 1e-9)); // 23.55*0.45^2
        expect(res.exercises[3].finalScore, closeTo(1.694925, 1e-9)); // 18.6*0.45^3
      },
    );

    test(
      'T2-F5-05: engine methods are pure and never mutate caller muscleStates or machineHistory maps',
      () {
        final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
        final history = buildDefaultMachineHistory();
        final statesSnapshot = Map<String, MuscleInputState>.of(states);
        final historySnapshot = Map<String, MachineHistoryEntry>.of(history);
        final profile = buildTestProfile();

        generator.computeMuscleScores(
          muscleStates: states,
          profile: profile,
          now: kClockEvening1800,
        );
        final menu = generator.generateMenu(
          profile: profile,
          muscleStates: states,
          machineHistory: history,
          course: WorkoutDurationCourse.full60,
          condition: WorkoutCondition.normal,
          now: kClockEvening1800,
        );
        generator.advanceSessionDay(
          muscleStates: states,
          machineHistory: history,
          completedExercises: menu.exercises,
          overallFeedback: WorkoutFeedback.tooLight,
          sessionCount: 1,
          daysElapsed: 2,
        );

        expect(states, equals(statesSnapshot));
        expect(history, equals(historySnapshot));
      },
    );

    test(
      'T2-F5-06: R1 offline <50ms performance and bitwise determinism benchmark',
      () {
        final profile = buildTestProfile();
        final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
        final history = buildDefaultMachineHistory();

        runWithoutNetworkSync(() {
          // Warm-up call
          final baseline = generator.generateMenu(
            profile: profile,
            muscleStates: states,
            machineHistory: history,
            course: WorkoutDurationCourse.full60,
            condition: WorkoutCondition.normal,
            now: kClockEvening1800,
            sessionCount: 3,
          );

          final sw = Stopwatch();
          var maxElapsedMs = 0;
          for (var i = 0; i < 20; i++) {
            sw
              ..reset()
              ..start();
            final run = generator.generateMenu(
              profile: profile,
              muscleStates: states,
              machineHistory: history,
              course: WorkoutDurationCourse.full60,
              condition: WorkoutCondition.normal,
              now: kClockEvening1800,
              sessionCount: 3,
            );
            sw.stop();
            if (sw.elapsedMilliseconds > maxElapsedMs) {
              maxElapsedMs = sw.elapsedMilliseconds;
            }
            expect(run.timeSlot, baseline.timeSlot);
            expect(run.exercises, baseline.exercises);
          }

          expect(
            maxElapsedMs,
            lessThan(50),
            reason: 'R1 requires generateMenu to finish under 50ms offline',
          );
        });
      },
    );
  });

  // ===========================================================================
  // F6: Step 5 Load Prescription & advanceSessionDay Boundaries (T2-F6-01 .. 06)
  // ===========================================================================
  group('Tier 2 F6: Step 5 Load Prescription & Session Advance Boundaries', () {
    test(
      'T2-F6-01: 2.5 kg floor holds under extreme low bodyWeight, female, 60_plus, tired, and tooHard',
      () {
        final mac23States = _isolateMusclesFor(<String>['mac23']);
        final hist = buildDefaultMachineHistory();

        // S5-06: First-time extreme floor (10 kg female, 60_plus, tired, mac23)
        final firstTimeExtreme = generator.generateMenu(
          profile: buildTestProfile(
            gender: Gender.female,
            birthYear: 1966,
            experience: ExperienceLevel.beginner,
            bodyWeightKg: 10.0,
            isFirstTime: true,
          ),
          muscleStates: mac23States,
          machineHistory: hist,
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.tired,
          now: kClockDaytime1300,
        );
        expect(firstTimeExtreme.exercises.first.weightKg, 2.5);
        expect(firstTimeExtreme.exercises.first.reps, 15);
        expect(firstTimeExtreme.exercises.first.sets, 2);

        // S5-10: Returning 2.5 kg + tooHard + tired + 60_plus female (40 kg)
        final returningFloor = generator.generateMenu(
          profile: buildTestProfile(
            gender: Gender.female,
            birthYear: 1966,
            experience: ExperienceLevel.beginner,
            bodyWeightKg: 40.0,
            isFirstTime: false,
          ),
          muscleStates: mac23States,
          machineHistory: buildDefaultMachineHistory(
            overrides: const <String, MachineHistoryEntry>{
              'mac23': MachineHistoryEntry(
                machineId: 'mac23',
                sessionsSinceUsed: 6,
                lastWeightKg: 2.5,
                lastFeedback: WorkoutFeedback.tooHard,
              ),
            },
          ),
          course: WorkoutDurationCourse.short20,
          condition: WorkoutCondition.tired,
          lastFeedback: WorkoutFeedback.tooHard,
          now: kClockDaytime1300,
        );
        expect(returningFloor.exercises.first.weightKg, 2.5);
        expect(returningFloor.exercises.first.reps, 15);
        expect(returningFloor.exercises.first.sets, 2);
      },
    );

    test(
      'T2-F6-02: roundTo25 boundaries (0.0->2.5, 3.74->2.5, 3.75->5.0, 61.25->62.5, 73.625->72.5)',
      () {
        final mac23States = _isolateMusclesFor(<String>['mac23']);
        final mac1States = _isolateMusclesFor(<String>['mac1']);
        final mac1HighRotHist = buildDefaultMachineHistory(
          overrides: const <String, MachineHistoryEntry>{
            'mac1': MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 20,
            ),
          },
        );

        // 0.0 -> 2.5
        final w0 = generator
            .generateMenu(
              profile: buildTestProfile(
                birthYear: 1996,
                bodyWeightKg: 0.0,
                isFirstTime: true,
              ),
              muscleStates: mac23States,
              machineHistory: buildDefaultMachineHistory(),
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockDaytime1300,
            )
            .exercises
            .first
            .weightKg;
        expect(w0, 2.5);

        // 14.96 * 0.25 = 3.74 -> 2.5
        final w374 = generator
            .generateMenu(
              profile: buildTestProfile(
                birthYear: 1996,
                bodyWeightKg: 14.96,
                isFirstTime: true,
              ),
              muscleStates: mac23States,
              machineHistory: buildDefaultMachineHistory(),
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockDaytime1300,
            )
            .exercises
            .first
            .weightKg;
        expect(w374, 2.5);

        // 15.0 * 0.25 = 3.75 -> 5.0
        final w375 = generator
            .generateMenu(
              profile: buildTestProfile(
                birthYear: 1996,
                bodyWeightKg: 15.0,
                isFirstTime: true,
              ),
              muscleStates: mac23States,
              machineHistory: buildDefaultMachineHistory(),
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockDaytime1300,
            )
            .exercises
            .first
            .weightKg;
        expect(w375, 5.0);

        // 49.0 * 1.25 = 61.25 -> 62.5
        final w6125 = generator
            .generateMenu(
              profile: buildTestProfile(
                birthYear: 1996,
                bodyWeightKg: 49.0,
                isFirstTime: true,
              ),
              muscleStates: mac1States,
              machineHistory: mac1HighRotHist,
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.normal,
              now: kClockDaytime1300,
            )
            .exercises
            .first
            .weightKg;
        expect(w6125, 62.5);

        // S5-15: 85.0 * 0.90 = 76.5 -> 77.5; 77.5 * 0.95 = 73.625 -> 72.5
        final w73625 = generator
            .generateMenu(
              profile: buildTestProfile(
                birthYear: 1966, // 60_plus
                isFirstTime: false,
              ),
              muscleStates: mac1States,
              machineHistory: buildDefaultMachineHistory(
                overrides: const <String, MachineHistoryEntry>{
                  'mac1': MachineHistoryEntry(
                    machineId: 'mac1',
                    sessionsSinceUsed: 20,
                    lastWeightKg: 85.0,
                    lastFeedback: WorkoutFeedback.justRight,
                  ),
                },
              ),
              course: WorkoutDurationCourse.short20,
              condition: WorkoutCondition.tired,
              now: kClockDaytime1300,
            )
            .exercises
            .first
            .weightKg;
        expect(w73625, 72.5);
      },
    );

    test(
      'T2-F6-03: age rep shift edges (50s shifts 10->12 only; 60_plus shifts 10->12 and 12->15)',
      () {
        final mac11States = _isolateMusclesFor(<String>['mac11']); // baseReps=10
        final mac5States = _isolateMusclesFor(<String>['mac5']); // baseReps=12
        final mac27States = _isolateMusclesFor(<String>['mac27']); // baseReps=15
        final hist = buildDefaultMachineHistory();

        int repsFor(Map<String, MuscleInputState> st, int birthYear) {
          return generator
              .generateMenu(
                profile: buildTestProfile(birthYear: birthYear),
                muscleStates: st,
                machineHistory: hist,
                course: WorkoutDurationCourse.short20,
                condition: WorkoutCondition.normal,
                now: kClockDaytime1300,
              )
              .exercises
              .first
              .reps;
        }

        // Age 30 (20_30): 10, 12, 15
        expect(repsFor(mac11States, 1996), 10);
        expect(repsFor(mac5States, 1996), 12);
        expect(repsFor(mac27States, 1996), 15);

        // Age 55 (50s): 10->12, 12->12, 15->15
        expect(repsFor(mac11States, 1971), 12);
        expect(repsFor(mac5States, 1971), 12);
        expect(repsFor(mac27States, 1971), 15);

        // Age 65 (60_plus): 10->12, 12->15, 15->15
        expect(repsFor(mac11States, 1961), 12);
        expect(repsFor(mac5States, 1961), 15);
        expect(repsFor(mac27States, 1961), 15);
      },
    );

    test(
      'T2-F6-04: advanceSessionDay clamps (B<=30, primary S<=12.0, daysElapsed<=0 -> 1)',
      () {
        final mac20 = MasterData.machineById['mac20']!;
        final completed = <PrescribedExercise>[
          PrescribedExercise(
            machine: mac20, // primary: m4, m6, m42; syn: m11...
            weightKg: 40.0,
            reps: 10,
            sets: 3,
          ),
        ];

        final initialStates = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm4': MuscleInputState(
              muscleId: 'm4',
              blankDays: 4,
              stimulationDays: 11.8, // primary: 11.8*0.92 + 1.5 = 12.356 -> cap 12.0
              priorityP: 18,
            ),
            'm11': MuscleInputState(
              muscleId: 'm11',
              blankDays: 29,
              stimulationDays: 11.8, // syn: 11.8*0.92 + 0.3 = 11.156 -> 11.2
              priorityP: 14,
            ),
            'm2': MuscleInputState(
              muscleId: 'm2',
              blankDays: 29,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
          },
        );
        final hist = buildDefaultMachineHistory();

        // Check S<=12.0 on daysElapsed=1 and B<=30 on daysElapsed=3
        final day1 = generator.advanceSessionDay(
          muscleStates: initialStates,
          machineHistory: hist,
          completedExercises: completed,
          overallFeedback: WorkoutFeedback.justRight,
          sessionCount: 1,
          daysElapsed: 1,
        );
        expect(day1.muscleStates['m4']!.blankDays, 1);
        expect(day1.muscleStates['m4']!.stimulationDays, 12.0);
        expect(day1.muscleStates['m11']!.blankDays, 30);
        expect(day1.muscleStates['m11']!.stimulationDays, 11.2);
        expect(day1.muscleStates['m2']!.blankDays, 30);
        expect(day1.sessionCount, 2);

        final day3 = generator.advanceSessionDay(
          muscleStates: initialStates,
          machineHistory: hist,
          completedExercises: completed,
          overallFeedback: WorkoutFeedback.justRight,
          sessionCount: 1,
          daysElapsed: 3,
        );
        expect(day3.muscleStates['m11']!.blankDays, 30);
        expect(day3.muscleStates['m2']!.blankDays, 30);

        // daysElapsed <= 0 clamped to 1
        final zeroDays = generator.advanceSessionDay(
          muscleStates: buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale),
          machineHistory: hist,
          completedExercises: completed,
          overallFeedback: WorkoutFeedback.justRight,
          sessionCount: 1,
          daysElapsed: 0,
        );
        expect(zeroDays.muscleStates['m4']!.blankDays, 1);
        expect(zeroDays.muscleStates['m2']!.blankDays, 5);
        expect(zeroDays.muscleStates['m4']!.stimulationDays, 3.3);
        expect(zeroDays.muscleStates['m2']!.stimulationDays, 1.8);

        final negDays = generator.advanceSessionDay(
          muscleStates: buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale),
          machineHistory: hist,
          completedExercises: completed,
          overallFeedback: WorkoutFeedback.justRight,
          sessionCount: 1,
          daysElapsed: -3,
        );
        expect(negDays.muscleStates['m4']!.blankDays, 1);
        expect(negDays.muscleStates['m2']!.blankDays, 5);
      },
    );

    test(
      'T2-F6-05: advanceSessionDay applies primary rule only when a muscle is both primary and synergist',
      () {
        // m0 is primary in mac1 AND synergist in mac8
        final completed = <PrescribedExercise>[
          PrescribedExercise(
            machine: MasterData.machineById['mac1']!,
            weightKg: 85.0,
            reps: 10,
            sets: 3,
          ),
          PrescribedExercise(
            machine: MasterData.machineById['mac8']!,
            weightKg: 70.0,
            reps: 10,
            sets: 3,
          ),
        ];

        final res = generator.advanceSessionDay(
          muscleStates: buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale),
          machineHistory: buildDefaultMachineHistory(),
          completedExercises: completed,
          overallFeedback: WorkoutFeedback.justRight,
          sessionCount: 1,
          daysElapsed: 1,
        );

        // m0 gets primary reset (B=1, S=round1(2.0*0.92+1.5)=3.3), NOT 3.6
        expect(res.muscleStates['m0']!.blankDays, 1);
        expect(res.muscleStates['m0']!.stimulationDays, 3.3);
      },
    );

    test(
      'T2-F6-06: exact birthYear age bracket cutoffs (19 vs 20, 39 vs 40, 49 vs 50, 59 vs 60)',
      () {
        final mac1States = _isolateMusclesFor(<String>['mac1']);
        final mac5States = _isolateMusclesFor(<String>['mac5']);
        final mac1Hist = buildDefaultMachineHistory(
          overrides: const <String, MachineHistoryEntry>{
            'mac1': MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 20,
            ),
          },
        );
        final mac5Hist = buildDefaultMachineHistory();
        final refNow = DateTime(2026, 11, 19, 13, 0, 0);

        // 80 kg * 1.25 = 100.0 -> weight directly equals 100 * ageCoeff
        final brackets =
            <({
              int birthYear,
              double expectedWeight,
              int expectedMac1Reps,
              int expectedMac5Reps,
              int expectedM0R,
            })>[
          (
            birthYear: 2007, // age 19 -> under_20 (0.95)
            expectedWeight: 95.0,
            expectedMac1Reps: 10,
            expectedMac5Reps: 12,
            expectedM0R: 3,
          ),
          (
            birthYear: 2006, // age 20 -> 20_30 (1.00)
            expectedWeight: 100.0,
            expectedMac1Reps: 10,
            expectedMac5Reps: 12,
            expectedM0R: 3,
          ),
          (
            birthYear: 1987, // age 39 -> 20_30 (1.00)
            expectedWeight: 100.0,
            expectedMac1Reps: 10,
            expectedMac5Reps: 12,
            expectedM0R: 3,
          ),
          (
            birthYear: 1986, // age 40 -> 40s (0.90)
            expectedWeight: 90.0,
            expectedMac1Reps: 10,
            expectedMac5Reps: 12,
            expectedM0R: 3,
          ),
          (
            birthYear: 1977, // age 49 -> 40s (0.90)
            expectedWeight: 90.0,
            expectedMac1Reps: 10,
            expectedMac5Reps: 12,
            expectedM0R: 3,
          ),
          (
            birthYear: 1976, // age 50 -> 50s (0.80, R+1, 10->12)
            expectedWeight: 80.0,
            expectedMac1Reps: 12,
            expectedMac5Reps: 12,
            expectedM0R: 4,
          ),
          (
            birthYear: 1967, // age 59 -> 50s (0.80, R+1, 10->12)
            expectedWeight: 80.0,
            expectedMac1Reps: 12,
            expectedMac5Reps: 12,
            expectedM0R: 4,
          ),
          (
            birthYear: 1966, // age 60 -> 60_plus (0.65, R+1, 10->12 & 12->15)
            expectedWeight: 65.0,
            expectedMac1Reps: 12,
            expectedMac5Reps: 15,
            expectedM0R: 4,
          ),
        ];

        for (final b in brackets) {
          final profile = buildTestProfile(
            gender: Gender.male,
            birthYear: b.birthYear,
            experience: ExperienceLevel.beginner,
            bodyWeightKg: 80.0,
            isFirstTime: true,
          );

          final mac1Menu = generator.generateMenu(
            profile: profile,
            muscleStates: mac1States,
            machineHistory: mac1Hist,
            course: WorkoutDurationCourse.short20,
            condition: WorkoutCondition.normal,
            now: refNow,
          );
          final mac5Menu = generator.generateMenu(
            profile: profile,
            muscleStates: mac5States,
            machineHistory: mac5Hist,
            course: WorkoutDurationCourse.short20,
            condition: WorkoutCondition.normal,
            now: refNow,
          );

          expect(mac1Menu.exercises.first.machine.id, 'mac1');
          expect(
            mac1Menu.exercises.first.weightKg,
            b.expectedWeight,
            reason: 'weight mismatch for birthYear=${b.birthYear}',
          );
          expect(
            mac1Menu.exercises.first.reps,
            b.expectedMac1Reps,
            reason: 'mac1 reps mismatch for birthYear=${b.birthYear}',
          );
          expect(
            mac5Menu.exercises.first.reps,
            b.expectedMac5Reps,
            reason: 'mac5 reps mismatch for birthYear=${b.birthYear}',
          );
          expect(
            mac1Menu.muscleScores['m0']!.effectiveRecoveryDays,
            b.expectedM0R,
            reason: 'm0 effectiveR mismatch for birthYear=${b.birthYear}',
          );
        }
      },
    );
  });
}
