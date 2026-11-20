import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/config/supabase_config.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/engine/workout_menu_generator.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/services/workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_test_helpers.dart';

// =============================================================================
// Local Test Helpers (Opaque-Box Descendant Readers)
// =============================================================================

String _extractText(WidgetTester tester, String key) {
  final root = find.byKey(Key(key));
  expect(root, findsOneWidget, reason: 'Widget with key "$key" must exist');
  final widget = tester.widget<Widget>(root);
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  final textDescendants = find.descendant(
    of: root,
    matching: find.byType(Text),
  );
  return textDescendants
      .evaluate()
      .map((e) {
        final t = e.widget as Text;
        return t.data ?? t.textSpan?.toPlainText() ?? '';
      })
      .join(' ')
      .trim();
}

String _formatWeightKg(double kg) {
  if (kg == kg.roundToDouble()) {
    return '${kg.toInt()} kg';
  }
  return '${kg.toStringAsFixed(1)} kg';
}

ExpectedMachineSpec _specByExerciseTitle(String title) {
  for (final spec in kExpectedMachineSpecs) {
    if (title.contains(spec.name) || spec.name.contains(title)) {
      return spec;
    }
  }
  fail('Unknown exercise title "$title" not found in 29 master machines');
}

/// Traverses all [expectedCount] exercises on Screen A2 via `'btn_next_workout'`
/// using [advanceWorkoutToA3] (handling both `N` and `N+1` `'開始'->'次へ'` taps)
/// and returns their displayed `'exercise_title'` strings in order.
Future<List<String>> _collectAndCompleteA2Exercises(
  WidgetTester tester,
  int expectedCount,
) async {
  final titles = await advanceWorkoutToA3(tester, expectedCount: expectedCount);
  expect(titles, hasLength(expectedCount));
  return titles;
}

/// Attempts to increment `B_i` inside a Screen B group batch widget (`group_batch_*`)
/// using opaque-box UI patterns (add icon / `+` button / text field).
Future<void> _tryAdjustGroupBatchBlankDays(
  WidgetTester tester,
  String groupKey, {
  int incrementSteps = 5,
}) async {
  final groupFinder = find.byKey(Key(groupKey));
  if (groupFinder.evaluate().isEmpty) {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(
        groupFinder,
        200.0,
        scrollable: scrollables.first,
      );
    }
  }
  expect(groupFinder, findsOneWidget);
  await tester.ensureVisible(groupFinder);

  // Look for a B_i label row inside the group batch section, else add icons.
  final bLabel = find.descendant(
    of: groupFinder,
    matching: find.textContaining('ブランク'),
  );
  final addButtons = find.descendant(
    of: groupFinder,
    matching: find.byIcon(Icons.add),
  );
  final plusOneButtons = find.descendant(
    of: groupFinder,
    matching: find.textContaining('+1'),
  );

  if (plusOneButtons.evaluate().isNotEmpty) {
    final target = plusOneButtons.first;
    await tester.ensureVisible(target);
    for (var i = 0; i < incrementSteps; i++) {
      await tester.tap(target);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  } else if (addButtons.evaluate().isNotEmpty) {
    // Prefer the second Icons.add if P/B/S order is used and B label exists,
    // otherwise tap the add button closest to B_i.
    final idx = (bLabel.evaluate().isNotEmpty && addButtons.evaluate().length >= 2)
        ? 1
        : 0;
    final target = addButtons.at(idx);
    await tester.ensureVisible(target);
    for (var i = 0; i < incrementSteps; i++) {
      await tester.tap(target);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }
}

void main() {
  const generator = WorkoutMenuGenerator();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Tier 3 — Pairwise Cross-Feature Combinations (T3-01 .. T3-20)', () {
    test('T3-01 (F2 x F4): Morning 08:00 x1.25 cannot revive recovering m9 (B=1 < R=3)', () {
      final profile = buildTestProfile();
      final statesRecoveringM9 = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: const <String, MuscleInputState>{
          'm9': MuscleInputState(
            muscleId: 'm9',
            blankDays: 1,
            stimulationDays: 2.0,
            priorityP: 14,
          ),
        },
      );
      // Give mac29 extreme rotation (n=15) to prove primaryScore==0 still gates bonuses.
      final historyHighMac29 = buildDefaultMachineHistory(
        overrides: const <String, MachineHistoryEntry>{
          'mac29': MachineHistoryEntry(
            machineId: 'mac29',
            sessionsSinceUsed: 15,
          ),
        },
      );

      final scores = generator.computeMuscleScores(
        muscleStates: statesRecoveringM9,
        profile: profile,
        now: kClockMorning0800,
      );
      expect(scores['m9']!.mVal, 0.0);
      expect(scores['m9']!.synMVal, 0.0);
      expect(scores['m9']!.status, MuscleScoreStatus.recovering);

      final resultRecovering = generator.generateMenu(
        profile: profile,
        muscleStates: statesRecoveringM9,
        machineHistory: historyHighMac29,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockMorning0800,
        sessionCount: 1,
      );
      expect(resultRecovering.timeSlot, TimeSlot.morning);
      expect(
        resultRecovering.exercises.any((e) => e.machine.id == 'mac29'),
        isFalse,
        reason: 'Recovering primary m9 zeroes primaryScore and blocks morning x1.25 revival',
      );

      // Contrast: once m9 recovers (B=4 >= R=3), mac29 with n=15 jumps to #1 in morning.
      final statesActiveM9 = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final resultActive = generator.generateMenu(
        profile: profile,
        muscleStates: statesActiveM9,
        machineHistory: historyHighMac29,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockMorning0800,
        sessionCount: 1,
      );
      expect(resultActive.exercises.first.machine.id, 'mac29');
      expect(resultActive.exercises.first.finalScore, closeTo(57.0, 1e-6));
    });

    test('T3-02 (F2 x F4): Night 22:00 + focusMuscleId=m0 yields combined 0.30 x 1.25 = 0.375', () {
      final night2200 = DateTime(2026, 11, 19, 22, 0);
      final profile = buildTestProfile();

      // Isolate mac5 (m0, m13 primaries; m18 synergist) to verify exact combined score.
      final allOtherInjured = <String>{
        for (final m in kExpectedMuscleSpecs)
          if (m.id != 'm0' && m.id != 'm13' && m.id != 'm18') m.id,
      };
      final isolatedStates = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        injuredIds: allOtherInjured,
      );
      final history = buildDefaultMachineHistory();

      final nightFocused = generator.generateMenu(
        profile: profile,
        muscleStates: isolatedStates,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        focusMuscleId: 'm0',
        now: night2200,
        sessionCount: 1,
      );
      expect(nightFocused.timeSlot, TimeSlot.night);
      expect(nightFocused.exercises, hasLength(1));
      expect(nightFocused.exercises.first.machine.id, 'mac5');
      // raw = 15.8 + 1.8 + 9.5 + 3.5 = 30.6; final = 30.6 * (0.30 * 1.25) = 11.475
      expect(nightFocused.exercises.first.rawScore, closeTo(30.6, 1e-6));
      expect(nightFocused.exercises.first.finalScore, closeTo(11.475, 1e-6));

      // With all muscles healthy, night suppression still prevents mac5 from topping night menu.
      final healthyStates = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final healthyNight = generator.generateMenu(
        profile: profile,
        muscleStates: healthyStates,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        focusMuscleId: 'm0',
        now: night2200,
        sessionCount: 1,
      );
      expect(healthyNight.exercises.first.machine.id, isNot('mac5'));
    });

    test('T3-03 (F3 x F5): mac7 TFL P=0 rule + 4-pick overlap loop zeroes primaries & attenuates synergists x0.75', () {
      final profile = buildTestProfile(
        gender: Gender.female,
        purpose: TrainingPurpose.bodyMakeFemale,
      );
      final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeFemale);
      expect(states['m27']!.priorityP, 0);

      // Boost mac7 rotation so it wins pick #0 deterministically.
      final history = buildDefaultMachineHistory(
        overrides: const <String, MachineHistoryEntry>{
          'mac7': MachineHistoryEntry(machineId: 'mac7', sessionsSinceUsed: 12),
        },
      );

      final result = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );

      expect(result.exercises, hasLength(4));
      expect(result.exercises.first.machine.id, 'mac7');
      // Under bodyMakeFemale (B=4, S=2.0): m2=17.0, m5=18.0, m14=13.0, TFL(m27 stripped);
      // primaryScore = 18.0*0.7 + ((18.0+17.0)/2)*0.3 = 17.85; syn=6.0 -> 1.8; rot=16.0; str=4.0 -> raw=39.65
      expect(result.exercises.first.rawScore, closeTo(39.65, 1e-6));

      // Picking mac7 zeroed m2 (sole primary of mac8), so mac8 cannot be picked afterward.
      final pickedIds = result.exercises.map((e) => e.machine.id).toList();
      expect(pickedIds, isNot(contains('mac8')));
      expect(pickedIds.toSet().length, 4);

      // Verify muscleScores reflects m27 as untargeted (mVal=0, synMVal=6.0)
      expect(result.muscleScores['m27']!.mVal, 0.0);
      expect(result.muscleScores['m27']!.synMVal, 6.0);
      expect(result.muscleScores['m27']!.status, MuscleScoreStatus.untargeted);
    });

    test('T3-04 (F2 x F6): 50s age bracket + tooHard stacks R+2 on m34, drops -2.5kg, shifts 10->12 reps', () {
      final now2026 = DateTime(2026, 11, 19, 13, 0);
      // 2026 - 1971 = 55 -> 50s bracket (0.80, R+1 all 54 muscles, 10->12 reps)
      final profile = buildTestProfile(
        birthYear: 1971,
        isFirstTime: false,
      );

      // m34 base R=2, in HIGH_VOLUME_EXTEND_MUSCLES -> R = 2 + 1 (50s) + 1 (tooHard) = 4
      final statesB3 = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: const <String, MuscleInputState>{
          'm34': MuscleInputState(
            muscleId: 'm34',
            blankDays: 3,
            stimulationDays: 2.0,
            priorityP: 14,
          ),
          'm0': MuscleInputState(
            muscleId: 'm0',
            blankDays: 4,
            stimulationDays: 2.0,
            priorityP: 18,
          ),
        },
      );

      final scores = generator.computeMuscleScores(
        muscleStates: statesB3,
        profile: profile,
        lastFeedback: WorkoutFeedback.tooHard,
        now: now2026,
      );
      expect(scores['m34']!.effectiveRecoveryDays, 4);
      expect(scores['m34']!.mVal, 0.0);
      expect(scores['m34']!.status, MuscleScoreStatus.recovering);
      // m0 is NOT in HIGH_VOLUME_EXTEND_MUSCLES -> R = 3 + 1 (50s) = 4; B=4 -> active (16.0)
      expect(scores['m0']!.effectiveRecoveryDays, 4);
      expect(scores['m0']!.mVal, 16.0);
      expect(scores['m0']!.status, MuscleScoreStatus.active);

      // Returning 50s + tooHard prescription on mac1 (baseReps=10, lastWeightKg=85.0)
      final onlyMac1 = <String>{
        for (final m in kExpectedMuscleSpecs)
          if (!const <String>['m0', 'm2', 'm13', 'm1', 'm14', 'm16', 'm17']
              .contains(m.id))
            m.id,
      };
      final statesForMac1 = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        injuredIds: onlyMac1,
      );
      final history = buildDefaultMachineHistory(
        overrides: const <String, MachineHistoryEntry>{
          'mac1': MachineHistoryEntry(
            machineId: 'mac1',
            sessionsSinceUsed: 8,
            lastWeightKg: 85.0,
            lastFeedback: WorkoutFeedback.tooHard,
          ),
        },
      );

      final result = generator.generateMenu(
        profile: profile,
        muscleStates: statesForMac1,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: now2026,
        lastFeedback: WorkoutFeedback.tooHard,
      );
      final mac1Pick = result.exercises.firstWhere((e) => e.machine.id == 'mac1');
      expect(mac1Pick.weightKg, 82.5);
      expect(mac1Pick.reps, 12);
      expect(mac1Pick.sets, 3);
    });

    test('T3-05 (F4 x F5): full60 at night + tired applies x0.30, iso bonus, 0.45^k, -5% & 2 sets', () {
      final profile = buildTestProfile(bodyWeightKg: 65.0, isFirstTime: true);
      final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final history = buildDefaultMachineHistory();

      final result = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.tired,
        now: kClockNight2230,
        sessionCount: 1,
      );

      expect(result.timeSlot, TimeSlot.night);
      expect(result.exercises, hasLength(5));
      expect(
        result.exercises.map((e) => e.machine.id).toSet().length,
        5,
      );

      // Top pick should NOT be a night-avoid heavy compound (mac1, mac11, mac16)
      expect(
        const <String>['mac1', 'mac11', 'mac16'],
        isNot(contains(result.exercises.first.machine.id)),
      );
      // mac23 (shoulders, non-night-avoid, iso +3.5) ranks #1 at night
      expect(result.exercises.first.machine.id, 'mac23');

      for (final ex in result.exercises) {
        expect(ex.sets, 2);
        final spec = kExpectedMachineSpecById[ex.machine.id]!;
        final expectedNormalW = oracleRoundTo25(65.0 * spec.bwFactor);
        final expectedTiredW = oracleRoundTo25(expectedNormalW * 0.95);
        expect(ex.weightKg, expectedTiredW);
      }
    });

    test('T3-06 (F5 x F6): advanceSessionDay -> next-day generateMenu suppresses trained primaries & rotates', () {
      final profile = buildTestProfile(isFirstTime: false);
      final statesDay1 = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final historyDay1 = buildDefaultMachineHistory();

      final day1Menu = generator.generateMenu(
        profile: profile,
        muscleStates: statesDay1,
        machineHistory: historyDay1,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );
      final day1MachineIds = day1Menu.exercises.map((e) => e.machine.id).toSet();
      final day1PrimaryIds = <String>{
        for (final ex in day1Menu.exercises) ...ex.machine.primaryMuscleIds,
      };
      expect(day1MachineIds, hasLength(4));

      final advanced = generator.advanceSessionDay(
        muscleStates: statesDay1,
        machineHistory: historyDay1,
        completedExercises: day1Menu.exercises,
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 1,
        daysElapsed: 1,
      );

      expect(advanced.sessionCount, 2);
      for (final id in day1MachineIds) {
        expect(advanced.machineHistory[id]!.sessionsSinceUsed, 0);
      }
      for (final pId in day1PrimaryIds) {
        expect(advanced.muscleStates[pId]!.blankDays, 1);
        expect(advanced.muscleStates[pId]!.stimulationDays, closeTo(3.3, 1e-6));
      }

      final day2Menu = generator.generateMenu(
        profile: profile,
        muscleStates: advanced.muscleStates,
        machineHistory: advanced.machineHistory,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300.add(const Duration(days: 1)),
        sessionCount: advanced.sessionCount,
      );

      for (final pId in day1PrimaryIds) {
        expect(day2Menu.muscleScores[pId]!.mVal, 0.0);
        expect(day2Menu.muscleScores[pId]!.status, MuscleScoreStatus.recovering);
      }
      final day2MachineIds = day2Menu.exercises.map((e) => e.machine.id).toSet();
      expect(
        day2MachineIds.intersection(day1MachineIds),
        isEmpty,
        reason: 'Next-day menu must rotate away from Day 1 machines whose primaries are recovering',
      );
    });

    test('T3-07 (F1 x F10): windsurfing + m4 (広背筋) injury excludes all 7 m4-involved machines', () {
      const m4Machines = <String>{
        'mac13',
        'mac15',
        'mac16',
        'mac17',
        'mac18',
        'mac19',
        'mac20',
      };
      final expectedFromSpec = <String>{
        for (final m in kExpectedMachineSpecs)
          if (m.primaryMuscleIds.contains('m4') ||
              m.synergistMuscleIds.contains('m4'))
            m.id,
      };
      expect(expectedFromSpec, m4Machines);
      expect(
        MasterData.machines
            .where(
              (m) =>
                  m.primaryMuscleIds.contains('m4') ||
                  m.synergistMuscleIds.contains('m4'),
            )
            .map((m) => m.id)
            .toSet(),
        m4Machines,
      );

      final profile = buildTestProfile(purpose: TrainingPurpose.windsurfing);
      final states = buildDefaultMuscleStates(
        TrainingPurpose.windsurfing,
        injuredIds: const <String>{'m4'},
      );
      final history = buildDefaultMachineHistory();

      final result = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
      );

      expect(result.exercises, hasLength(5));
      for (final ex in result.exercises) {
        expect(m4Machines, isNot(contains(ex.machine.id)));
      }
    });

    testWidgets('T3-08 (F7 x F8): Screen A1 (short20, tired, focus=m3) -> A2 shows 2 exercises, 2 sets, -5% weight', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapKey(tester, 'course_short');
      await tapKey(tester, 'condition_tired');
      await selectDropdownOption(tester, 'focus_muscle_dropdown', '大胸筋（全体・中部）');
      await tapKey(tester, 'btn_start_workout');

      expect(find.byKey(const Key('exercise_title')), findsOneWidget);
      expect(_extractText(tester, 'exercise_progress_badge'), contains('1 / 2'));
      expect(_extractText(tester, 'card_sets'), contains('2 セット'));

      final firstTitle = _extractText(tester, 'exercise_title');
      final firstSpec = _specByExerciseTitle(firstTitle);
      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final profile = (await repo.loadProfile()) ?? const UserProfile();
      final age = kClockDaytime1300.year - profile.birthYear;
      final ageCoeff = age < 20
          ? 0.95
          : (age < 40 ? 1.0 : (age < 50 ? 0.9 : (age < 60 ? 0.8 : 0.65)));
      final normalW = oracleRoundTo25(
        profile.bodyWeightKg *
            firstSpec.bwFactor *
            profile.gender.firstTimeWeightFactor *
            profile.experience.firstTimeWeightFactor *
            ageCoeff,
      );
      final tiredW = oracleRoundTo25(normalW * 0.95);
      expect(_extractText(tester, 'card_weight'), contains(_formatWeightKg(tiredW)));

      // Exercise 2 also has 2 sets and completes to Screen A3 (handles N / N+1 taps).
      await advanceToNextExercise(tester);
      expect(_extractText(tester, 'exercise_progress_badge'), contains('2 / 2'));
      expect(_extractText(tester, 'card_sets'), contains('2 セット'));

      await advanceToNextExercise(tester);
      expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);
    });

    testWidgets('T3-09 (F8 x F9): Screen A2 +2.5kg edit & exercise swap saves modified CompletedExerciseRecords on A3', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapKey(tester, 'course_short');
      await tapKey(tester, 'btn_start_workout');

      final initialTitle = _extractText(tester, 'exercise_title');

      // Open swap sheet and pick the 2nd prescribed exercise.
      await tapKey(tester, 'btn_select_exercise');
      final swapOption1 = find.byKey(const Key('swap_exercise_option_1'));
      if (swapOption1.evaluate().isNotEmpty) {
        await tester.tap(swapOption1);
      } else {
        final sheetTiles = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(ListTile),
        );
        expect(sheetTiles, findsAtLeastNWidgets(2));
        await tester.tap(sheetTiles.at(1));
      }
      await tester.pumpAndSettle();

      final swappedTitle = _extractText(tester, 'exercise_title');
      expect(swappedTitle, isNot(initialTitle));
      final swappedSpec = _specByExerciseTitle(swappedTitle);

      // Increment weight by +2.5kg and reps by +1
      final weightBeforeText = _extractText(tester, 'card_weight');
      await tapCounterButton(tester, 'card_weight', increment: true);
      await tapCounterButton(tester, 'card_reps', increment: true);
      await tester.pumpAndSettle();
      final weightAfterText = _extractText(tester, 'card_weight');
      expect(weightAfterText, isNot(weightBeforeText));

      // Complete both exercises and finish on Screen A3 (handles N / N+1 taps).
      await advanceWorkoutToA3(tester, expectedCount: 2);
      await tapKey(tester, 'feedback_just_right');
      await tapKey(tester, 'btn_finish_workout');

      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final sessions = await repo.loadSessionHistory();
      expect(sessions, hasLength(1));
      final savedFirst = sessions.first.exercises.first;
      expect(savedFirst.machineId, swappedSpec.id);
      expect(weightAfterText, contains(_formatWeightKg(savedFirst.weightKg)));
      expect(_formatWeightKg(savedFirst.weightKg), isNot(weightBeforeText));
    });

    testWidgets('T3-10 (F9 x F7): Screen A3 tooLight persists +2.5kg for next A1->A2 workout', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      // Session 1: short20 -> capture first machine & weight -> finish with tooLight
      await tapKey(tester, 'course_short');
      await tapKey(tester, 'btn_start_workout');

      final firstTitle = _extractText(tester, 'exercise_title');
      final firstSpec = _specByExerciseTitle(firstTitle);
      final firstWeightText = _extractText(tester, 'card_weight');

      await advanceWorkoutToA3(tester, expectedCount: 2);
      await tapKey(tester, 'feedback_too_light');
      await tapKey(tester, 'btn_finish_workout');

      // Verify machineHistory saved lastWeightKg & tooLight feedback
      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final historyAfterS1 = await repo.loadMachineHistory();
      final entryS1 = historyAfterS1[firstSpec.id]!;
      expect(entryS1.lastFeedback, WorkoutFeedback.tooLight);
      expect(entryS1.lastWeightKg, isNotNull);
      expect(firstWeightText, contains(_formatWeightKg(entryS1.lastWeightKg!)));
      final expectedNextWeight = entryS1.lastWeightKg! + 2.5;

      // Simulate recovery days passing & isolate firstSpec so A1->A2 prescribes it next
      final recoveredOnlyFirst = <String, MuscleInputState>{
        for (final m in kExpectedMuscleSpecs)
          m.id: MuscleInputState(
            muscleId: m.id,
            blankDays: 5,
            stimulationDays: 2.0,
            priorityP: kExpectedPurposePriorities[TrainingPurpose.bodyMakeMale]![m.id]!,
            isInjured: !firstSpec.primaryMuscleIds.contains(m.id) &&
                !firstSpec.synergistMuscleIds.contains(m.id),
          ),
      };
      await repo.saveMuscleStates(recoveredOnlyFirst);

      await restartNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300.add(const Duration(days: 5))),
      );
      await tapKey(tester, 'course_short');
      await tapKey(tester, 'btn_start_workout');

      expect(_extractText(tester, 'exercise_title'), contains(firstSpec.name));
      expect(
        _extractText(tester, 'card_weight'),
        contains(_formatWeightKg(expectedNextWeight)),
      );
    });

    testWidgets('T3-11 (F10 x F7/F8): Screen B m0 injury + chest batch -> A1/A2 excludes m0 & includes chest', (tester) async {
      const m0Machines = <String>{
        'レッグプレス',
        'ハックスクワット',
        'ペンデュラムスクワット',
        'ベルトスクワット',
        'レッグエクステンション',
        'グルート／ヒップスラストマシン',
      };
      const chestMachines = <String>{
        'チェストプレス（フラット／ヴァーティカル）',
        'インクラインチェストプレス',
        'デクラインチェストプレス／ワイドチェスト',
        'ペックフライ／バタフライ（ペックデック）',
        'シーテッドディップ',
      };

      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_custom');
      await tapKey(tester, 'injury_toggle_m0');
      await _tryAdjustGroupBatchBlankDays(
        tester,
        'group_batch_chest',
        incrementSteps: 5,
      );

      await tapNavTab(tester, 'nav_tab_training');
      await tapKey(tester, 'course_standard');
      await tapKey(tester, 'btn_start_workout');

      final titles = await _collectAndCompleteA2Exercises(tester, 4);
      for (final t in titles) {
        expect(
          m0Machines.any((forbidden) => t.contains(forbidden)),
          isFalse,
          reason: 'Injured m0 machine "$t" must be excluded from A2',
        );
      }
      expect(
        titles.any((t) => chestMachines.any((c) => t.contains(c))),
        isTrue,
        reason: 'Chest exercises must be prescribed when m0 is injured and chest prioritized',
      );
    });

    testWidgets('T3-12 (F11 x F10): Screen C gender flip (male->female) updates Screen B purpose & 54-muscle P_i', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_settings');
      final genderRoot = find.byKey(const Key('gender_selector'));
      expect(genderRoot, findsOneWidget);
      final femaleBtn = find.descendant(
        of: genderRoot,
        matching: find.textContaining('女性'),
      );
      expect(femaleBtn, findsAtLeastNWidgets(1));
      await tester.ensureVisible(femaleBtn.first);
      await tester.tap(femaleBtn.first);
      await tester.pumpAndSettle();
      await tapKey(tester, 'btn_save_profile');

      await tapNavTab(tester, 'nav_tab_custom');
      expect(
        find.descendant(
          of: find.byKey(const Key('purpose_selector')),
          matching: find.textContaining('ボディーメイク（女性向け）'),
        ),
        findsAtLeastNWidgets(1),
      );

      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final profile = await repo.loadProfile();
      final states = await repo.loadMuscleStates();
      expect(profile!.gender, Gender.female);
      expect(profile.purpose, TrainingPurpose.bodyMakeFemale);
      expect(states['m5']!.priorityP, 18); // 中臀筋: female 18 vs male 10
      expect(states['m3']!.priorityP, 10); // 大胸筋中部: female 10 vs male 18
    });

    testWidgets('T3-13 (F11 x F6 x F8): Screen C birthYear 1960 (60_plus) & 55kg -> A2 scales 0.65 & shifts 10->12 / 12->15 reps', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_settings');
      await enterTextByKey(tester, 'birth_year_input', '1960');
      await enterTextByKey(tester, 'body_weight_input', '55');
      await tapKey(tester, 'btn_save_profile');

      await tapNavTab(tester, 'nav_tab_training');
      await tapKey(tester, 'course_standard');
      await tapKey(tester, 'btn_start_workout');

      final title = _extractText(tester, 'exercise_title');
      final spec = _specByExerciseTitle(title);

      final expectedW = oracleRoundTo25(55.0 * spec.bwFactor * 1.0 * 1.0 * 0.65);
      final expectedReps = spec.baseReps == 10
          ? 12
          : (spec.baseReps == 12 ? 15 : spec.baseReps);

      expect(
        _extractText(tester, 'card_weight'),
        contains(_formatWeightKg(expectedW)),
      );
      expect(
        _extractText(tester, 'card_reps'),
        contains('$expectedReps 回'),
      );
    });

    testWidgets('T3-14 (F11 x F12): Screen C local Google login + profile save persists across cold restart', (tester) async {
      expect(SupabaseConfig.isConfigured, isFalse);

      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_settings');
      await tapKey(tester, 'btn_google_login');
      expect(find.byKey(const Key('btn_logout')), findsOneWidget);

      final femaleBtn = find.descendant(
        of: find.byKey(const Key('gender_selector')),
        matching: find.textContaining('女性'),
      );
      await tester.ensureVisible(femaleBtn.first);
      await tester.tap(femaleBtn.first);
      await tester.pumpAndSettle();

      final intermediateBtn = find.descendant(
        of: find.byKey(const Key('experience_selector')),
        matching: find.textContaining('中級'),
      );
      await tester.ensureVisible(intermediateBtn.first);
      await tester.tap(intermediateBtn.first);
      await tester.pumpAndSettle();

      await enterTextByKey(tester, 'birth_year_input', '1988');
      await enterTextByKey(tester, 'body_weight_input', '58');
      await tapKey(tester, 'btn_save_profile');

      // Cold restart without clearing SharedPreferences
      await restartNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_settings');
      expect(find.byKey(const Key('btn_logout')), findsOneWidget);
      expect(find.textContaining('1988'), findsAtLeastNWidgets(1));

      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final restored = await repo.loadProfile();
      expect(restored, isNotNull);
      expect(restored!.gender, Gender.female);
      expect(restored.experience, ExperienceLevel.intermediate);
      expect(restored.birthYear, 1988);
      expect(restored.bodyWeightKg, 58.0);
    });

    testWidgets('T3-15 (F10 x F12): Screen B purpose & injury edits persist across cold restart and affect A1->A2', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_custom');
      await selectOptionInControl(tester, 'purpose_selector', '健康維持');
      await tapKey(tester, 'injury_toggle_m0');
      await tapKey(tester, 'injury_toggle_m3');

      await restartNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_custom');
      expect(
        find.descendant(
          of: find.byKey(const Key('purpose_selector')),
          matching: find.textContaining('健康維持'),
        ),
        findsAtLeastNWidgets(1),
      );

      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final restoredProfile = await repo.loadProfile();
      final restoredStates = await repo.loadMuscleStates();
      expect(restoredProfile!.purpose, TrainingPurpose.health);
      expect(restoredStates['m0']!.isInjured, isTrue);
      expect(restoredStates['m3']!.isInjured, isTrue);

      // Verify A1->A2 after restart excludes all m0 & m3 machines
      await tapNavTab(tester, 'nav_tab_training');
      await tapKey(tester, 'course_standard');
      await tapKey(tester, 'btn_start_workout');
      final titles = await _collectAndCompleteA2Exercises(tester, 4);
      final forbiddenNames = <String>{
        for (final m in kExpectedMachineSpecs)
          if (m.primaryMuscleIds.contains('m0') ||
              m.synergistMuscleIds.contains('m0') ||
              m.primaryMuscleIds.contains('m3') ||
              m.synergistMuscleIds.contains('m3'))
            m.name,
      };
      for (final t in titles) {
        expect(forbiddenNames.any((n) => t.contains(n)), isFalse);
      }
    });

    testWidgets('T3-16 (F9 x F12): Screen A3 finish atomically persists session, machineHistory, muscleStates & sessionCount', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockEvening1800),
      );

      final repoBefore = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final beforeCount = await repoBefore.loadSessionCount();

      await tapKey(tester, 'course_short');
      await tapKey(tester, 'btn_start_workout');
      final completedTitles = await _collectAndCompleteA2Exercises(tester, 2);
      final completedIds = completedTitles
          .map((t) => _specByExerciseTitle(t).id)
          .toList();

      await tapKey(tester, 'feedback_too_hard');
      await tapKey(tester, 'btn_finish_workout');

      // Cold restart and inspect persisted repository state
      await restartNoukinApp(
        tester,
        clock: fixedClock(kClockEvening1800),
      );

      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final sessions = await repo.loadSessionHistory();
      final count = await repo.loadSessionCount();
      final machineHist = await repo.loadMachineHistory();
      final muscleStates = await repo.loadMuscleStates();

      expect(sessions, hasLength(1));
      expect(sessions.first.durationCourse, WorkoutDurationCourse.short20);
      expect(sessions.first.timeSlot, TimeSlot.evening);
      expect(sessions.first.feedback, WorkoutFeedback.tooHard);
      expect(
        sessions.first.exercises.map((e) => e.machineId).toList(),
        completedIds,
      );
      expect(count, beforeCount + 1);

      for (final macId in completedIds) {
        expect(machineHist[macId]!.sessionsSinceUsed, 0);
        expect(machineHist[macId]!.lastFeedback, WorkoutFeedback.tooHard);
        expect(machineHist[macId]!.lastWeightKg, isNotNull);
        for (final pId in kExpectedMachineSpecById[macId]!.primaryMuscleIds) {
          expect(muscleStates[pId]!.blankDays, 1);
          expect(muscleStates[pId]!.stimulationDays, greaterThan(2.0));
        }
      }
    });

    test('T3-17 (F3 x F4 x F5): mac23 with sessionsSinceUsed=15 overcomes compounds at step=0', () {
      final profile = buildTestProfile();
      final states = buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale);

      final highRotHistory = buildDefaultMachineHistory(
        overrides: const <String, MachineHistoryEntry>{
          'mac23': MachineHistoryEntry(
            machineId: 'mac23',
            sessionsSinceUsed: 15,
          ),
        },
      );

      final resultHigh = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: highRotHistory,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );
      // mac23: prim=18.0, syn=(10+10)/2*0.3=3.0, rot(15)=23.5, str=4.0 -> 48.5
      expect(resultHigh.exercises.first.machine.id, 'mac23');
      expect(resultHigh.exercises.first.rawScore, closeTo(48.5, 1e-6));
      expect(resultHigh.exercises.first.finalScore, closeTo(48.5, 1e-6));

      // With default n=6 (rot=5.0, str=0.0 -> 26.0), mac23 loses to compounds at step 0.
      final defaultResult = generator.generateMenu(
        profile: profile,
        muscleStates: states,
        machineHistory: buildDefaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: kClockDaytime1300,
        sessionCount: 1,
      );
      expect(defaultResult.exercises.first.machine.id, isNot('mac23'));
    });

    test('T3-18 (F2 x F5): Core P_i=0 excludes mac27/mac28 while mac29 synergists retain synMVal (P_syn=6)', () {
      final profile = buildTestProfile();
      final history = buildDefaultMachineHistory();

      // Case A: Non-m9 core muscles P_i=0 -> mac27 & mac28 excluded, mac29 eligible with synMVal=6.0 on m52/m53
      final partialCoreZeroOverrides = <String, MuscleInputState>{
        for (final m in kExpectedMuscleSpecs)
          if (m.group == MuscleGroup.core && m.id != 'm9')
            m.id: MuscleInputState(
              muscleId: m.id,
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
      };
      final partialStates = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: partialCoreZeroOverrides,
      );
      final partialMenu = generator.generateMenu(
        profile: profile,
        muscleStates: partialStates,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: kClockMorning0800,
      );
      expect(partialMenu.muscleScores['m52']!.mVal, 0.0);
      expect(partialMenu.muscleScores['m52']!.synMVal, 6.0);
      expect(partialMenu.muscleScores['m53']!.mVal, 0.0);
      expect(partialMenu.muscleScores['m53']!.synMVal, 6.0);
      final partialIds = partialMenu.exercises.map((e) => e.machine.id).toSet();
      expect(partialIds, isNot(contains('mac27')));
      expect(partialIds, isNot(contains('mac28')));

      // Case B: ALL 9 core muscles (including m9) P_i=0 -> mac27, mac28, mac29 all excluded,
      // yet m9/m52/m53 retain synMVal via P_syn=6 for synergist scoring.
      final allCoreZeroOverrides = <String, MuscleInputState>{
        for (final m in kExpectedMuscleSpecs)
          if (m.group == MuscleGroup.core)
            m.id: MuscleInputState(
              muscleId: m.id,
              blankDays: 4,
              stimulationDays: 2.0,
              priorityP: 0,
            ),
      };
      final allCoreZeroStates = buildDefaultMuscleStates(
        TrainingPurpose.bodyMakeMale,
        overrides: allCoreZeroOverrides,
      );
      final allZeroMenu = generator.generateMenu(
        profile: profile,
        muscleStates: allCoreZeroStates,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: kClockMorning0800,
      );
      expect(allZeroMenu.muscleScores['m9']!.mVal, 0.0);
      expect(allZeroMenu.muscleScores['m9']!.synMVal, 5.0);
      expect(allZeroMenu.muscleScores['m52']!.synMVal, 6.0);
      final allZeroIds = allZeroMenu.exercises.map((e) => e.machine.id).toSet();
      expect(allZeroIds, isNot(contains('mac27')));
      expect(allZeroIds, isNot(contains('mac28')));
      expect(allZeroIds, isNot(contains('mac29')));
    });

    testWidgets('T3-19 (F4 x F7 x F8): Same state at 08:00 vs 22:00 changes A1 badge & A2 first exercise', (tester) async {
      // Morning 08:00
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockMorning0800),
      );
      expect(_extractText(tester, 'detected_timeslot_badge'), contains('朝'));
      await tapKey(tester, 'course_short');
      await tapKey(tester, 'btn_start_workout');
      final morningFirstTitle = _extractText(tester, 'exercise_title');
      expect(morningFirstTitle, contains('チェストサポート式Tバーロウ'));

      // Night 22:00 with identical fresh default state
      await pumpNoukinApp(
        tester,
        clock: fixedClock(DateTime(2026, 11, 19, 22, 0)),
      );
      expect(_extractText(tester, 'detected_timeslot_badge'), contains('就寝前'));
      await tapKey(tester, 'course_short');
      await tapKey(tester, 'btn_start_workout');
      final nightFirstTitle = _extractText(tester, 'exercise_title');
      expect(nightFirstTitle, contains('サイドレイズマシン'));

      expect(nightFirstTitle, isNot(morningFirstTitle));
    });

    testWidgets('T3-20 (F1 x F11 x F12): tennis purpose survives gender toggle in Screen C & persists across restart', (tester) async {
      await pumpNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      // Set purpose to tennis on Screen B
      await tapNavTab(tester, 'nav_tab_custom');
      await selectOptionInControl(tester, 'purpose_selector', 'テニス');

      // Flip gender to female on Screen C
      await tapNavTab(tester, 'nav_tab_settings');
      final femaleBtn = find.descendant(
        of: find.byKey(const Key('gender_selector')),
        matching: find.textContaining('女性'),
      );
      await tester.ensureVisible(femaleBtn.first);
      await tester.tap(femaleBtn.first);
      await tester.pumpAndSettle();
      await tapKey(tester, 'btn_save_profile');

      // Screen B must retain tennis (not overwritten by bodyMakeFemale)
      await tapNavTab(tester, 'nav_tab_custom');
      expect(
        find.descendant(
          of: find.byKey(const Key('purpose_selector')),
          matching: find.textContaining('テニス'),
        ),
        findsAtLeastNWidgets(1),
      );

      // Restart app and confirm both female gender and tennis purpose persisted
      await restartNoukinApp(
        tester,
        clock: fixedClock(kClockDaytime1300),
      );

      await tapNavTab(tester, 'nav_tab_custom');
      expect(
        find.descendant(
          of: find.byKey(const Key('purpose_selector')),
          matching: find.textContaining('テニス'),
        ),
        findsAtLeastNWidgets(1),
      );

      final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
      final restored = await repo.loadProfile();
      expect(restored!.gender, Gender.female);
      expect(restored.purpose, TrainingPurpose.tennis);
    });
  });
}
