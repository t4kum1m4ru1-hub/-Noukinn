import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/controllers/training_session_controller.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/screens/review_screen.dart';
import 'package:noukin/screens/training_flow_screen.dart';
import 'package:noukin/screens/training_pre_screen.dart';
import 'package:noukin/screens/training_screen.dart';
import 'package:noukin/theme/app_colors.dart';
import 'package:noukin/theme/app_theme.dart';

void main() {
  const defaultProfile = UserProfile(
    id: 'test-user',
    gender: Gender.male,
    birthYear: 1995,
    experience: ExperienceLevel.beginner,
    bodyWeightKg: 70.0,
    purpose: TrainingPurpose.bodyMakeMale,
    isFirstTime: true,
  );

  Map<String, MuscleInputState> buildDefaultStates({bool allInjured = false}) {
    final base = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
    if (!allInjured) return base;
    return base.map(
      (id, state) => MapEntry(id, state.copyWith(isInjured: true)),
    );
  }

  Map<String, MachineHistoryEntry> buildDefaultHistory() =>
      MasterData.defaultMachineHistory();

  Future<void> pumpFlow(
    WidgetTester tester, {
    Size surfaceSize = const Size(390, 844),
    UserProfile profile = defaultProfile,
    Map<String, MuscleInputState>? muscleStates,
    Map<String, MachineHistoryEntry>? machineHistory,
    int sessionCount = 1,
    DateTime Function()? clock,
    ValueChanged<MenuGenerationResult>? onMenuGenerated,
    FutureOr<void> Function(WorkoutCompletionResult result)? onWorkoutCompleted,
    bool wrapWithNavigationBar = false,
  }) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final flow = TrainingFlowScreen(
      profile: profile,
      muscleStates: muscleStates ?? buildDefaultStates(),
      machineHistory: machineHistory ?? buildDefaultHistory(),
      sessionCount: sessionCount,
      clock: clock ?? () => DateTime(2026, 11, 20, 18, 0),
      onMenuGenerated: onMenuGenerated,
      onWorkoutCompleted: onWorkoutCompleted,
    );

    final home = wrapWithNavigationBar
        ? Scaffold(
            body: flow,
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                  key: Key('nav_tab_training'),
                  icon: Icon(Icons.fitness_center),
                  label: 'トレーニング',
                ),
                NavigationDestination(
                  key: Key('nav_tab_custom'),
                  icon: Icon(Icons.tune),
                  label: 'カスタム',
                ),
                NavigationDestination(
                  key: Key('nav_tab_settings'),
                  icon: Icon(Icons.settings),
                  label: '設定',
                ),
              ],
            ),
          )
        : flow;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapWithScroll(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void expectNoR1ViolationsInWidgetTree(WidgetTester tester) {
    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const Key('card_volume')), findsNothing);
    expect(find.byKey(const Key('volume_slider')), findsNothing);
    expect(find.byKey(const Key('volume_value_text')), findsNothing);
    expect(find.byKey(const Key('media_control_bar')), findsNothing);
    expect(find.byKey(const Key('training_mode_indicator')), findsNothing);
    expect(find.byKey(const Key('btn_media_prev')), findsNothing);
    expect(find.byKey(const Key('btn_media_play_pause')), findsNothing);
    expect(find.byKey(const Key('btn_media_next')), findsNothing);
    expect(find.byKey(const Key('btn_media_vol_down')), findsNothing);
    expect(find.byKey(const Key('btn_media_vol_up')), findsNothing);
    expect(find.textContaining('Gym AI'), findsNothing);
    expect(find.textContaining('button_controll_test'), findsNothing);
    expect(find.textContaining('音声ガイド'), findsNothing);
    expect(find.textContaining('チュートリアル'), findsNothing);
    expect(find.textContaining('状態A'), findsNothing);
    expect(find.textContaining('状態B'), findsNothing);
    expect(find.textContaining('状態C'), findsNothing);
    expect(find.textContaining('時間帯を変更'), findsNothing);
    expect(find.textContaining('14日'), findsNothing);
    expect(find.textContaining('0.75'), findsNothing);
    expect(find.textContaining('0.45'), findsNothing);
  }

  group('1. TrainingSessionController unit behavior', () {
    test('formats weights without trailing .0 and clamps lower bounds', () {
      expect(TrainingSessionController.formatWeightNumber(60.0), '60');
      expect(TrainingSessionController.formatWeightNumber(62.5), '62.5');
      expect(TrainingSessionController.formatWeightNumber(2.5), '2.5');

      final ex1 = PrescribedExercise(
        machine: MasterData.machines[0],
        weightKg: 5.0,
        reps: 2,
        sets: 2,
        primaryMuscleNames: const ['大腿四頭筋'],
        synergistMuscleNames: const ['大臀筋'],
      );
      final ex2 = PrescribedExercise(
        machine: MasterData.machines[10],
        weightKg: 40.0,
        reps: 10,
        sets: 3,
        primaryMuscleNames: const ['大胸筋'],
        synergistMuscleNames: const ['上腕三頭筋'],
      );

      final controller = TrainingSessionController.fromExercises(
        exercises: [ex1, ex2],
      );
      addTearDown(controller.dispose);

      expect(controller.progressText, '1 / 2');
      expect(controller.formattedWeightDisplay, '5 kg');

      controller.adjustWeight(-2.5);
      expect(controller.formattedWeightDisplay, '2.5 kg');
      controller.adjustWeight(-2.5);
      expect(controller.weightKg, 2.5);

      controller.adjustReps(-1);
      expect(controller.reps, 1);
      controller.adjustReps(-1);
      expect(controller.reps, 1);

      controller.adjustSets(-1);
      expect(controller.sets, 1);
      controller.adjustSets(-1);
      expect(controller.sets, 1);

      // Self-swap & out-of-range swap are no-ops
      controller.swapExercise(0);
      controller.swapExercise(-1);
      controller.swapExercise(99);
      expect(controller.currentExercise.machine.id, ex1.machine.id);

      // Valid swap exchanges in-place while keeping index 0
      controller.swapExercise(1);
      expect(controller.currentIndex, 0);
      expect(controller.currentExercise.machine.id, ex2.machine.id);
      expect(controller.exercises[1].machine.id, ex1.machine.id);
      expect(controller.exercises[1].weightKg, 2.5);
    });

    test('sanitizes non-finite initial weightKg (NaN / Infinity) on adjustWeight', () {
      final ctrlNan = TrainingSessionController.fromExercises(
        exercises: [
          PrescribedExercise(
            machine: MasterData.machines[0],
            weightKg: double.nan,
            reps: 10,
            sets: 3,
            primaryMuscleNames: const ['大腿四頭筋'],
            synergistMuscleNames: const ['大臀筋'],
          ),
        ],
      );
      addTearDown(ctrlNan.dispose);
      ctrlNan.adjustWeight(2.5);
      expect(ctrlNan.weightKg.isFinite, isTrue);
      expect(ctrlNan.weightKg, greaterThanOrEqualTo(2.5));
      expect(ctrlNan.toCompletedRecords().first.weightKg.isFinite, isTrue);

      final ctrlInf = TrainingSessionController.fromExercises(
        exercises: [
          PrescribedExercise(
            machine: MasterData.machines[0],
            weightKg: double.infinity,
            reps: 10,
            sets: 3,
            primaryMuscleNames: const ['大腿四頭筋'],
            synergistMuscleNames: const ['大臀筋'],
          ),
        ],
      );
      addTearDown(ctrlInf.dispose);
      ctrlInf.adjustWeight(2.5);
      expect(ctrlInf.weightKg.isFinite, isTrue);
      expect(ctrlInf.weightKg, greaterThanOrEqualTo(2.5));
      expect(ctrlInf.toCompletedRecords().first.weightKg.isFinite, isTrue);

      final ctrlNeg = TrainingSessionController.fromExercises(
        exercises: [
          PrescribedExercise(
            machine: MasterData.machines[0],
            weightKg: double.nan,
            reps: 10,
            sets: 3,
            primaryMuscleNames: const ['大腿四頭筋'],
            synergistMuscleNames: const ['大臀筋'],
          ),
        ],
      );
      addTearDown(ctrlNeg.dispose);
      ctrlNeg.adjustWeight(-2.5);
      expect(ctrlNeg.weightKg.isFinite, isTrue);
      expect(ctrlNeg.weightKg, 2.5);
    });

    test('sanitizes NaN/Infinity/<=0 weightKg and <1 reps/sets immediately on construction', () {
      expect(TrainingSessionController.formatWeightNumber(double.nan), '2.5');
      expect(TrainingSessionController.formatWeightNumber(double.infinity), '2.5');
      expect(TrainingSessionController.formatWeightNumber(0.0), '2.5');
      expect(TrainingSessionController.formatWeightNumber(-5.0), '2.5');
      expect(TrainingSessionController.formatWeightNumber(1.5), '1.5');

      for (final badWeight in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0.0,
        -5.0,
      ]) {
        final ctrl = TrainingSessionController.fromExercises(
          exercises: [
            PrescribedExercise(
              machine: MasterData.machines[0],
              weightKg: badWeight,
              reps: 0,
              sets: 0,
              primaryMuscleNames: const ['大腿四頭筋'],
              synergistMuscleNames: const ['大臀筋'],
            ),
          ],
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.weightKg, 2.5, reason: 'badWeight=$badWeight');
        expect(ctrl.formattedWeightDisplay, '2.5 kg', reason: 'badWeight=$badWeight');
        expect(ctrl.reps, 1);
        expect(ctrl.sets, 1);
        expect(ctrl.currentExercise.weightKg, 2.5);
        expect(ctrl.updatedPrescribedExercises.first.weightKg, 2.5);
        final record = ctrl.toCompletedRecords().first;
        expect(record.weightKg, 2.5);
        expect(record.reps, 1);
        expect(record.sets, 1);
      }
    });
  });

  group('2. Full A1 -> A2 -> Swap -> ± Edits -> A3 -> Save -> Return to A1', () {
    testWidgets('completes full journey and persists swapped/edited records', (
      WidgetTester tester,
    ) async {
      MenuGenerationResult? generatedMenu;
      WorkoutCompletionResult? completionResult;

      await pumpFlow(
        tester,
        clock: () => DateTime(2026, 11, 20, 18, 30),
        onMenuGenerated: (menu) => generatedMenu = menu,
        onWorkoutCompleted: (result) => completionResult = result,
      );

      expectNoR1ViolationsInWidgetTree(tester);
      expect(find.byKey(const Key('detected_timeslot_badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('detected_timeslot_badge')),
          matching: find.text('夕方'),
        ),
        findsOneWidget,
      );

      // Select short course (2 exercises) + great condition
      await tapWithScroll(tester, find.byKey(const Key('course_short')));
      await tapWithScroll(tester, find.byKey(const Key('condition_great')));
      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));

      expect(generatedMenu, isNotNull);
      expect(generatedMenu!.exercises.length, 2);
      final originalFirst = generatedMenu!.exercises[0];
      final originalSecond = generatedMenu!.exercises[1];

      // A2 Screen verification
      expect(find.byType(TrainingScreen), findsOneWidget);
      expectNoR1ViolationsInWidgetTree(tester);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, AppColors.surface);
      expect(appBar.elevation, 0);

      final titleText = tester.widget<Text>(
        find.byKey(const Key('exercise_title')),
      );
      expect(titleText.data, originalFirst.machine.name);

      final progressText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('exercise_progress_badge')),
          matching: find.textContaining('1 / 2'),
        ),
      );
      expect(progressText.data, contains('1 / 2'));

      expect(find.byKey(const Key('target_muscles_badge')), findsOneWidget);
      expect(find.textContaining('〇'), findsAtLeastNWidgets(1));
      expect(find.textContaining('△'), findsAtLeastNWidgets(1));

      // Card styling checks
      final weightCard = tester.widget<Card>(
        find.byKey(const Key('card_weight')),
      );
      expect(weightCard.color, AppColors.surface);
      final weightValueText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('card_weight')),
          matching: find.textContaining('kg'),
        ),
      );
      expect(weightValueText.style?.color, AppColors.tealAccent);

      // Initial CTA is '開始' -> tap once -> '次へ'
      expect(find.text('開始'), findsOneWidget);
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      expect(find.text('次へ'), findsOneWidget);

      // Open swap sheet and verify self-swap no-op first
      await tester.tap(find.byKey(const Key('btn_select_exercise')));
      await tester.pumpAndSettle();
      expect(find.textContaining('種目変更'), findsOneWidget);
      expect(find.byKey(const Key('swap_exercise_option_0')), findsOneWidget);
      expect(find.byKey(const Key('swap_exercise_option_1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('swap_exercise_option_0')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('exercise_title'))).data,
        originalFirst.machine.name,
      );

      // Swap index 0 with index 1
      await tester.tap(find.byKey(const Key('btn_select_exercise')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('swap_exercise_option_1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('exercise_title'))).data,
        originalSecond.machine.name,
      );
      expect(find.textContaining('1 / 2'), findsOneWidget);

      // Adjust weight (+2.5), reps (+1), sets (-1) on swapped first exercise
      await tapWithScroll(tester, find.byKey(const Key('btn_weight_up')));
      await tapWithScroll(tester, find.byKey(const Key('btn_reps_up')));
      await tapWithScroll(tester, find.byKey(const Key('btn_sets_down')));

      final expectedWeight = double.parse(
        (originalSecond.weightKg + 2.5).toStringAsFixed(1),
      );
      final expectedWeightLabel =
          '${TrainingSessionController.formatWeightNumber(expectedWeight)} kg';
      expect(
        find.descendant(
          of: find.byKey(const Key('card_weight')),
          matching: find.text(expectedWeightLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('card_reps')),
          matching: find.text('${originalSecond.reps + 1} 回'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('card_sets')),
          matching: find.text('${originalSecond.sets - 1} セット'),
        ),
        findsOneWidget,
      );

      // Advance to exercise 2 / 2
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      expect(
        tester.widget<Text>(find.byKey(const Key('exercise_title'))).data,
        originalFirst.machine.name,
      );
      expect(find.textContaining('2 / 2'), findsOneWidget);

      // Exercise 2 must retain its own unedited weight/reps/sets
      expect(
        find.descendant(
          of: find.byKey(const Key('card_weight')),
          matching: find.text(
            '${TrainingSessionController.formatWeightNumber(originalFirst.weightKg)} kg',
          ),
        ),
        findsOneWidget,
      );

      // Complete workout -> pushes Screen A3
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      expect(find.byType(ReviewScreen), findsOneWidget);
      expectNoR1ViolationsInWidgetTree(tester);

      // Finish button is disabled initially
      final initialBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_finish_workout')),
      );
      expect(initialBtn.onPressed, isNull);

      // Select '軽すぎた（次回+2.5kg）' -> enabled
      await tapWithScroll(tester, find.byKey(const Key('feedback_too_light')));
      final enabledBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_finish_workout')),
      );
      expect(enabledBtn.onPressed, isNotNull);

      await tapWithScroll(tester, find.byKey(const Key('btn_finish_workout')));

      // Returned to Screen A1 cleanly
      expect(find.byType(TrainingPreScreen), findsOneWidget);
      expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
      expect(find.byKey(const Key('btn_finish_workout')), findsNothing);
      expect(find.byKey(const Key('exercise_title')), findsNothing);

      // Verify persisted completion payload
      expect(completionResult, isNotNull);
      final record = completionResult!.sessionRecord;
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(record.id),
        isTrue,
      );
      expect(record.durationCourse, WorkoutDurationCourse.short20);
      expect(record.condition, WorkoutCondition.great);
      expect(record.timeSlot, TimeSlot.evening);
      expect(record.feedback, WorkoutFeedback.tooLight);
      expect(record.exercises.length, 2);
      expect(record.exercises.first.machineId, originalSecond.machine.id);
      expect(record.exercises.first.machineName, originalSecond.machine.name);
      expect(record.exercises.first.weightKg, expectedWeight);
      expect(record.exercises.first.reps, originalSecond.reps + 1);
      expect(record.exercises.first.sets, originalSecond.sets - 1);

      expect(completionResult!.advanceResult.sessionCount, 2);
      final hist = completionResult!
          .advanceResult
          .machineHistory[originalSecond.machine.id]!;
      expect(hist.lastWeightKg, expectedWeight);
      expect(hist.lastFeedback, WorkoutFeedback.tooLight);
      expect(hist.sessionsSinceUsed, 0);
      for (final mId in originalSecond.machine.primaryMuscleIds) {
        expect(
          completionResult!.advanceResult.muscleStates[mId]!.blankDays,
          1,
        );
      }
    });
  });

  group('3. Screen A1 edge cases (clock, dropdown, tired, empty menu)', () {
    testWidgets('displays only active timeSlot badge for all 4 slots', (
      WidgetTester tester,
    ) async {
      final cases = <DateTime, String>{
        DateTime(2026, 11, 20, 8, 0): '朝',
        DateTime(2026, 11, 20, 13, 0): '日中',
        DateTime(2026, 11, 20, 18, 0): '夕方',
        DateTime(2026, 11, 20, 22, 30): '就寝前',
      };
      final allLabels = <String>['朝', '日中', '夕方', '就寝前'];

      for (final entry in cases.entries) {
        await pumpFlow(tester, clock: () => entry.key);
        final badge = find.byKey(const Key('detected_timeslot_badge'));
        expect(badge, findsOneWidget);
        expect(
          find.descendant(of: badge, matching: find.text(entry.value)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: badge,
            matching: find.byType(DropdownButton<TimeSlot>),
          ),
          findsNothing,
        );
        for (final other in allLabels.where((l) => l != entry.value)) {
          expect(find.text(other), findsNothing);
        }
        expect(find.textContaining('時間帯を変更'), findsNothing);
      }
    });

    testWidgets('focus_muscle_dropdown selects a muscle and resets to 指定なし', (
      WidgetTester tester,
    ) async {
      MenuGenerationResult? latestMenu;

      await pumpFlow(
        tester,
        onMenuGenerated: (menu) => latestMenu = menu,
      );

      // Select a specific muscle
      await tapWithScroll(
        tester,
        find.byKey(const Key('focus_muscle_dropdown')),
      );
      await tester.tap(find.textContaining('上腕二頭筋').last);
      await tester.pumpAndSettle();

      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));
      expect(latestMenu, isNotNull);
      expect(latestMenu!.focusMuscleId, isNotNull);
      expect(
        MasterData.muscleById[latestMenu!.focusMuscleId!]!.name,
        '上腕二頭筋',
      );

      // Back out to A1 and reset dropdown to 指定なし (null)
      await tester.tap(find.byKey(const Key('training_back_button')));
      await tester.pumpAndSettle();

      await tapWithScroll(
        tester,
        find.byKey(const Key('focus_muscle_dropdown')),
      );
      await tester.tap(find.text('指定なし').last);
      await tester.pumpAndSettle();

      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));
      expect(latestMenu!.focusMuscleId, isNull);
    });

    testWidgets('condition_tired prescribes 2 sets and -5% weight', (
      WidgetTester tester,
    ) async {
      MenuGenerationResult? tiredMenu;

      await pumpFlow(
        tester,
        onMenuGenerated: (menu) => tiredMenu = menu,
      );
      await tapWithScroll(tester, find.byKey(const Key('course_short')));
      await tapWithScroll(tester, find.byKey(const Key('condition_tired')));
      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));

      expect(tiredMenu, isNotNull);
      expect(tiredMenu!.exercises.first.sets, 2);
      expect(find.textContaining('2 セット'), findsAtLeastNWidgets(1));

      // Verify -5% weight on the same prescribed machine compared to normal
      final firstMachine = tiredMenu!.exercises.first.machine;
      final expectedNormalRaw = defaultProfile.bodyWeightKg *
          firstMachine.bwFactor *
          defaultProfile.gender.firstTimeWeightFactor *
          defaultProfile.experience.firstTimeWeightFactor;
      final expectedNormalRounded =
          ((expectedNormalRaw / 2.5).round() * 2.5).clamp(2.5, double.infinity);
      final expectedTired =
          (((expectedNormalRounded * 0.95) / 2.5).round() * 2.5)
              .clamp(2.5, double.infinity);
      expect(tiredMenu!.exercises.first.weightKg, expectedTired);
    });

    testWidgets('all-injured empty menu stays on A1 with SnackBar and no crash', (
      WidgetTester tester,
    ) async {
      var menuCount = 0;
      var completedCount = 0;

      await pumpFlow(
        tester,
        muscleStates: buildDefaultStates(allInjured: true),
        onMenuGenerated: (_) => menuCount++,
        onWorkoutCompleted: (_) => completedCount++,
      );

      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));

      expect(tester.takeException(), isNull);
      expect(menuCount, 0);
      expect(completedCount, 0);
      expect(find.byType(TrainingPreScreen), findsOneWidget);
      expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
      expect(find.byKey(const Key('exercise_title')), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('TrainingPreScreen catches onStartWorkout exception, shows error SnackBar, and allows retry', (
      WidgetTester tester,
    ) async {
      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TrainingPreScreen(
            clock: () => DateTime(2026, 11, 20, 18, 0),
            onStartWorkout: ({
              required course,
              required condition,
              required focusMuscleId,
            }) async {
              attempts++;
              if (attempts == 1) {
                throw StateError('Simulated menu generation failure');
              }
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));
      expect(tester.takeException(), isNull);
      expect(attempts, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('メニューの生成に失敗しました。もう一度お試しください。'), findsOneWidget);

      final retryBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_start_workout')),
      );
      expect(retryBtn.onPressed, isNotNull);

      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));
      expect(tester.takeException(), isNull);
      expect(attempts, 2);
    });
  });

  group('4. Screen A2 & A3 guards (back abort, image fallback, double-tap)', () {
    testWidgets('training_back_button aborts without calling onWorkoutCompleted', (
      WidgetTester tester,
    ) async {
      var completed = false;
      await pumpFlow(
        tester,
        onWorkoutCompleted: (_) => completed = true,
      );

      await tapWithScroll(tester, find.byKey(const Key('course_short')));
      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));

      await tapWithScroll(tester, find.byKey(const Key('btn_weight_up')));
      await tester.tap(find.byKey(const Key('training_back_button')));
      await tester.pumpAndSettle();

      expect(completed, isFalse);
      expect(find.byType(TrainingPreScreen), findsOneWidget);
      expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
    });

    testWidgets('renders fallback Icons.fitness_center for null, missing, and .avif assets with zero FlutterError', (
      WidgetTester tester,
    ) async {
      final macAvif = MasterData.machineById['mac1']!; // leg_press.avif
      final macMissing = macAvif.copyWith(
        id: 'mac_missing',
        imageAssetPath: 'assets/images/workout/missing_asset.avif',
      );
      final macNull = MasterData.machineById['mac2']!; // imageAssetPath == null

      final controller = TrainingSessionController.fromExercises(
        exercises: [
          PrescribedExercise(
            machine: macAvif,
            weightKg: 80,
            reps: 10,
            sets: 3,
            primaryMuscleNames: const ['大腿四頭筋'],
            synergistMuscleNames: const ['大臀筋'],
          ),
          PrescribedExercise(
            machine: macMissing,
            weightKg: 70,
            reps: 10,
            sets: 3,
            primaryMuscleNames: const ['大腿四頭筋'],
            synergistMuscleNames: const ['大臀筋'],
          ),
          PrescribedExercise(
            machine: macNull,
            weightKg: 60,
            reps: 10,
            sets: 3,
            primaryMuscleNames: const ['ハムストリングス'],
            synergistMuscleNames: const ['大臀筋'],
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TrainingScreen(controller: controller),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      // mac1 (.avif): either engine decoded it into RawImage or errorBuilder showed fitness_center, with 0 FlutterErrors
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('exercise_image')), findsOneWidget);
      final hasDecodedOrFallback =
          find
              .descendant(
                of: find.byKey(const Key('exercise_image')),
                matching: find.byIcon(Icons.fitness_center),
              )
              .evaluate()
              .isNotEmpty ||
          find
              .descendant(
                of: find.byKey(const Key('exercise_image')),
                matching: find.byType(RawImage),
              )
              .evaluate()
              .isNotEmpty;
      expect(hasDecodedOrFallback, isTrue);

      // Advance to macMissing (missing asset -> errorBuilder must show Icons.fitness_center)
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('exercise_image')),
          matching: find.byIcon(Icons.fitness_center),
        ),
        findsOneWidget,
      );

      // Advance to mac2 (null imageAssetPath -> direct Icons.fitness_center fallback)
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('exercise_image')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('exercise_image')),
          matching: find.byIcon(Icons.fitness_center),
        ),
        findsOneWidget,
      );
    });

    testWidgets('btn_finish_workout is disabled before selection and guards rapid double-tap', (
      WidgetTester tester,
    ) async {
      var submitCount = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ReviewScreen(
            onSubmitFeedback: (_) {
              submitCount++;
              return completer.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tapping while disabled does nothing
      await tester.tap(find.byKey(const Key('btn_finish_workout')));
      await tester.pump();
      expect(submitCount, 0);

      // Select feedback and tap twice rapidly before completer finishes
      await tapWithScroll(tester, find.byKey(const Key('feedback_just_right')));
      await tester.tap(find.byKey(const Key('btn_finish_workout')));
      await tester.tap(find.byKey(const Key('btn_finish_workout')));
      await tester.pump();
      expect(submitCount, 1);

      completer.complete();
      await tester.pumpAndSettle();
      expect(submitCount, 1);
    });

    testWidgets('rapid double-tap on btn_finish_workout with microtask-completing onWorkoutCompleted saves only once', (
      WidgetTester tester,
    ) async {
      final completions = <WorkoutCompletionResult>[];

      await pumpFlow(
        tester,
        onWorkoutCompleted: (result) =>
            Future<void>.microtask(() => completions.add(result)),
      );

      await tapWithScroll(tester, find.byKey(const Key('course_short')));
      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));

      // '開始' -> '次へ' (ex 1) -> '次へ' (ex 2) -> A3
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      expect(find.byType(ReviewScreen), findsOneWidget);

      await tapWithScroll(tester, find.byKey(const Key('feedback_just_right')));
      final finishBtn = find.byKey(const Key('btn_finish_workout'));
      await tester.ensureVisible(finishBtn);
      await tester.pumpAndSettle();

      await tester.tap(finishBtn);
      await tester.tap(finishBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(completions, hasLength(1));
      expect(find.byType(TrainingPreScreen), findsOneWidget);
    });

    testWidgets('unmounting TrainingFlowScreen while A2 is pushed keeps controller alive without FlutterError', (
      WidgetTester tester,
    ) async {
      var showFlow = true;
      late StateSetter setHostState;
      MenuGenerationResult? generatedMenu;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return showFlow
                  ? TrainingFlowScreen(
                      profile: defaultProfile,
                      muscleStates: buildDefaultStates(),
                      machineHistory: buildDefaultHistory(),
                      clock: () => DateTime(2026, 11, 20, 18, 0),
                      onMenuGenerated: (menu) => generatedMenu = menu,
                    )
                  : const Scaffold(
                      body: Center(child: Text('Other Tab')),
                    );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapWithScroll(tester, find.byKey(const Key('course_short')));
      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));
      expect(find.byType(TrainingScreen), findsOneWidget);
      expect(generatedMenu, isNotNull);

      final initialWeight = generatedMenu!.exercises.first.weightKg;
      final expectedWeight = double.parse(
        (initialWeight + 2.5).toStringAsFixed(1),
      );
      final expectedWeightLabel =
          '${TrainingSessionController.formatWeightNumber(expectedWeight)} kg';

      // Unmount TrainingFlowScreen while A2 remains pushed on Navigator
      setHostState(() {
        showFlow = false;
      });
      await tester.pumpAndSettle();
      expect(find.byType(TrainingFlowScreen), findsNothing);
      expect(find.byType(TrainingScreen), findsOneWidget);

      // Interacting with A2 must not throw a disposed-controller FlutterError
      await tapWithScroll(tester, find.byKey(const Key('btn_weight_up')));
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('card_weight')),
          matching: find.text(expectedWeightLabel),
        ),
        findsOneWidget,
      );

      // Back button pops A2 cleanly with zero errors
      await tester.tap(find.byKey(const Key('training_back_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TrainingScreen), findsNothing);
      expect(find.text('Other Tab'), findsOneWidget);
    });

    testWidgets('lower clamps hold at 2.5 kg / 1 rep / 1 set in UI', (
      WidgetTester tester,
    ) async {
      final controller = TrainingSessionController.fromExercises(
        exercises: [
          PrescribedExercise(
            machine: MasterData.machines[1],
            weightKg: 5.0,
            reps: 2,
            sets: 2,
            primaryMuscleNames: const ['大腿四頭筋'],
            synergistMuscleNames: const ['大臀筋'],
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TrainingScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tapWithScroll(tester, find.byKey(const Key('btn_weight_down')));
        await tapWithScroll(tester, find.byKey(const Key('btn_reps_down')));
        await tapWithScroll(tester, find.byKey(const Key('btn_sets_down')));
      }

      expect(find.text('2.5 kg'), findsOneWidget);
      expect(find.text('1 回'), findsOneWidget);
      expect(find.text('1 セット'), findsOneWidget);
    });

    testWidgets('ReviewScreen catches onSubmitFeedback exception, shows error SnackBar, and allows retry', (
      WidgetTester tester,
    ) async {
      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ReviewScreen(
            onSubmitFeedback: (_) async {
              attempts++;
              if (attempts == 1) {
                throw StateError('Simulated persistence failure');
              }
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapWithScroll(tester, find.byKey(const Key('feedback_just_right')));
      await tapWithScroll(tester, find.byKey(const Key('btn_finish_workout')));

      expect(tester.takeException(), isNull);
      expect(attempts, 1);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('保存に失敗しました。もう一度お試しください。'), findsOneWidget);

      final retryBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_finish_workout')),
      );
      expect(retryBtn.onPressed, isNotNull);

      await tapWithScroll(tester, find.byKey(const Key('btn_finish_workout')));
      expect(tester.takeException(), isNull);
      expect(attempts, 2);
      final submittedBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_finish_workout')),
      );
      expect(submittedBtn.onPressed, isNull);
    });

    testWidgets('TrainingFlowScreen catches onWorkoutCompleted exception on A3, shows error SnackBar, and retries to A1', (
      WidgetTester tester,
    ) async {
      var attempts = 0;
      WorkoutCompletionResult? savedResult;

      await pumpFlow(
        tester,
        onWorkoutCompleted: (result) async {
          attempts++;
          if (attempts == 1) {
            throw Exception('Simulated DB save failure');
          }
          savedResult = result;
        },
      );

      await tapWithScroll(tester, find.byKey(const Key('course_short')));
      await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));

      // '開始' -> '次へ' (ex 1) -> '次へ' (ex 2) -> A3
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
      expect(find.byType(ReviewScreen), findsOneWidget);

      await tapWithScroll(tester, find.byKey(const Key('feedback_just_right')));
      await tapWithScroll(tester, find.byKey(const Key('btn_finish_workout')));

      expect(tester.takeException(), isNull);
      expect(attempts, 1);
      expect(savedResult, isNull);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('保存に失敗しました。もう一度お試しください。'), findsOneWidget);

      final retryBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_finish_workout')),
      );
      expect(retryBtn.onPressed, isNotNull);

      await tapWithScroll(tester, find.byKey(const Key('btn_finish_workout')));
      expect(tester.takeException(), isNull);
      expect(attempts, 2);
      expect(savedResult, isNotNull);
      expect(find.byType(TrainingPreScreen), findsOneWidget);
      expect(find.byType(ReviewScreen), findsNothing);
    });
  });

  group('5. Responsive layout & zero-overflow checks', () {
    for (final spec in <({String name, Size size, bool withNavBar})>[
      (name: '360x640 standalone', size: const Size(360, 640), withNavBar: false),
      (name: '360x640 with NavigationBar', size: const Size(360, 640), withNavBar: true),
      (name: '390x844', size: const Size(390, 844), withNavBar: false),
      (name: '1280x800', size: const Size(1280, 800), withNavBar: false),
    ]) {
      testWidgets('zero overflow across A1 -> A2 (5 items + swap sheet) -> A3 on ${spec.name}', (
        WidgetTester tester,
      ) async {
        await pumpFlow(
          tester,
          surfaceSize: spec.size,
          wrapWithNavigationBar: spec.withNavBar,
        );
        expect(tester.takeException(), isNull);

        await tapWithScroll(tester, find.byKey(const Key('course_full')));
        await tapWithScroll(tester, find.byKey(const Key('btn_start_workout')));
        expect(tester.takeException(), isNull);

        // Open 5-item swap sheet and verify no overflow
        await tester.tap(find.byKey(const Key('btn_select_exercise')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('swap_exercise_option_4')), findsOneWidget);

        await tester.tap(find.byKey(const Key('swap_exercise_option_1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Tap through 5 exercises ('開始' + 5x '次へ') -> A3
        for (var i = 0; i < 6; i++) {
          await tapWithScroll(tester, find.byKey(const Key('btn_next_workout')));
        }
        expect(find.byType(ReviewScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tapWithScroll(tester, find.byKey(const Key('feedback_too_hard')));
        await tapWithScroll(tester, find.byKey(const Key('btn_finish_workout')));
        expect(find.byType(TrainingPreScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('6. R1 static source hygiene check for M4 files', () {
    test('M4 files contain zero prohibited TTS/media/Gym AI symbols', () {
      final m4Files = <String>[
        'lib/controllers/training_session_controller.dart',
        'lib/screens/training_pre_screen.dart',
        'lib/screens/training_screen.dart',
        'lib/screens/review_screen.dart',
        'lib/screens/training_flow_screen.dart',
      ];
      final prohibited = <String>[
        'flutter_tts',
        'audio_session',
        'TtsService',
        'AudioDuckingController',
        'SoundEffectService',
        'ButtonAction',
        'KeyEventChannelDispatcher',
        'TutorialScreen',
        '_buildVolumeCard',
        '_buildMediaControlBar',
        'Gym AI',
        'button_controll_test',
      ];

      for (final relPath in m4Files) {
        final content = File(relPath).readAsStringSync();
        for (final token in prohibited) {
          expect(
            content.contains(token),
            isFalse,
            reason: '$relPath must not contain prohibited token "$token"',
          );
        }
      }
    });
  });
}
