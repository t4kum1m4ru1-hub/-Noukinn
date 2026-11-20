import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/engine/workout_menu_generator.dart';
import 'package:noukin/models/models.dart';

void main() {
  const generator = WorkoutMenuGenerator();
  final daytimeNow = DateTime(2026, 11, 19, 13, 0);
  const profile = UserProfile();

  group('Degenerate & Boundary Inputs', () {
    test('all 54 muscles injured yields empty menu without throwing', () {
      final injuredAll = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, isInjured: true),
      };

      final res = generator.generateMenu(
        profile: profile,
        muscleStates: injuredAll,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );

      expect(res.exercises, isEmpty);
      expect(
        res.muscleScores.values.every(
          (s) => s.status == MuscleScoreStatus.injured && s.mVal == 0.0,
        ),
        isTrue,
      );
    });

    test('all 54 muscles blankDays=0 yields empty menu with recovering/untargeted statuses', () {
      final zeroBlank = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(
            muscleId: m.id,
            blankDays: 0,
            priorityP: MasterData.purposePriorities[profile.purpose]![m.id]!,
          ),
      };

      final res = generator.generateMenu(
        profile: profile,
        muscleStates: zeroBlank,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );

      expect(res.exercises, isEmpty);
      expect(
        res.muscleScores.values.every(
          (s) =>
              s.status == MuscleScoreStatus.recovering ||
              s.status == MuscleScoreStatus.untargeted,
        ),
        isTrue,
      );
    });

    test('breaks early when fewer than course.exerciseCount machines are eligible', () {
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4),
      };
      // Only mac27 (primary m7) and mac26 (primary m12) are eligible
      states['m7'] = const MuscleInputState(muscleId: 'm7', priorityP: 18, blankDays: 6);
      states['m12'] = const MuscleInputState(muscleId: 'm12', priorityP: 18, blankDays: 6);

      final res = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );

      // mac27 (m7), mac26 (m12), and mac15/mac19? No, mac15 has primary m12 & m30(P=0 -> excluded).
      expect(res.exercises.length, 2);
      expect(
        res.exercises.map((e) => e.machine.id).toSet(),
        <String>{'mac26', 'mac27'},
      );
    });

    test('missing muscleStates and machineHistory keys fall back safely to defaults', () {
      final res = generator.generateMenu(
        profile: profile,
        muscleStates: const <String, MuscleInputState>{},
        machineHistory: const <String, MachineHistoryEntry>{},
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );

      expect(res.muscleScores.length, 54);
      expect(res.exercises.length, 4);
    });

    test('never mutates caller-supplied muscleStates or machineHistory maps', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = MasterData.defaultMachineHistory();
      final statesBefore = Map<String, MuscleInputState>.from(states);
      final historyBefore = Map<String, MachineHistoryEntry>.from(history);

      generator.computeMuscleScores(
        muscleStates: states,
        profile: profile,
        now: daytimeNow,
      );
      final menu = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      generator.advanceSessionDay(
        muscleStates: states,
        machineHistory: history,
        completedExercises: menu.exercises,
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 1,
      );

      expect(states, statesBefore);
      expect(history, historyBefore);
    });

    test('lastFeedback == null triggers HIGH_VOLUME_EXTEND_MUSCLES R+1 when machineHistory has tooHard', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = MasterData.defaultMachineHistory();
      history['mac11'] = const MachineHistoryEntry(
        machineId: 'mac11',
        sessionsSinceUsed: 1,
        lastWeightKg: 50.0,
        lastFeedback: WorkoutFeedback.tooHard,
      );

      final res = generator.generateMenu(
        profile: profile.copyWith(isFirstTime: false),
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        lastFeedback: null,
        now: daytimeNow,
      );

      expect(res.muscleScores['m29']!.isExtendedByVolume, isTrue);
      expect(res.muscleScores['m29']!.effectiveRecoveryDays, 3);
      expect(res.muscleScores['m0']!.isExtendedByVolume, isFalse);
    });

    test('sanitizes non-finite and non-positive returning lastWeightKg across feedback and conditions', () {
      // Isolate mac23 (baseWeight = 20.0, primary = ['m35'])
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4),
      };
      states['m35'] = const MuscleInputState(
        muscleId: 'm35',
        priorityP: 18,
        blankDays: 8,
        stimulationDays: 0.0,
      );

      final invalidWeights = <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -0.0,
        0.0,
        -20.0,
      ];
      const feedbacks = <WorkoutFeedback>[
        WorkoutFeedback.justRight,
        WorkoutFeedback.tooLight,
        WorkoutFeedback.tooHard,
      ];
      const conditions = <WorkoutCondition>[
        WorkoutCondition.normal,
        WorkoutCondition.tired,
      ];

      for (final badW in invalidWeights) {
        for (final fb in feedbacks) {
          for (final cond in conditions) {
            final history = MasterData.defaultMachineHistory();
            history['mac23'] = MachineHistoryEntry(
              machineId: 'mac23',
              sessionsSinceUsed: 6,
              lastWeightKg: badW,
              lastFeedback: fb,
            );

            final res = generator.generateMenu(
              profile: profile.copyWith(isFirstTime: false, birthYear: 1995),
              muscleStates: states,
              machineHistory: history,
              course: WorkoutDurationCourse.short20,
              condition: cond,
              now: daytimeNow,
            );

            final ex = res.exercises.firstWhere((e) => e.machine.id == 'mac23');
            // mac23.baseWeight = 20.0
            final expectedBase = switch (fb) {
              WorkoutFeedback.justRight => 20.0,
              WorkoutFeedback.tooLight => 22.5,
              WorkoutFeedback.tooHard => 17.5,
            };
            final expectedFinal = cond == WorkoutCondition.tired
                ? ((expectedBase * 0.95) / 2.5).round() * 2.5
                : expectedBase;

            expect(
              ex.weightKg.isFinite,
              isTrue,
              reason: 'badW=$badW fb=$fb cond=$cond',
            );
            expect(
              ex.weightKg,
              greaterThanOrEqualTo(2.5),
              reason: 'badW=$badW fb=$fb cond=$cond',
            );
            expect(
              ex.weightKg,
              expectedFinal,
              reason: 'badW=$badW fb=$fb cond=$cond',
            );
          }
        }
      }

      // Small positive finite lastWeightKg (< 2.5) is also floored to 2.5 kg
      final lowHistory = MasterData.defaultMachineHistory();
      lowHistory['mac23'] = const MachineHistoryEntry(
        machineId: 'mac23',
        sessionsSinceUsed: 6,
        lastWeightKg: 1.0,
        lastFeedback: WorkoutFeedback.justRight,
      );
      final lowRes = generator.generateMenu(
        profile: profile.copyWith(isFirstTime: false, birthYear: 1995),
        muscleStates: states,
        machineHistory: lowHistory,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(
        lowRes.exercises.firstWhere((e) => e.machine.id == 'mac23').weightKg,
        2.5,
      );
    });

    test('advanceSessionDay prevents 64-bit signed integer wraparound on extreme daysElapsed and blankDays', () {
      const maxInt = 0x7fffffffffffffff;
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      // m1 is synergist of mac1, m3 is unused, m0 is primary of mac1
      states['m1'] = const MuscleInputState(
        muscleId: 'm1',
        blankDays: 10,
        stimulationDays: 2.0,
      );
      states['m3'] = const MuscleInputState(
        muscleId: 'm3',
        blankDays: maxInt - 5,
        stimulationDays: 2.0,
      );

      final mac1 = MasterData.machineById['mac1']!;
      final advanced = generator.advanceSessionDay(
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        completedExercises: <PrescribedExercise>[
          PrescribedExercise(machine: mac1, weightKg: 85.0, reps: 10, sets: 3),
        ],
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 1,
        daysElapsed: maxInt,
      );

      expect(advanced.muscleStates['m0']!.blankDays, 30);
      expect(advanced.muscleStates['m1']!.blankDays, 30);
      expect(advanced.muscleStates['m3']!.blankDays, 30);
      for (final s in advanced.muscleStates.values) {
        expect(s.blankDays, inInclusiveRange(0, 30));
        expect(s.stimulationDays.isFinite, isTrue);
        expect(s.stimulationDays, greaterThanOrEqualTo(0.0));
      }
    });
  });

  group('R1 Compliance, Zero-Network & Performance', () {
    test('exposes hardcoded R1 engine constants', () {
      expect(WorkoutMenuGenerator.bCap, 14);
      expect(WorkoutMenuGenerator.synergistAttenuation, 0.75);
      expect(WorkoutMenuGenerator.sameCategoryAttenuation, 0.45);
    });

    test('runs 100% offline with HttpOverrides blocking all network and completes < 50 ms', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = MasterData.defaultMachineHistory();

      HttpOverrides.runZoned(
        () {
          // Warmup
          final warmup = generator.generateMenu(
            profile: profile,
            muscleStates: states,
            machineHistory: history,
            course: WorkoutDurationCourse.full60,
            condition: WorkoutCondition.normal,
            now: daytimeNow,
          );
          expect(warmup.exercises.length, 5);

          final sw = Stopwatch()..start();
          for (var i = 0; i < 20; i++) {
            final run = generator.generateMenu(
              profile: profile,
              muscleStates: states,
              machineHistory: history,
              course: WorkoutDurationCourse.full60,
              condition: WorkoutCondition.normal,
              now: daytimeNow,
            );
            expect(run.exercises, warmup.exercises);
          }
          sw.stop();

          final avgMs = sw.elapsedMilliseconds / 20.0;
          expect(avgMs, lessThan(50.0));

          final advanced = generator.advanceSessionDay(
            muscleStates: states,
            machineHistory: history,
            completedExercises: warmup.exercises,
            overallFeedback: WorkoutFeedback.justRight,
            sessionCount: 1,
          );
          expect(advanced.sessionCount, 2);
        },
        createHttpClient: (_) {
          throw StateError('External network call prohibited by R1');
        },
      );
    });

    test('lib/data and lib/engine are pure Dart with zero R1 prohibited terms', () {
      final targetPaths = <String>[
        'lib/data/master_data.dart',
        'lib/engine/workout_menu_generator.dart',
      ];
      final prohibited = <RegExp>[
        RegExp(r'package:flutter/'),
        RegExp(r'gym\s*ai', caseSensitive: false),
        RegExp(r'button_controll_test'),
        RegExp(r'flutter_tts'),
        RegExp(r'audio_session'),
        RegExp(r'TtsService'),
        RegExp(r'AudioDuckingController'),
        RegExp(r'SoundEffectService'),
        RegExp(r'ButtonAction'),
        RegExp(r'KeyEventChannelDispatcher'),
        RegExp(r'TutorialScreen'),
        RegExp(r'api\.openai\.com'),
        RegExp(r'api\.anthropic\.com'),
        RegExp(r'generativelanguage\.googleapis\.com'),
      ];

      for (final rel in targetPaths) {
        final file = File(rel);
        expect(file.existsSync(), isTrue, reason: '$rel must exist');
        final content = file.readAsStringSync();
        for (final pattern in prohibited) {
          expect(
            pattern.hasMatch(content),
            isFalse,
            reason: 'Prohibited pattern ${pattern.pattern} found in $rel',
          );
        }
      }
    });
  });
}
