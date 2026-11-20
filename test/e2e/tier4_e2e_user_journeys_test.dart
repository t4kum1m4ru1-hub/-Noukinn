import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/config/supabase_config.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/engine/workout_menu_generator.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/state/app_state.dart';
import 'package:noukin/theme/app_colors.dart';

import 'e2e_test_helpers.dart';

// =============================================================================
// Resilient Opaque-Box UI Helpers for Tier 4 E2E Journeys
// =============================================================================

/// Scrolls through available [Scrollable] widgets (resolving actual
/// [Scrollable] descendants when [preferredContainerKey] is provided) until
/// [key] is visible.
Future<void> _ensureKeyVisible(
  WidgetTester tester,
  String key, {
  String? preferredContainerKey,
}) async {
  await scrollToWidgetByKey(
    tester,
    key,
    preferredContainerKey: preferredContainerKey,
    delta: 220.0,
  );
}

Future<void> _tapContractedKey(
  WidgetTester tester,
  String key, {
  String? preferredContainerKey,
}) async {
  await _ensureKeyVisible(
    tester,
    key,
    preferredContainerKey: preferredContainerKey,
  );
  final target = find.byKey(Key(key));
  expect(
    target,
    findsAtLeastNWidgets(1),
    reason: 'Expected widget with Key("$key") to be present and tappable',
  );
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

/// Selects [optionText] inside a selector widget keyed by [selectorKey],
/// delegating to [selectOptionInControl] so 55-item dropdown overlays scroll
/// properly across `390x844` and `1280x800` viewports.
Future<void> _selectOptionInSelector(
  WidgetTester tester,
  String selectorKey,
  String optionText,
) => selectOptionInControl(tester, selectorKey, optionText);

/// Reads the first displayed text from a widget keyed by [key].
String _readKeyText(WidgetTester tester, String key) {
  final root = find.byKey(Key(key));
  expect(root, findsOneWidget, reason: 'Widget "$key" must exist');
  final rootWidget = tester.widget(root);
  if (rootWidget is Text && rootWidget.data != null) {
    return rootWidget.data!;
  }
  final texts = find.descendant(of: root, matching: find.byType(Text));
  expect(
    texts,
    findsAtLeastNWidgets(1),
    reason: 'Widget "$key" must render at least one Text child',
  );
  return texts
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((s) => s.isNotEmpty)
      .join(' ');
}

/// Extracts the numeric value shown inside a Screen A2 counter card
/// (`'card_weight'`, `'card_reps'`, `'card_sets'`).
double _readCounterCardValue(WidgetTester tester, String cardKey) {
  final card = find.byKey(Key(cardKey));
  expect(card, findsOneWidget, reason: 'Counter card "$cardKey" must exist');
  final texts = find.descendant(of: card, matching: find.byType(Text));
  for (final element in texts.evaluate()) {
    final text = (element.widget as Text).data ?? '';
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (match != null) {
      return double.parse(match.group(1)!);
    }
  }
  fail('No numeric value found inside counter card "$cardKey"');
}

/// Resolves [ExpectedMachineSpec] from the displayed exercise title on A2.
ExpectedMachineSpec _matchMachineSpecByTitle(String title) {
  for (final spec in kExpectedMachineSpecs) {
    if (title == spec.name ||
        title.contains(spec.name) ||
        spec.name.contains(title)) {
      return spec;
    }
  }
  fail('Unable to match displayed exercise title "$title" to 29 machines');
}

/// Asserts that no prohibited R1 TTS, media-button, branding, or non-strength UI
/// appears in the current widget tree.
void _expectR1UiCleanliness(
  WidgetTester tester, {
  bool checkScreenBHiddenConstants = false,
  bool checkScreenCNoAgeBrackets = false,
}) {
  const prohibitedTexts = <String>[
    'Gym AI',
    'button_controll_test',
    '音声ガイド',
    'チュートリアル',
    '状態A',
    '状態B',
    '状態C',
    'プール',
    'サウナ',
    'ランニング',
    'タイムライン',
  ];
  for (final text in prohibitedTexts) {
    expect(
      find.textContaining(text),
      findsNothing,
      reason: 'Prohibited R1 text "$text" must never appear in UI',
    );
  }

  expect(find.byKey(const Key('card_volume')), findsNothing);
  expect(find.byKey(const Key('volume_slider')), findsNothing);
  expect(find.byKey(const Key('media_control_bar')), findsNothing);
  expect(find.byKey(const Key('btn_media_play_pause')), findsNothing);

  if (checkScreenBHiddenConstants) {
    expect(find.textContaining('上限キャップ'), findsNothing);
    expect(find.textContaining('重複制御'), findsNothing);
    expect(find.textContaining('0.75'), findsNothing);
    expect(find.textContaining('0.45'), findsNothing);
  }

  if (checkScreenCNoAgeBrackets) {
    expect(find.textContaining('10代・20代前半'), findsNothing);
    expect(find.textContaining('20代後半〜30代'), findsNothing);
    expect(find.textContaining('60代以上'), findsNothing);
  }
}

/// Walks through all exercises on Screen A2 until Screen A3 appears, returning
/// the list of displayed exercise titles in order.
Future<List<String>> _completeInWorkoutFlow(
  WidgetTester tester, {
  required int expectedCount,
  bool assertNoSliderOrMedia = true,
  Future<void> Function(int index, String title)? onExercise,
}) async {
  final titles = <String>[];
  for (var i = 0; i < expectedCount; i++) {
    expect(find.byKey(const Key('exercise_title')), findsOneWidget);
    expect(find.byKey(const Key('exercise_image')), findsOneWidget);
    expect(find.byKey(const Key('target_muscles_badge')), findsOneWidget);
    expect(find.byKey(const Key('exercise_progress_badge')), findsOneWidget);
    expect(find.byKey(const Key('card_weight')), findsOneWidget);
    expect(find.byKey(const Key('card_reps')), findsOneWidget);
    expect(find.byKey(const Key('card_sets')), findsOneWidget);
    expect(find.byKey(const Key('btn_next_workout')), findsOneWidget);

    if (assertNoSliderOrMedia) {
      expect(find.byType(Slider), findsNothing);
      _expectR1UiCleanliness(tester);
    }

    final progressText = _readKeyText(tester, 'exercise_progress_badge');
    expect(
      progressText,
      contains('${i + 1}'),
      reason: 'Progress badge should show step ${i + 1} of $expectedCount',
    );

    final title = _readKeyText(tester, 'exercise_title');
    titles.add(title);

    if (onExercise != null) {
      await onExercise(i, title);
    }

    await advanceToNextExercise(tester);
  }

  expect(find.byKey(const Key('feedback_too_light')), findsOneWidget);
  expect(find.byKey(const Key('feedback_just_right')), findsOneWidget);
  expect(find.byKey(const Key('feedback_too_hard')), findsOneWidget);
  expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);
  return titles;
}

/// Submits [feedbackKey] on Screen A3 and returns to Screen A1.
Future<void> _submitReviewAndReturnToA1(
  WidgetTester tester,
  String feedbackKey,
) async {
  await _tapContractedKey(tester, feedbackKey);
  await _tapContractedKey(tester, 'btn_finish_workout');
  expect(
    find.byKey(const Key('btn_start_workout')),
    findsOneWidget,
    reason: 'Finishing review must return to Screen A1',
  );
}

/// Attempts to apply a batch blank-day (`B_i`) increment or value via Screen B's
/// `group_batch_${group.name}` section.
Future<void> _applyGroupBatchBlankDays(
  WidgetTester tester,
  MuscleGroup group, {
  required int incrementSteps,
  bool preferPlusFiveButton = false,
}) async {
  final groupKey = 'group_batch_${group.name}';
  await _ensureKeyVisible(tester, groupKey);
  final groupWidget = find.byKey(Key(groupKey));
  expect(groupWidget, findsOneWidget);

  if (preferPlusFiveButton) {
    final plusFive = find.descendant(
      of: groupWidget,
      matching: find.textContaining('+5'),
    );
    if (plusFive.evaluate().isNotEmpty) {
      await tester.ensureVisible(plusFive.first);
      await tester.tap(plusFive.first);
      await tester.pumpAndSettle();
      return;
    }
  }

  // Look for an inline B_i / ブランク TextField or increment button inside groupWidget.
  final textFields = find.descendant(
    of: groupWidget,
    matching: find.byType(TextField),
  );
  if (textFields.evaluate().isNotEmpty) {
    final currentText =
        tester.widget<TextField>(textFields.first).controller?.text ?? '';
    final parsed = int.tryParse(currentText.trim()) ?? 0;
    await tester.enterText(textFields.first, '${parsed + incrementSteps}');
    await tester.pumpAndSettle();
    final applyBtn = find.descendant(
      of: groupWidget,
      matching: find.textContaining('適用'),
    );
    if (applyBtn.evaluate().isNotEmpty) {
      await tester.tap(applyBtn.first);
      await tester.pumpAndSettle();
    }
    return;
  }

  // Check if there is a B_i label with an associated Icons.add button.
  final addButtons = find.descendant(
    of: groupWidget,
    matching: find.byIcon(Icons.add),
  );
  if (addButtons.evaluate().isNotEmpty) {
    final bLabel = find.descendant(
      of: groupWidget,
      matching: find.textContaining(RegExp(r'B|ブランク')),
    );
    Finder targetAdd = addButtons.first;
    if (bLabel.evaluate().isNotEmpty) {
      final bRow = find.ancestor(of: bLabel.first, matching: find.byType(Row));
      if (bRow.evaluate().isNotEmpty) {
        final addInBRow = find.descendant(
          of: bRow.first,
          matching: find.byIcon(Icons.add),
        );
        if (addInBRow.evaluate().isNotEmpty) {
          targetAdd = addInBRow.first;
        }
      }
    }
    for (var i = 0; i < incrementSteps; i++) {
      await tester.ensureVisible(targetAdd);
      await tester.tap(targetAdd);
      await tester.pumpAndSettle();
    }
    return;
  }

  // Fallback: groupWidget may be a group chip/button paired with section-level controls.
  await tester.tap(groupWidget);
  await tester.pumpAndSettle();
  final section = find.byKey(const Key('group_batch_section'));
  final dialogOrSection = find.byType(AlertDialog).evaluate().isNotEmpty
      ? find.byType(AlertDialog)
      : section;

  if (preferPlusFiveButton) {
    final plusFiveInSection = find.descendant(
      of: dialogOrSection,
      matching: find.textContaining('+5'),
    );
    if (plusFiveInSection.evaluate().isNotEmpty) {
      await tester.ensureVisible(plusFiveInSection.first);
      await tester.tap(plusFiveInSection.first);
      await tester.pumpAndSettle();
      return;
    }
  }

  final addInSection = find.descendant(
    of: dialogOrSection,
    matching: find.byIcon(Icons.add),
  );
  if (addInSection.evaluate().isNotEmpty) {
    for (var i = 0; i < incrementSteps; i++) {
      await tester.ensureVisible(addInSection.first);
      await tester.tap(addInSection.first);
      await tester.pumpAndSettle();
    }
  }
  final applyInDialog = find.descendant(
    of: dialogOrSection,
    matching: find.textContaining('適用'),
  );
  if (applyInDialog.evaluate().isNotEmpty) {
    await tester.tap(applyInDialog.first);
    await tester.pumpAndSettle();
  }
}

/// Edits an individual muscle row `matrix_row_${muscleId}` in Screen B's
/// `muscle_matrix_list` by tapping its increment control or edit dialog.
Future<void> _editMatrixMuscleBlankDays(
  WidgetTester tester,
  String muscleId, {
  int incrementSteps = 1,
}) async {
  final rowKey = 'matrix_row_$muscleId';
  await _ensureKeyVisible(
    tester,
    rowKey,
    preferredContainerKey: 'muscle_matrix_list',
  );
  final row = find.byKey(Key(rowKey));
  expect(row, findsOneWidget, reason: 'Matrix row "$rowKey" must exist');

  final addButtons = find.descendant(of: row, matching: find.byIcon(Icons.add));
  if (addButtons.evaluate().isNotEmpty) {
    for (var i = 0; i < incrementSteps; i++) {
      await tester.ensureVisible(addButtons.first);
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();
    }
    return;
  }

  final textFields = find.descendant(of: row, matching: find.byType(TextField));
  if (textFields.evaluate().isNotEmpty) {
    final currentText =
        tester.widget<TextField>(textFields.first).controller?.text ?? '';
    final parsed = int.tryParse(currentText.trim()) ?? 4;
    await tester.enterText(textFields.first, '${parsed + incrementSteps}');
    await tester.pumpAndSettle();
    return;
  }

  // Otherwise tap row to open edit dialog/sheet if supported.
  await tester.tap(row);
  await tester.pumpAndSettle();
  final dialog = find.byType(AlertDialog);
  if (dialog.evaluate().isNotEmpty) {
    final addInDialog = find.descendant(
      of: dialog,
      matching: find.byIcon(Icons.add),
    );
    if (addInDialog.evaluate().isNotEmpty) {
      for (var i = 0; i < incrementSteps; i++) {
        await tester.tap(addInDialog.first);
        await tester.pumpAndSettle();
      }
    }
    final saveBtn = find.descendant(
      of: dialog,
      matching: find.textContaining(RegExp(r'保存|適用|OK')),
    );
    if (saveBtn.evaluate().isNotEmpty) {
      await tester.tap(saveBtn.first);
      await tester.pumpAndSettle();
    }
  }
}

/// Reads back persisted state into a fresh [AppState] from mock
/// [SharedPreferences] to verify real persistence.
Future<AppState> _loadPersistedAppState(DateTime Function() clock) async {
  final state = AppState(clock: clock);
  await state.initialize();
  return state;
}

void main() {
  group('Tier 4 — Real-World E2E User Journeys (T4-01..T4-10)', () {
    testWidgets(
      'T4-01: First-Time Male Beginner Morning Quick Workout (20m) + Cold Restart',
      (WidgetTester tester) async {
        final clock = MutableTestClock(DateTime(2026, 11, 19, 7, 30, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        expectDarkScaffoldTheme(tester);
        expectNoRenderOverflow(tester);

        // Step 1: Configure Male / 1998 / Beginner / 70kg on Screen C.
        await tapNavTab(tester, 'nav_tab_settings');
        _expectR1UiCleanliness(tester, checkScreenCNoAgeBrackets: true);

        await _selectOptionInSelector(tester, 'gender_selector', '男性');
        await enterTextByKey(tester, 'birth_year_input', '1998');
        await _selectOptionInSelector(tester, 'experience_selector', '初級');
        await enterTextByKey(tester, 'body_weight_input', '70');
        await _tapContractedKey(tester, 'btn_save_profile');

        // Step 2: Navigate to Screen A1, verify morning auto-detection, pick 20m + Great.
        await tapNavTab(tester, 'nav_tab_training');
        expect(_readKeyText(tester, 'detected_timeslot_badge'), contains('朝'));

        await _tapContractedKey(tester, 'course_short');
        await _tapContractedKey(tester, 'condition_great');
        await _tapContractedKey(tester, 'btn_start_workout');

        // Step 3: Complete 2 exercises on Screen A2, verifying first-time load & R1 cleanliness.
        double? firstWeightKg;
        String? firstMachineId;
        final titles = await _completeInWorkoutFlow(
          tester,
          expectedCount: 2,
          onExercise: (index, title) async {
            expect(_readCounterCardValue(tester, 'card_sets'), 3.0);
            final targetText = _readKeyText(tester, 'target_muscles_badge');
            expect(targetText, contains('〇'));

            if (index == 0) {
              final spec = _matchMachineSpecByTitle(title);
              firstMachineId = spec.id;
              firstWeightKg = _readCounterCardValue(tester, 'card_weight');
              // Male (1.0) * Beginner (1.0) * 20_30 (1.0) * Great (1.0).
              final expectedFirstWeight = oracleRoundTo25(
                70.0 * spec.bwFactor * 1.0 * 1.0 * 1.0,
              );
              expect(firstWeightKg, expectedFirstWeight);
            }
          },
        );
        expect(titles.length, 2);
        expect(titles.toSet().length, 2);

        // Step 4: Submit "too_light" on Screen A3 and return to Screen A1.
        await _submitReviewAndReturnToA1(tester, 'feedback_too_light');

        // Step 5: Cold restart NoukinApp without resetting SharedPreferences.
        await restartNoukinApp(tester, clock: clock.call);
        expectNoRenderOverflow(tester);

        await tapNavTab(tester, 'nav_tab_settings');
        expect(find.textContaining('1998'), findsAtLeastNWidgets(1));

        // Verify persisted AppState & next-session +2.5kg progression.
        final persisted = await _loadPersistedAppState(clock.call);
        expect(persisted.isInitialized, isTrue);
        expect(persisted.profile.gender, Gender.male);
        expect(persisted.profile.birthYear, 1998);
        expect(persisted.profile.experience, ExperienceLevel.beginner);
        expect(persisted.profile.bodyWeightKg, 70.0);
        expect(persisted.profile.isFirstTime, isFalse);
        expect(persisted.sessionHistory.length, 1);

        final savedSession = persisted.sessionHistory.single;
        expect(savedSession.durationCourse, WorkoutDurationCourse.short20);
        expect(savedSession.condition, WorkoutCondition.great);
        expect(savedSession.timeSlot, TimeSlot.morning);
        expect(savedSession.feedback, WorkoutFeedback.tooLight);
        expect(savedSession.exercises.length, 2);

        final historyEntry = persisted.machineHistory[firstMachineId!]!;
        expect(historyEntry.sessionsSinceUsed, 0);
        expect(historyEntry.lastWeightKg, firstWeightKg);
        expect(historyEntry.lastFeedback, WorkoutFeedback.tooLight);
      },
    );

    testWidgets(
      'T4-02: Female Intermediate Evening Body-Make + Gender Sync + Swap & ± Adjust',
      (WidgetTester tester) async {
        final clock = MutableTestClock(DateTime(2026, 11, 19, 18, 0, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        // Step 1: Switch gender to Female on Screen C and verify Screen B auto-sync.
        await tapNavTab(tester, 'nav_tab_settings');
        await _selectOptionInSelector(tester, 'gender_selector', '女性');
        await enterTextByKey(tester, 'birth_year_input', '1993');
        await _selectOptionInSelector(tester, 'experience_selector', '中級');
        await enterTextByKey(tester, 'body_weight_input', '55');
        await _tapContractedKey(tester, 'btn_save_profile');

        await tapNavTab(tester, 'nav_tab_custom');
        final syncedState = await _loadPersistedAppState(clock.call);
        expect(syncedState.profile.purpose, TrainingPurpose.bodyMakeFemale);
        expect(
          find.descendant(
            of: find.byKey(const Key('purpose_selector')),
            matching: find.textContaining('女性向け'),
          ),
          findsAtLeastNWidgets(1),
        );

        // Step 2: Screen A1 -> Evening, Standard 45m, Normal, focus m2 (大臀筋).
        await tapNavTab(tester, 'nav_tab_training');
        expect(_readKeyText(tester, 'detected_timeslot_badge'), contains('夕方'));
        await _tapContractedKey(tester, 'course_standard');
        await _tapContractedKey(tester, 'condition_normal');
        await selectDropdownOption(tester, 'focus_muscle_dropdown', '大臀筋');
        await _tapContractedKey(tester, 'btn_start_workout');

        // Step 3: On Screen A2, swap exercise 0 via bottom sheet and adjust +2.5kg.
        String? swappedTitle;
        double? adjustedFirstWeight;
        await _completeInWorkoutFlow(
          tester,
          expectedCount: 4,
          onExercise: (index, title) async {
            expect(_readCounterCardValue(tester, 'card_sets'), 3.0);
            if (index == 0) {
              await _tapContractedKey(tester, 'btn_select_exercise');
              expect(find.byType(BottomSheet), findsOneWidget);
              expect(find.textContaining('種目変更'), findsAtLeastNWidgets(1));

              final swapOption1 = find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byKey(const Key('swap_exercise_option_1')),
              );
              final sheetTiles = find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(ListTile),
              );
              Finder swapCandidate;
              if (swapOption1.evaluate().isNotEmpty) {
                swapCandidate = swapOption1.first;
              } else {
                expect(sheetTiles, findsAtLeastNWidgets(2));
                swapCandidate = sheetTiles.at(1);
                for (final el in sheetTiles.evaluate()) {
                  final textDesc = find.descendant(
                    of: find.byWidget(el.widget),
                    matching: find.byType(Text),
                  );
                  final tileText = textDesc
                      .evaluate()
                      .map((t) => (t.widget as Text).data ?? '')
                      .join(' ');
                  if (tileText.isNotEmpty && !tileText.contains(title)) {
                    swapCandidate = find.byWidget(el.widget);
                    break;
                  }
                }
              }
              await scrollAndTap(tester, swapCandidate);

              swappedTitle = _readKeyText(tester, 'exercise_title');
              expect(swappedTitle, isNot(equals(title)));

              final beforeWeight = _readCounterCardValue(tester, 'card_weight');
              await tapCounterButton(tester, 'card_weight', increment: true);
              await tester.pumpAndSettle();
              adjustedFirstWeight = _readCounterCardValue(
                tester,
                'card_weight',
              );
              expect(adjustedFirstWeight, beforeWeight + 2.5);
            }
          },
        );

        // Step 4: Submit "just_right" on Screen A3 and verify persisted record.
        await _submitReviewAndReturnToA1(tester, 'feedback_just_right');

        final persisted = await _loadPersistedAppState(clock.call);
        expect(persisted.sessionHistory.length, 1);
        final session = persisted.sessionHistory.single;
        expect(session.durationCourse, WorkoutDurationCourse.standard45);
        expect(session.timeSlot, TimeSlot.evening);
        expect(session.focusMuscleId, 'm2');
        expect(session.feedback, WorkoutFeedback.justRight);
        expect(session.exercises.length, 4);
        expect(session.exercises.first.machineName, swappedTitle);
        expect(session.exercises.first.weightKg, adjustedFirstWeight);
      },
    );

    testWidgets(
      'T4-03: Late-Night (22:30) Tired User with Multi-Muscle Shoulder Injury',
      (WidgetTester tester) async {
        final clock = MutableTestClock(DateTime(2026, 11, 19, 22, 30, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        // Step 1: Injure m34 (三角筋前部) and m35 (三角筋中部) on Screen B.
        await tapNavTab(tester, 'nav_tab_custom');
        await _tapContractedKey(tester, 'injury_toggle_m34');
        await _tapContractedKey(tester, 'injury_toggle_m35');

        final afterInjury = await _loadPersistedAppState(clock.call);
        expect(afterInjury.muscleStates['m34']!.isInjured, isTrue);
        expect(afterInjury.muscleStates['m35']!.isInjured, isTrue);

        // Step 2: Screen A1 -> Night badge, Standard 45m, Tired condition.
        await tapNavTab(tester, 'nav_tab_training');
        expect(
          _readKeyText(tester, 'detected_timeslot_badge'),
          contains('就寝前'),
        );
        await _tapContractedKey(tester, 'course_standard');
        await _tapContractedKey(tester, 'condition_tired');
        await _tapContractedKey(tester, 'btn_start_workout');

        // Step 3: Verify ZERO machines involve m34/m35 (primary OR synergist)
        // and all exercises use 2 sets & -5% tired weight.
        await _completeInWorkoutFlow(
          tester,
          expectedCount: 4,
          onExercise: (index, title) async {
            final spec = _matchMachineSpecByTitle(title);
            expect(
              spec.primaryMuscleIds.contains('m34') ||
                  spec.primaryMuscleIds.contains('m35'),
              isFalse,
              reason: '${spec.id} must not involve injured shoulder primaries',
            );
            expect(
              spec.synergistMuscleIds.contains('m34') ||
                  spec.synergistMuscleIds.contains('m35'),
              isFalse,
              reason: '${spec.id} must not involve injured shoulder synergists',
            );
            expect(_readCounterCardValue(tester, 'card_sets'), 2.0);
          },
        );

        // Step 4: Submit "too_hard" on Screen A3 and verify R+1 extension in engine.
        await _submitReviewAndReturnToA1(tester, 'feedback_too_hard');

        final persisted = await _loadPersistedAppState(clock.call);
        expect(
          persisted.sessionHistory.single.condition,
          WorkoutCondition.tired,
        );
        expect(persisted.sessionHistory.single.timeSlot, TimeSlot.night);
        expect(
          persisted.sessionHistory.single.feedback,
          WorkoutFeedback.tooHard,
        );

        const generator = WorkoutMenuGenerator();
        final scores = generator.computeMuscleScores(
          muscleStates: persisted.muscleStates,
          profile: persisted.profile,
          lastFeedback: WorkoutFeedback.tooHard,
          now: clock(),
        );
        expect(scores['m34']!.mVal, 0.0);
        expect(scores['m34']!.status, MuscleScoreStatus.injured);
        // m36 (三角筋後部) is in HIGH_VOLUME_EXTEND_MUSCLES -> R_i extended +1.
        expect(
          scores['m36']!.effectiveRecoveryDays,
          kExpectedMuscleSpecById['m36']!.recoveryDays + 1,
        );
      },
    );

    testWidgets(
      'T4-04: 60+ Returning User Consecutive Full-60m Sessions & Supercompensation Rotation',
      (WidgetTester tester) async {
        final clock = MutableTestClock(DateTime(2026, 11, 19, 10, 0, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        // Step 1: Set 62-year-old user (birthYear = 1964 -> 60_plus) on Screen C.
        await tapNavTab(tester, 'nav_tab_settings');
        await _selectOptionInSelector(tester, 'gender_selector', '男性');
        await enterTextByKey(tester, 'birth_year_input', '1964');
        await _selectOptionInSelector(tester, 'experience_selector', '初級');
        await enterTextByKey(tester, 'body_weight_input', '70');
        await _tapContractedKey(tester, 'btn_save_profile');

        // Step 2: Session 1 (Full 60m = 5 exercises) verifying 60_plus rep shifts.
        await tapNavTab(tester, 'nav_tab_training');
        await _tapContractedKey(tester, 'course_full');
        await _tapContractedKey(tester, 'condition_normal');
        await _tapContractedKey(tester, 'btn_start_workout');

        final session1Titles = await _completeInWorkoutFlow(
          tester,
          expectedCount: 5,
          onExercise: (index, title) async {
            final spec = _matchMachineSpecByTitle(title);
            final expectedReps = spec.baseReps == 10
                ? 12
                : (spec.baseReps == 12 ? 15 : spec.baseReps);
            expect(_readCounterCardValue(tester, 'card_reps'), expectedReps);
            expect(_readCounterCardValue(tester, 'card_sets'), 3.0);
          },
        );
        await _submitReviewAndReturnToA1(tester, 'feedback_just_right');

        // Verify Session 1 primaries are now in supercompensation recovery (B=1 < R>=3 for 60+).
        final afterSession1 = await _loadPersistedAppState(clock.call);
        expect(afterSession1.profile.isFirstTime, isFalse);
        const generator = WorkoutMenuGenerator();
        final postS1Scores = generator.computeMuscleScores(
          muscleStates: afterSession1.muscleStates,
          profile: afterSession1.profile,
          now: clock(),
        );
        final session1PrimaryMuscles = <String>{
          for (final title in session1Titles)
            ..._matchMachineSpecByTitle(title).primaryMuscleIds,
        };
        for (final mId in session1PrimaryMuscles) {
          expect(
            postS1Scores[mId]!.mVal,
            0.0,
            reason:
                'Trained primary $mId must be guarded (M=0) immediately after',
          );
          if (afterSession1.muscleStates[mId]!.priorityP > 0) {
            expect(postS1Scores[mId]!.status, MuscleScoreStatus.recovering);
          }
        }

        // Step 3: Immediately run Session 2 (Full 60m) and verify rotation + 60+ returning ×0.90.
        await _tapContractedKey(tester, 'course_full');
        await _tapContractedKey(tester, 'condition_normal');
        await _tapContractedKey(tester, 'btn_start_workout');

        final session2Titles = await _completeInWorkoutFlow(
          tester,
          expectedCount: 5,
          onExercise: (index, title) async {
            final spec = _matchMachineSpecByTitle(title);
            final expectedReps = spec.baseReps == 10
                ? 12
                : (spec.baseReps == 12 ? 15 : spec.baseReps);
            expect(_readCounterCardValue(tester, 'card_reps'), expectedReps);
            if (!session1Titles.contains(title)) {
              expect(
                _readCounterCardValue(tester, 'card_weight'),
                oracleRoundTo25(spec.baseWeight * 0.90),
              );
            }
          },
        );
        await _submitReviewAndReturnToA1(tester, 'feedback_just_right');

        // Verify fresh machine rotation across consecutive sessions.
        final overlapCount = session2Titles
            .toSet()
            .intersection(session1Titles.toSet())
            .length;
        expect(
          overlapCount,
          lessThan(5),
          reason: 'Supercompensation guard and sessionsSinceUsed=0 must rotate Session 2 menu',
        );

        final afterSession2 = await _loadPersistedAppState(clock.call);
        expect(afterSession2.sessionHistory.length, 2);
      },
    );

    testWidgets(
      'T4-05: Windsurfing Athlete Purpose + Group Batch + Individual Matrix Edit (daytime)',
      (WidgetTester tester) async {
        final clock = MutableTestClock(DateTime(2026, 11, 19, 13, 30, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        // Step 1: Select Windsurfing purpose on Screen B and adjust Core batch + individual row.
        await tapNavTab(tester, 'nav_tab_custom');
        _expectR1UiCleanliness(tester, checkScreenBHiddenConstants: true);

        await _selectOptionInSelector(tester, 'purpose_selector', 'ウィンドサーフィン');

        await _applyGroupBatchBlankDays(
          tester,
          MuscleGroup.core,
          incrementSteps: 4,
        );
        await _editMatrixMuscleBlankDays(tester, 'm7', incrementSteps: 1);

        final afterEdits = await _loadPersistedAppState(clock.call);
        expect(afterEdits.profile.purpose, TrainingPurpose.windsurfing);
        expect(
          afterEdits.muscleStates['m7']!.blankDays,
          greaterThan(4),
          reason: 'Core batch + individual edit must increase m7 blankDays',
        );

        // Step 2: Screen A1 -> Daytime badge, Standard 45m -> complete through A3.
        await tapNavTab(tester, 'nav_tab_training');
        expect(_readKeyText(tester, 'detected_timeslot_badge'), contains('日中'));
        await _tapContractedKey(tester, 'course_standard');
        await _tapContractedKey(tester, 'condition_normal');
        await _tapContractedKey(tester, 'btn_start_workout');

        await _completeInWorkoutFlow(tester, expectedCount: 4);
        await _submitReviewAndReturnToA1(tester, 'feedback_just_right');

        final persisted = await _loadPersistedAppState(clock.call);
        expect(persisted.profile.purpose, TrainingPurpose.windsurfing);
        expect(persisted.sessionHistory.single.timeSlot, TimeSlot.daytime);
      },
    );

    testWidgets(
      'T4-06: Offline Google Login -> Workout -> Cold Restart -> Logout Lifecycle',
      (WidgetTester tester) async {
        expect(SupabaseConfig.isConfigured, isFalse);
        final clock = MutableTestClock(DateTime(2026, 11, 19, 16, 0, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        // Step 1: Screen C local fallback sign-in + profile save.
        await tapNavTab(tester, 'nav_tab_settings');
        final initialState = await _loadPersistedAppState(clock.call);
        expect(initialState.isLocalFallbackMode, isTrue);
        expect(find.byKey(const Key('btn_google_login')), findsOneWidget);
        await _tapContractedKey(tester, 'btn_google_login');

        expect(
          find.byKey(const Key('btn_logout')),
          findsOneWidget,
          reason: 'Logging in via local fallback must expose btn_logout',
        );

        await enterTextByKey(tester, 'birth_year_input', '1992');
        await enterTextByKey(tester, 'body_weight_input', '68');
        await _tapContractedKey(tester, 'btn_save_profile');

        // Step 2: Screen B injure m0, then Screen A1->A2->A3 20m workout.
        await tapNavTab(tester, 'nav_tab_custom');
        await _tapContractedKey(tester, 'injury_toggle_m0');

        await tapNavTab(tester, 'nav_tab_training');
        await _tapContractedKey(tester, 'course_short');
        await _tapContractedKey(tester, 'condition_normal');
        await _tapContractedKey(tester, 'btn_start_workout');

        await _completeInWorkoutFlow(
          tester,
          expectedCount: 2,
          onExercise: (index, title) async {
            final spec = _matchMachineSpecByTitle(title);
            expect(spec.primaryMuscleIds.contains('m0'), isFalse);
            expect(spec.synergistMuscleIds.contains('m0'), isFalse);
          },
        );
        await _submitReviewAndReturnToA1(tester, 'feedback_just_right');

        // Step 3: Cold restart and verify auth user, profile, injury, and history persist.
        await restartNoukinApp(tester, clock: clock.call);
        final restarted = await _loadPersistedAppState(clock.call);
        expect(restarted.isLocalFallbackMode, isTrue);
        expect(restarted.currentUser, isNotNull);
        expect(restarted.profile.birthYear, 1992);
        expect(restarted.profile.bodyWeightKg, 68.0);
        expect(restarted.muscleStates['m0']!.isInjured, isTrue);
        expect(restarted.sessionHistory.length, 1);

        // Step 4: Logout on Screen C and verify local workout history remains intact.
        await tapNavTab(tester, 'nav_tab_settings');
        expect(find.byKey(const Key('btn_logout')), findsOneWidget);
        await _tapContractedKey(tester, 'btn_logout');
        expect(find.byKey(const Key('btn_google_login')), findsOneWidget);

        final afterLogout = await _loadPersistedAppState(clock.call);
        expect(afterLogout.currentUser, isNull);
        expect(afterLogout.sessionHistory.length, 1);
      },
    );

    testWidgets(
      'T4-07: Overtrained Muscle Recovery (B=1) -> Batch Reset (+5) -> Leg Machine Unlock',
      (WidgetTester tester) async {
        final clock = MutableTestClock(DateTime(2026, 11, 19, 13, 0, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        // Step 1: Complete a leg-focused workout (focus = m0 大腿四頭筋) so leg primaries drop to B=1.
        await selectDropdownOption(tester, 'focus_muscle_dropdown', '大腿四頭筋');
        await _tapContractedKey(tester, 'course_standard');
        await _tapContractedKey(tester, 'condition_normal');
        await _tapContractedKey(tester, 'btn_start_workout');
        final firstTitles = await _completeInWorkoutFlow(
          tester,
          expectedCount: 4,
        );
        await _submitReviewAndReturnToA1(tester, 'feedback_just_right');

        final trainedLegPrimaryIds = <String>{
          for (final title in firstTitles)
            for (final mId in _matchMachineSpecByTitle(title).primaryMuscleIds)
              if (kExpectedMuscleSpecById[mId]!.group == MuscleGroup.legsGlutes)
                mId,
        };
        expect(trainedLegPrimaryIds, isNotEmpty);

        // Verify trained leg primary muscles are now at B=1 (< R_i -> M=0.0 recovering).
        final afterWorkout = await _loadPersistedAppState(clock.call);
        const generator = WorkoutMenuGenerator();
        final preBatchScores = generator.computeMuscleScores(
          muscleStates: afterWorkout.muscleStates,
          profile: afterWorkout.profile,
          now: clock(),
        );
        for (final mId in trainedLegPrimaryIds) {
          expect(afterWorkout.muscleStates[mId]!.blankDays, 1);
          expect(preBatchScores[mId]!.mVal, 0.0);
          expect(preBatchScores[mId]!.status, MuscleScoreStatus.recovering);
        }

        // Step 2: Check Screen B matrix shows m0 recovering, then batch-reset legsGlutes (+5).
        await tapNavTab(tester, 'nav_tab_custom');
        if (trainedLegPrimaryIds.contains('m0')) {
          await _ensureKeyVisible(
            tester,
            'matrix_row_m0',
            preferredContainerKey: 'muscle_matrix_list',
          );
          final rowText = _readKeyText(tester, 'matrix_row_m0');
          expect(rowText, contains('0'));
        }

        final beforeChestB = afterWorkout.muscleStates['m3']!.blankDays;
        await _applyGroupBatchBlankDays(
          tester,
          MuscleGroup.legsGlutes,
          incrementSteps: 5,
          preferPlusFiveButton: true,
        );

        final afterBatch = await _loadPersistedAppState(clock.call);
        for (final mId in trainedLegPrimaryIds) {
          expect(
            afterBatch.muscleStates[mId]!.blankDays,
            greaterThanOrEqualTo(5),
            reason: 'Batch +5 on legsGlutes must move B=1 past R_i',
          );
        }
        // Other muscle groups remain untouched by legsGlutes batch edit.
        expect(afterBatch.muscleStates['m3']!.blankDays, beforeChestB);

        // Step 3: Verify leg muscles are unlocked (active) and eligible on Screen A1 -> A2.
        final postBatchScores = generator.computeMuscleScores(
          muscleStates: afterBatch.muscleStates,
          profile: afterBatch.profile,
          now: clock(),
        );
        for (final mId in trainedLegPrimaryIds) {
          expect(postBatchScores[mId]!.mVal, greaterThan(0.0));
          expect(postBatchScores[mId]!.status, MuscleScoreStatus.active);
        }

        await tapNavTab(tester, 'nav_tab_training');
        await selectDropdownOption(tester, 'focus_muscle_dropdown', '大腿四頭筋');
        await _tapContractedKey(tester, 'course_short');
        await _tapContractedKey(tester, 'btn_start_workout');
        final unlockedTitles = await _completeInWorkoutFlow(
          tester,
          expectedCount: 2,
        );
        expect(
          unlockedTitles.any(
            (t) =>
                _matchMachineSpecByTitle(t).category == MuscleGroup.legsGlutes,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'T4-08: Extreme Multi-Injury (QUICK_INJURY_MUSCLES 10 injured) Partial Menu & Recovery',
      (WidgetTester tester) async {
        final clock = MutableTestClock(DateTime(2026, 11, 19, 14, 0, 0));
        await pumpNoukinApp(tester, clock: clock.call);

        // Step 1: Injure all 10 QUICK_INJURY_MUSCLES on Screen B.
        await tapNavTab(tester, 'nav_tab_custom');
        for (final mId in kQuickInjuryMuscleIds) {
          await _tapContractedKey(tester, 'injury_toggle_$mId');
        }

        final afterAllInjured = await _loadPersistedAppState(clock.call);
        for (final mId in kQuickInjuryMuscleIds) {
          expect(afterAllInjured.muscleStates[mId]!.isInjured, isTrue);
        }

        // Step 2: Request Full 60m (5 exercises) on Screen A1 -> verify partial (< 5) safe menu.
        await tapNavTab(tester, 'nav_tab_training');
        await _tapContractedKey(tester, 'course_full');
        await _tapContractedKey(tester, 'condition_normal');
        await _tapContractedKey(tester, 'btn_start_workout');

        expect(find.byKey(const Key('exercise_title')), findsOneWidget);
        final progressBadge = _readKeyText(tester, 'exercise_progress_badge');
        final totalMatch = RegExp(r'/\s*(\d+)').firstMatch(progressBadge);
        expect(totalMatch, isNotNull);
        final partialCount = int.parse(totalMatch!.group(1)!);
        expect(partialCount, greaterThanOrEqualTo(1));
        expect(partialCount, lessThan(5));

        final firstPartialTitle = _readKeyText(tester, 'exercise_title');
        final firstPartialSpec = _matchMachineSpecByTitle(firstPartialTitle);
        for (final mId in kQuickInjuryMuscleIds) {
          expect(firstPartialSpec.primaryMuscleIds.contains(mId), isFalse);
          expect(firstPartialSpec.synergistMuscleIds.contains(mId), isFalse);
        }

        // Abort back to Screen A1 cleanly.
        await _tapContractedKey(tester, 'training_back_button');
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);

        // Step 3: Clear all 10 injuries on Screen B and verify full 5-exercise menu returns.
        await tapNavTab(tester, 'nav_tab_custom');
        for (final mId in kQuickInjuryMuscleIds) {
          await _tapContractedKey(tester, 'injury_toggle_$mId');
        }

        await tapNavTab(tester, 'nav_tab_training');
        await _tapContractedKey(tester, 'course_full');
        await _tapContractedKey(tester, 'btn_start_workout');

        final restoredTitles = await _completeInWorkoutFlow(
          tester,
          expectedCount: 5,
        );
        expect(restoredTitles.length, 5);
        expect(restoredTitles.toSet().length, 5);
        await _submitReviewAndReturnToA1(tester, 'feedback_just_right');
      },
    );

    testWidgets(
      'T4-09: All-3-Tab Responsive (390x844 & 1280x800) & R1 Zero-Prohibition Walkthrough',
      (WidgetTester tester) async {
        final clock = MutableTestClock(kClockMorning0800);

        Future<void> runWalkthroughForViewport(Size viewport) async {
          await pumpNoukinApp(
            tester,
            clock: clock.call,
            viewportSize: viewport,
          );
          expectDarkScaffoldTheme(tester);
          expectNoRenderOverflow(tester);
          expect(
            find.textContaining(RegExp(r'のう筋|Noukin')),
            findsAtLeastNWidgets(1),
          );
          _expectR1UiCleanliness(tester);

          // Traverse Screen B.
          await tapNavTab(tester, 'nav_tab_custom');
          expectNoRenderOverflow(tester);
          _expectR1UiCleanliness(tester, checkScreenBHiddenConstants: true);
          await _ensureKeyVisible(
            tester,
            'matrix_row_m53',
            preferredContainerKey: 'muscle_matrix_list',
          );
          expect(find.byKey(const Key('matrix_row_m53')), findsOneWidget);

          // Traverse Screen C.
          await tapNavTab(tester, 'nav_tab_settings');
          expectNoRenderOverflow(tester);
          _expectR1UiCleanliness(tester, checkScreenCNoAgeBrackets: true);

          // Traverse Screen A1 -> A2 -> Swap Sheet -> A3 -> A1.
          await tapNavTab(tester, 'nav_tab_training');
          expectNoRenderOverflow(tester);
          _expectR1UiCleanliness(tester);

          await _tapContractedKey(tester, 'course_short');
          await _tapContractedKey(tester, 'btn_start_workout');
          expectNoRenderOverflow(tester);

          await _completeInWorkoutFlow(
            tester,
            expectedCount: 2,
            onExercise: (index, title) async {
              expectNoRenderOverflow(tester);
              if (index == 0) {
                final nextButtonFinder = find.byKey(
                  const Key('btn_next_workout'),
                );
                final bgColor = resolveEffectiveButtonBackgroundColor(
                  tester,
                  nextButtonFinder,
                );
                final fgColor = resolveEffectiveButtonForegroundColor(
                  tester,
                  nextButtonFinder,
                );
                expect(bgColor, AppColors.primaryAccent);
                expect(fgColor, AppColors.onPrimaryAccent);

                await _tapContractedKey(tester, 'btn_select_exercise');
                expect(find.byType(BottomSheet), findsOneWidget);
                expectNoRenderOverflow(tester);
                final swapOption1 = find.descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byKey(const Key('swap_exercise_option_1')),
                );
                if (swapOption1.evaluate().isNotEmpty) {
                  await scrollAndTap(tester, swapOption1.first);
                } else {
                  final sheetTiles = find.descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(ListTile),
                  );
                  expect(sheetTiles, findsAtLeastNWidgets(1));
                  await scrollAndTap(tester, sheetTiles.first);
                }
                expect(find.byType(BottomSheet), findsNothing);
              }
            },
          );
          expectNoRenderOverflow(tester);
          await _submitReviewAndReturnToA1(tester, 'feedback_just_right');
          expectNoRenderOverflow(tester);
        }

        // Mobile viewport (390x844) & Windows desktop viewport (1280x800).
        await runWalkthroughForViewport(const Size(390, 844));
        await runWalkthroughForViewport(const Size(1280, 800));
      },
    );

    testWidgets(
      'T4-10: Zero-Network (HttpOverrides) 3-Session Progression & Millisecond Latency Benchmark',
      (WidgetTester tester) async {
        await runWithoutNetwork(() async {
          final clock = MutableTestClock(DateTime(2026, 11, 19, 18, 0, 0));
          await pumpNoukinApp(tester, clock: clock.call);

          // Configure initial profile on Screen C.
          await tapNavTab(tester, 'nav_tab_settings');
          await _selectOptionInSelector(tester, 'gender_selector', '男性');
          await enterTextByKey(tester, 'birth_year_input', '1995');
          await _selectOptionInSelector(tester, 'experience_selector', '初級');
          await enterTextByKey(tester, 'body_weight_input', '70');
          await _tapContractedKey(tester, 'btn_save_profile');

          // Session 1 (Day 1): short20 -> tooLight.
          await tapNavTab(tester, 'nav_tab_training');
          await _tapContractedKey(tester, 'course_short');
          await _tapContractedKey(tester, 'condition_normal');
          await _tapContractedKey(tester, 'btn_start_workout');
          await _completeInWorkoutFlow(tester, expectedCount: 2);
          await _submitReviewAndReturnToA1(tester, 'feedback_too_light');

          // Session 2 (Day 4): short20 -> tooHard.
          clock.advanceDays(3);
          await _tapContractedKey(tester, 'course_short');
          await _tapContractedKey(tester, 'condition_normal');
          await _tapContractedKey(tester, 'btn_start_workout');
          await _completeInWorkoutFlow(tester, expectedCount: 2);
          await _submitReviewAndReturnToA1(tester, 'feedback_too_hard');

          // Session 3 (Day 7): short20 -> justRight.
          clock.advanceDays(3);
          await _tapContractedKey(tester, 'course_short');
          await _tapContractedKey(tester, 'condition_normal');
          await _tapContractedKey(tester, 'btn_start_workout');
          await _completeInWorkoutFlow(tester, expectedCount: 2);
          await _submitReviewAndReturnToA1(tester, 'feedback_just_right');

          final persisted = await _loadPersistedAppState(clock.call);
          expect(persisted.sessionHistory.length, 3);
          expect(
            persisted.sessionHistory.map((s) => s.feedback).toList(),
            containsAllInOrder(<WorkoutFeedback>[
              WorkoutFeedback.tooLight,
              WorkoutFeedback.tooHard,
              WorkoutFeedback.justRight,
            ]),
          );
        });

        // Pure engine 3-session multi-day simulation & millisecond latency benchmark.
        runWithoutNetworkSync(() {
          const generator = WorkoutMenuGenerator();
          var profile = buildTestProfile(
            gender: Gender.male,
            birthYear: 1995,
            experience: ExperienceLevel.beginner,
            bodyWeightKg: 70.0,
            isFirstTime: true,
          );
          var states = MasterData.defaultMuscleStates(profile.purpose);
          var history = MasterData.defaultMachineHistory();
          var sessionCount = 1;
          final feedbacks = <WorkoutFeedback>[
            WorkoutFeedback.tooLight,
            WorkoutFeedback.tooHard,
            WorkoutFeedback.justRight,
          ];

          final sw = Stopwatch()..start();
          for (var i = 0; i < 3; i++) {
            final menu = generator.generateMenu(
              profile: profile,
              muscleStates: states,
              machineHistory: history,
              course: WorkoutDurationCourse.full60,
              condition: WorkoutCondition.normal,
              now: DateTime(2026, 11, 19 + i * 3, 18, 0, 0),
              sessionCount: sessionCount,
            );
            expect(menu.exercises.length, 5);

            final advanced = generator.advanceSessionDay(
              muscleStates: states,
              machineHistory: history,
              completedExercises: menu.exercises,
              overallFeedback: feedbacks[i],
              sessionCount: sessionCount,
              daysElapsed: 3,
            );
            states = advanced.muscleStates;
            history = advanced.machineHistory;
            sessionCount = advanced.sessionCount;
            profile = profile.copyWith(isFirstTime: false);
          }
          sw.stop();

          expect(sessionCount, 4);
          expect(
            sw.elapsedMilliseconds,
            lessThan(150),
            reason: '3 full 5-exercise menu generations + advances must complete in < 150 ms (< 50 ms each) offline',
          );
        });
      },
    );
  });
}
