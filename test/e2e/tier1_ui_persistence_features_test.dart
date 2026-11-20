import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/app.dart';
import 'package:noukin/config/supabase_config.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/services/auth_service.dart';
import 'package:noukin/services/workout_repository.dart';
import 'package:noukin/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_test_helpers.dart';

// =============================================================================
// Resilient UI Inspection & Interaction Helpers (Opaque-Box)
// =============================================================================

String _extractAllText(WidgetTester tester, Finder root) {
  final textWidgets = tester.widgetList<Text>(
    find.descendant(of: root, matching: find.byType(Text)),
  );
  final rootWidget = tester.widget(root);
  final buffer = StringBuffer();
  if (rootWidget is Text && rootWidget.data != null) {
    buffer.write(rootWidget.data);
  }
  for (final t in textWidgets) {
    if (t.data != null) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(t.data);
    }
  }
  return buffer.toString();
}

String _readTextByKey(WidgetTester tester, String key) {
  final finder = find.byKey(Key(key));
  expect(finder, findsOneWidget, reason: 'Widget with Key("$key") must exist');
  return _extractAllText(tester, finder).trim();
}

double _readWeightFromCard(WidgetTester tester) {
  final text = _readTextByKey(tester, 'card_weight');
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*kg').firstMatch(text);
  expect(match, isNotNull, reason: 'Expected "<number> kg" in "$text"');
  return double.parse(match!.group(1)!);
}

int _readRepsFromCard(WidgetTester tester) {
  final text = _readTextByKey(tester, 'card_reps');
  final match = RegExp(r'(\d+)\s*回').firstMatch(text);
  expect(match, isNotNull, reason: 'Expected "<number> 回" in "$text"');
  return int.parse(match!.group(1)!);
}

int _readSetsFromCard(WidgetTester tester) {
  final text = _readTextByKey(tester, 'card_sets');
  final match = RegExp(r'(\d+)\s*セット').firstMatch(text);
  expect(match, isNotNull, reason: 'Expected "<number> セット" in "$text"');
  return int.parse(match!.group(1)!);
}

/// Starts a workout from Screen A1 and waits until Screen A2 (`exercise_title`)
/// is mounted.
Future<void> _startWorkoutFromA1(
  WidgetTester tester, {
  String courseKey = 'course_short',
  String? conditionKey,
  String? focusMuscleName,
}) async {
  await tapKey(tester, courseKey);
  if (conditionKey != null) {
    await tapKey(tester, conditionKey);
  }
  if (focusMuscleName != null) {
    await _selectOptionInSelector(
      tester,
      'focus_muscle_dropdown',
      focusMuscleName,
    );
  }
  await tapKey(tester, 'btn_start_workout');
  expect(
    find.byKey(const Key('exercise_title')),
    findsOneWidget,
    reason: 'Screen A2 should appear after tapping btn_start_workout',
  );
}

/// Advances Screen A2 via `btn_next_workout` until Screen A3 (`btn_finish_workout`)
/// appears, supporting both direct `'次へ'` (`N` taps) and `'開始'` -> `'次へ'`
/// (`N + 1` taps). Returns the ordered list of distinct exercise titles seen.
Future<List<String>> _advanceWorkoutToA3(
  WidgetTester tester, {
  int maxTaps = 12,
}) async {
  final titles = <String>[];
  var taps = 0;

  while (find.byKey(const Key('btn_finish_workout')).evaluate().isEmpty &&
      taps < maxTaps) {
    if (find.byKey(const Key('exercise_title')).evaluate().isNotEmpty) {
      final title = _readTextByKey(tester, 'exercise_title');
      if (titles.isEmpty || titles.last != title) {
        titles.add(title);
      }
    }
    await tapKey(tester, 'btn_next_workout');
    taps++;
  }

  expect(
    find.byKey(const Key('btn_finish_workout')),
    findsOneWidget,
    reason: 'Should reach Screen A3 within $maxTaps taps',
  );
  return titles;
}

/// Selects an option containing [optionText] in a widget keyed by [selectorKey],
/// supporting both DropdownButton/DropdownButtonFormField overlays (with scroll
/// inside long menus) and inline ChoiceChip/SegmentedButton/RadioListTile groups.
Future<void> _selectOptionInSelector(
  WidgetTester tester,
  String selectorKey,
  String optionText,
) => selectOptionInControl(tester, selectorKey, optionText);

Finder _findEffectiveScrollable(Finder container) {
  final inner = find.descendant(
    of: container,
    matching: find.byType(Scrollable),
  );
  for (final element in inner.evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.maxScrollExtent > 0) {
      return find.byWidget(element.widget);
    }
  }
  return find.byType(Scrollable).first;
}

/// Checks whether a button keyed by [key] is enabled (`onPressed != null`).
bool _isButtonEnabled(WidgetTester tester, String key) {
  final finder = find.byKey(Key(key));
  expect(finder, findsOneWidget);
  final widget = tester.widget(finder);
  if (widget is ButtonStyleButton) {
    return widget.onPressed != null;
  }
  if (widget is IconButton) {
    return widget.onPressed != null;
  }
  final descendantBtn = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  if (descendantBtn.evaluate().isNotEmpty) {
    final btn = tester.widget<ButtonStyleButton>(descendantBtn.first);
    return btn.onPressed != null;
  }
  return true;
}

/// Completes Screen A1 -> A2 -> A3 and returns the first exercise's machine spec
/// and prescribed weight.
Future<({ExpectedMachineSpec machine, double weightKg})>
_runShortWorkoutWithFeedback(
  WidgetTester tester, {
  required String feedbackKey,
}) async {
  await _startWorkoutFromA1(tester, courseKey: 'course_short');
  final firstTitle = _readTextByKey(tester, 'exercise_title');
  final firstWeight = _readWeightFromCard(tester);
  final spec = kExpectedMachineSpecs.firstWhere(
    (m) => m.name == firstTitle || firstTitle.contains(m.name),
  );

  await _advanceWorkoutToA3(tester);
  await tapKey(tester, feedbackKey);
  await tapKey(tester, 'btn_finish_workout');

  expect(
    find.byKey(const Key('btn_start_workout')),
    findsOneWidget,
    reason: 'Finishing Screen A3 should return to Screen A1',
  );

  return (machine: spec, weightKg: firstWeight);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ===========================================================================
  // F7: Screen A1 — Pre-Workout Step Form (6 tests)
  // ===========================================================================
  group('F7: Screen A1 Pre-Workout Step Form', () {
    testWidgets(
      'T1-F7-01: renders all 3 course options and contracted A1 keys on dark scaffold',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));

        expectDarkScaffoldTheme(tester);

        expect(find.byKey(const Key('course_short')), findsOneWidget);
        expect(find.byKey(const Key('course_standard')), findsOneWidget);
        expect(find.byKey(const Key('course_full')), findsOneWidget);

        expect(
          _readTextByKey(tester, 'course_short'),
          contains('20分'),
        );
        expect(
          _readTextByKey(tester, 'course_standard'),
          contains('45分'),
        );
        expect(
          _readTextByKey(tester, 'course_full'),
          contains('60分'),
        );

        expect(find.byKey(const Key('condition_great')), findsOneWidget);
        expect(find.byKey(const Key('condition_normal')), findsOneWidget);
        expect(find.byKey(const Key('condition_tired')), findsOneWidget);
        expect(find.byKey(const Key('focus_muscle_dropdown')), findsOneWidget);
        expect(
          find.byKey(const Key('detected_timeslot_badge')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);

        expectNoRenderOverflow(tester);
      },
    );

    testWidgets(
      'T1-F7-02: condition options (great/normal/tired) are selectable and tired sets 2 sets',
      (WidgetTester tester) async {
        // great -> 3 sets
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(
          tester,
          courseKey: 'course_short',
          conditionKey: 'condition_great',
        );
        expect(_readSetsFromCard(tester), 3);

        // normal -> 3 sets
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(
          tester,
          courseKey: 'course_short',
          conditionKey: 'condition_normal',
        );
        expect(_readSetsFromCard(tester), 3);

        // tired -> 2 sets
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(
          tester,
          courseKey: 'course_short',
          conditionKey: 'condition_tired',
        );
        expect(_readSetsFromCard(tester), 2);
      },
    );

    testWidgets(
      'T1-F7-03: focus_muscle_dropdown boosts machines targeting the selected focus muscle',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));

        await _startWorkoutFromA1(
          tester,
          courseKey: 'course_short',
          focusMuscleName: '上腕二頭筋',
        );

        final targetedMusclesSeen = <String>[];
        while (find.byKey(const Key('btn_finish_workout')).evaluate().isEmpty &&
            targetedMusclesSeen.length < 6) {
          if (find
              .byKey(const Key('target_muscles_badge'))
              .evaluate()
              .isNotEmpty) {
            targetedMusclesSeen.add(
              _readTextByKey(tester, 'target_muscles_badge'),
            );
          }
          await tapKey(tester, 'btn_next_workout');
        }

        expect(
          targetedMusclesSeen.any((text) => text.contains('上腕二頭筋')),
          isTrue,
          reason:
              'Selecting 上腕二頭筋 as focus muscle should include it in A2 menu ($targetedMusclesSeen)',
        );
      },
    );

    testWidgets(
      'T1-F7-04: detected_timeslot_badge reflects injected clock for morning/daytime/evening/night',
      (WidgetTester tester) async {
        final cases = <(DateTime, String)>[
          (kClockMorning0800, '朝'),
          (kClockDaytime1300, '日中'),
          (kClockEvening1800, '夕方'),
          (kClockNight2230, '就寝前'),
        ];

        for (final (clockTime, expectedLabel) in cases) {
          await pumpNoukinApp(tester, clock: fixedClock(clockTime));
          final badgeText = _readTextByKey(tester, 'detected_timeslot_badge');
          expect(
            badgeText,
            contains(expectedLabel),
            reason: 'Clock $clockTime should show "$expectedLabel"',
          );
        }
      },
    );

    testWidgets(
      'T1-F7-05: tapping btn_start_workout generates menu and transitions to Screen A2',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));

        await tapKey(tester, 'btn_start_workout');

        expect(find.byKey(const Key('exercise_title')), findsOneWidget);
        expect(find.byKey(const Key('btn_next_workout')), findsOneWidget);
        expect(find.byKey(const Key('card_weight')), findsOneWidget);
        expect(find.byKey(const Key('card_reps')), findsOneWidget);
        expect(find.byKey(const Key('card_sets')), findsOneWidget);
        expect(find.byKey(const Key('btn_start_workout')), findsNothing);
      },
    );

    testWidgets(
      'T1-F7-06: course counts short=2, standard=4, full=5 are accurately reflected on Screen A2',
      (WidgetTester tester) async {
        final courses = <(String, int)>[
          ('course_short', 2),
          ('course_standard', 4),
          ('course_full', 5),
        ];

        for (final (courseKey, expectedCount) in courses) {
          await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
          await _startWorkoutFromA1(tester, courseKey: courseKey);

          final progressText = _readTextByKey(
            tester,
            'exercise_progress_badge',
          );
          expect(
            progressText.replaceAll(' ', ''),
            contains('/$expectedCount'),
            reason: '$courseKey should report total count $expectedCount',
          );

          final visitedTitles = await _advanceWorkoutToA3(tester);
          expect(
            visitedTitles.length,
            expectedCount,
            reason: '$courseKey should traverse $expectedCount exercises',
          );
        }
      },
    );
  });

  // ===========================================================================
  // F8: Screen A2 — In-Workout UI (`noukin_app` Port) (6 tests)
  // ===========================================================================
  group('F8: Screen A2 In-Workout UI (noukin_app Port)', () {
    testWidgets(
      'T1-F8-01: renders all contracted noukin_app keys, target muscles badge, and progress badge',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        const expectedKeys = <String>[
          'training_back_button',
          'btn_select_exercise',
          'exercise_title',
          'exercise_image',
          'target_muscles_badge',
          'exercise_progress_badge',
          'btn_next_workout',
          'card_weight',
          'card_reps',
          'card_sets',
          'btn_weight_down',
          'btn_weight_up',
          'btn_reps_down',
          'btn_reps_up',
          'btn_sets_down',
          'btn_sets_up',
        ];

        for (final k in expectedKeys) {
          expect(
            find.byKey(Key(k)),
            findsOneWidget,
            reason: 'Screen A2 must render contracted key "$k"',
          );
        }

        expect(_readTextByKey(tester, 'card_weight'), contains('重量'));
        expect(_readTextByKey(tester, 'card_reps'), contains('レップ数'));
        expect(_readTextByKey(tester, 'card_sets'), contains('セット数'));
        expectNoRenderOverflow(tester);
      },
    );

    testWidgets(
      'T1-F8-02: preserves noukin_app dark palette (#121212/#1E1E1E), #FF9100 CTA, and tealAccent values',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        expectDarkScaffoldTheme(tester);

        final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
        final appBarContext = tester.element(find.byType(AppBar).first);
        final resolvedAppBarBg =
            appBar.backgroundColor ??
            Theme.of(appBarContext).appBarTheme.backgroundColor;
        expect(resolvedAppBarBg, AppColors.surface);
        expect(
          appBar.elevation ?? Theme.of(appBarContext).appBarTheme.elevation ?? 0,
          0,
        );

        final nextBtnFinder = find.byKey(const Key('btn_next_workout'));
        expect(nextBtnFinder, findsOneWidget);
        expect(
          resolveEffectiveButtonBackgroundColor(tester, nextBtnFinder),
          AppColors.primaryAccent,
        );
        expect(
          resolveEffectiveButtonForegroundColor(tester, nextBtnFinder),
          AppColors.onPrimaryAccent,
        );

        for (final cardKey in const <String>[
          'card_weight',
          'card_reps',
          'card_sets',
        ]) {
          final cardFinder = find.byKey(Key(cardKey));
          expect(
            resolveEffectiveCardColor(tester, cardFinder),
            AppColors.surface,
          );

          final texts = tester.widgetList<Text>(
            find.descendant(of: cardFinder, matching: find.byType(Text)),
          );
          expect(
            texts.any((t) => t.style?.color == AppColors.tealAccent),
            isTrue,
            reason: '$cardKey value text must use AppColors.tealAccent',
          );
        }
      },
    );

    testWidgets(
      'T1-F8-03: ± counter cards adjust weight (±2.5kg), reps (±1), and sets (±1)',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        final initWeight = _readWeightFromCard(tester);
        final initReps = _readRepsFromCard(tester);
        final initSets = _readSetsFromCard(tester);

        await tapCounterButton(tester, 'card_weight', increment: true);
        expect(_readWeightFromCard(tester), initWeight + 2.5);
        await tapCounterButton(tester, 'card_weight', increment: false);
        expect(_readWeightFromCard(tester), initWeight);

        await tapCounterButton(tester, 'card_reps', increment: true);
        expect(_readRepsFromCard(tester), initReps + 1);
        await tapCounterButton(tester, 'card_reps', increment: false);
        expect(_readRepsFromCard(tester), initReps);

        await tapCounterButton(tester, 'card_sets', increment: true);
        expect(_readSetsFromCard(tester), initSets + 1);
        await tapCounterButton(tester, 'card_sets', increment: false);
        expect(_readSetsFromCard(tester), initSets);
      },
    );

    testWidgets(
      'T1-F8-04: btn_select_exercise opens swap bottom sheet and swaps active exercise',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        final initialTitle = _readTextByKey(tester, 'exercise_title');
        final initialMuscles = _readTextByKey(tester, 'target_muscles_badge');

        await tapKey(tester, 'btn_select_exercise');
        expect(find.byType(BottomSheet), findsOneWidget);

        final optionKeyFinder = find.byKey(
          const Key('swap_exercise_option_1'),
        );
        final optionFinder = optionKeyFinder.evaluate().isNotEmpty
            ? optionKeyFinder
            : find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(ListTile),
                  )
                  .at(1);
        await scrollAndTap(tester, optionFinder);

        expect(find.byType(BottomSheet), findsNothing);
        final swappedTitle = _readTextByKey(tester, 'exercise_title');
        final swappedMuscles = _readTextByKey(tester, 'target_muscles_badge');
        expect(swappedTitle, isNot(equals(initialTitle)));
        expect(
          swappedTitle != initialTitle || swappedMuscles != initialMuscles,
          isTrue,
        );
      },
    );

    testWidgets(
      'T1-F8-05: target_muscles_badge shows 〇/△ markers and exercise_progress_badge updates',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        final title1 = _readTextByKey(tester, 'exercise_title');
        final spec1 = kExpectedMachineSpecs.firstWhere(
          (m) => m.name == title1 || title1.contains(m.name),
        );
        final primaryName1 =
            kExpectedMuscleSpecById[spec1.primaryMuscleIds.first]!.name;

        final badgeText = _readTextByKey(tester, 'target_muscles_badge');
        expect(badgeText, contains('〇'));
        expect(badgeText, contains('△'));
        expect(badgeText, contains(primaryName1));

        final progress1 = _readTextByKey(tester, 'exercise_progress_badge');
        expect(progress1.replaceAll(' ', ''), contains('1/2'));

        // Advance to exercise 2 (1 tap if direct '次へ', 2 taps if '開始' -> '次へ')
        await tapKey(tester, 'btn_next_workout');
        if (_readTextByKey(tester, 'exercise_progress_badge')
            .replaceAll(' ', '')
            .contains('1/2')) {
          await tapKey(tester, 'btn_next_workout');
        }

        final progress2 = _readTextByKey(tester, 'exercise_progress_badge');
        expect(progress2.replaceAll(' ', ''), contains('2/2'));
        expect(_readTextByKey(tester, 'exercise_title'), isNot(equals(title1)));
      },
    );

    testWidgets(
      'T1-F8-06: btn_next_workout progresses through all exercises to Screen A3',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        final visited = await _advanceWorkoutToA3(tester);
        expect(visited.length, 2);

        expect(find.byKey(const Key('feedback_too_light')), findsOneWidget);
        expect(find.byKey(const Key('feedback_just_right')), findsOneWidget);
        expect(find.byKey(const Key('feedback_too_hard')), findsOneWidget);
        expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);
      },
    );
  });

  // ===========================================================================
  // F9: Screen A3 — Post-Workout Feedback & Save (6 tests)
  // ===========================================================================
  group('F9: Screen A3 Post-Workout Feedback & Save', () {
    testWidgets(
      'T1-F9-01: renders 3 feedback options and disables btn_finish_workout until selected',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');
        await _advanceWorkoutToA3(tester);

        expectDarkScaffoldTheme(tester);
        expect(find.byKey(const Key('feedback_too_light')), findsOneWidget);
        expect(find.byKey(const Key('feedback_just_right')), findsOneWidget);
        expect(find.byKey(const Key('feedback_too_hard')), findsOneWidget);
        expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);

        expect(
          _readTextByKey(tester, 'feedback_too_light'),
          contains('軽すぎた'),
        );
        expect(
          _readTextByKey(tester, 'feedback_just_right'),
          contains('ちょうど良かった'),
        );
        expect(
          _readTextByKey(tester, 'feedback_too_hard'),
          contains('キツすぎた'),
        );

        expect(
          _isButtonEnabled(tester, 'btn_finish_workout'),
          isFalse,
          reason:
              'btn_finish_workout must be disabled until a feedback choice is selected',
        );

        await tapKey(tester, 'feedback_just_right');
        expect(
          _isButtonEnabled(tester, 'btn_finish_workout'),
          isTrue,
          reason:
              'btn_finish_workout must be enabled after selecting a feedback choice',
        );
        expectNoRenderOverflow(tester);
      },
    );

    testWidgets(
      'T1-F9-02: feedback_too_light saves MachineHistoryEntry and adds +2.5kg next session',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        final result = await _runShortWorkoutWithFeedback(
          tester,
          feedbackKey: 'feedback_too_light',
        );

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final history = await repo.loadMachineHistory();
        final entry = history[result.machine.id]!;
        expect(entry.lastFeedback, WorkoutFeedback.tooLight);
        expect(entry.lastWeightKg, result.weightKg);

        // Ensure machine's muscles are recovered and boost its rotation so it is
        // selected in Session 2 to verify +2.5 kg prescription in Screen A2 UI.
        final states = await repo.loadMuscleStates();
        final updatedStates = Map<String, MuscleInputState>.from(states);
        for (final mId in result.machine.primaryMuscleIds) {
          updatedStates[mId] = updatedStates[mId]!.copyWith(blankDays: 6);
        }
        await repo.saveMuscleStates(updatedStates);
        final updatedHistory = Map<String, MachineHistoryEntry>.from(history);
        updatedHistory[result.machine.id] = entry.copyWith(
          sessionsSinceUsed: 25,
        );
        await repo.saveMachineHistory(updatedHistory);

        await restartNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');
        expect(_readTextByKey(tester, 'exercise_title'), result.machine.name);
        expect(_readWeightFromCard(tester), result.weightKg + 2.5);
      },
    );

    testWidgets(
      'T1-F9-03: feedback_too_hard drops next session weight by -2.5kg (clamped >= 2.5kg)',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        final result = await _runShortWorkoutWithFeedback(
          tester,
          feedbackKey: 'feedback_too_hard',
        );

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final history = await repo.loadMachineHistory();
        final entry = history[result.machine.id]!;
        expect(entry.lastFeedback, WorkoutFeedback.tooHard);
        expect(entry.lastWeightKg, result.weightKg);

        final states = await repo.loadMuscleStates();
        final updatedStates = Map<String, MuscleInputState>.from(states);
        for (final mId in result.machine.primaryMuscleIds) {
          updatedStates[mId] = updatedStates[mId]!.copyWith(blankDays: 6);
        }
        await repo.saveMuscleStates(updatedStates);
        final updatedHistory = Map<String, MachineHistoryEntry>.from(history);
        updatedHistory[result.machine.id] = entry.copyWith(
          sessionsSinceUsed: 25,
        );
        await repo.saveMachineHistory(updatedHistory);

        await restartNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');
        expect(_readTextByKey(tester, 'exercise_title'), result.machine.name);
        expect(
          _readWeightFromCard(tester),
          math.max(2.5, result.weightKg - 2.5),
        );
      },
    );

    testWidgets(
      'T1-F9-04: feedback_just_right preserves exact weight for next session',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        final result = await _runShortWorkoutWithFeedback(
          tester,
          feedbackKey: 'feedback_just_right',
        );

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final history = await repo.loadMachineHistory();
        final entry = history[result.machine.id]!;
        expect(entry.lastFeedback, WorkoutFeedback.justRight);
        expect(entry.lastWeightKg, result.weightKg);

        final states = await repo.loadMuscleStates();
        final updatedStates = Map<String, MuscleInputState>.from(states);
        for (final mId in result.machine.primaryMuscleIds) {
          updatedStates[mId] = updatedStates[mId]!.copyWith(blankDays: 6);
        }
        await repo.saveMuscleStates(updatedStates);
        final updatedHistory = Map<String, MachineHistoryEntry>.from(history);
        updatedHistory[result.machine.id] = entry.copyWith(
          sessionsSinceUsed: 25,
        );
        await repo.saveMachineHistory(updatedHistory);

        await restartNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');
        expect(_readTextByKey(tester, 'exercise_title'), result.machine.name);
        expect(_readWeightFromCard(tester), result.weightKg);
      },
    );

    testWidgets(
      'T1-F9-05: completing A3 advances B_i/S_i, saves session record, increments sessionCount, and returns to A1',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final initialCount = await repo.loadSessionCount();

        final result = await _runShortWorkoutWithFeedback(
          tester,
          feedbackKey: 'feedback_just_right',
        );

        // Returned to A1
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
        expect(find.byKey(const Key('btn_finish_workout')), findsNothing);

        final sessions = await repo.loadSessionHistory();
        expect(sessions.length, 1);
        expect(sessions.first.durationCourse, WorkoutDurationCourse.short20);
        expect(sessions.first.timeSlot, TimeSlot.morning);
        expect(sessions.first.feedback, WorkoutFeedback.justRight);
        expect(sessions.first.exercises.length, 2);

        final updatedCount = await repo.loadSessionCount();
        expect(updatedCount, initialCount + 1);

        final updatedMuscles = await repo.loadMuscleStates();
        for (final mId in result.machine.primaryMuscleIds) {
          expect(updatedMuscles[mId]!.blankDays, lessThanOrEqualTo(1));
          expect(updatedMuscles[mId]!.stimulationDays, greaterThan(2.0));
        }

        // Verify Screen B matrix also reflects the updated B_i/S_i
        await tapNavTab(tester, 'nav_tab_custom');
        final primaryId = result.machine.primaryMuscleIds.first;
        final rowFinder = find.byKey(Key('matrix_row_$primaryId'));
        await tester.scrollUntilVisible(
          rowFinder,
          200.0,
          scrollable: _findEffectiveScrollable(
            find.byKey(const Key('muscle_matrix_list')),
          ),
        );
        expect(rowFinder, findsOneWidget);
      },
    );

    testWidgets(
      'T1-F9-06: weight, rep, and set edits made on Screen A2 are persisted in WorkoutSessionRecord',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        await tapCounterButton(tester, 'card_weight', increment: true);
        await tapCounterButton(tester, 'card_weight', increment: true);
        await tapCounterButton(tester, 'card_reps', increment: true);
        await tapCounterButton(tester, 'card_sets', increment: false);

        final editedWeight = _readWeightFromCard(tester);
        final editedReps = _readRepsFromCard(tester);
        final editedSets = _readSetsFromCard(tester);

        await _advanceWorkoutToA3(tester);
        await tapKey(tester, 'feedback_just_right');
        await tapKey(tester, 'btn_finish_workout');

        final prefs = await SharedPreferences.getInstance();
        final sessions = await LocalWorkoutRepository(prefs).loadSessionHistory();
        expect(sessions.length, 1);
        final recorded = sessions.first.exercises.first;
        expect(recorded.weightKg, editedWeight);
        expect(recorded.reps, editedReps);
        expect(recorded.sets, editedSets);
      },
    );
  });

  // ===========================================================================
  // F10: Screen B — Custom Settings & 54-Muscle M-Matrix (6 tests)
  // ===========================================================================
  group('F10: Screen B Custom Settings & 54-Muscle Matrix', () {
    testWidgets(
      'T1-F10-01: purpose_selector lists all 6 purposes including ウィンドサーフィン and applies P_i template',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_custom');

        final selector = find.byKey(const Key('purpose_selector'));
        expect(selector, findsOneWidget);

        // Open dropdown if dropdown-backed, otherwise check inline labels
        final selectorWidget = tester.widget(selector);
        final hasDropdownDescendant = find
            .descendant(
              of: selector,
              matching: find.byWidgetPredicate(
                (w) => w is DropdownButton || w is DropdownButtonFormField,
              ),
            )
            .evaluate()
            .isNotEmpty;
        if (selectorWidget is DropdownButton ||
            selectorWidget is DropdownButtonFormField ||
            hasDropdownDescendant) {
          await tester.tap(selector);
          await tester.pumpAndSettle();
        }

        for (final purpose in TrainingPurpose.values) {
          expect(
            find.textContaining(purpose.label),
            findsAtLeastNWidgets(1),
            reason: 'Purpose "${purpose.label}" must be selectable',
          );
        }

        await tester.tap(find.textContaining('ウィンドサーフィン').last);
        await tester.pumpAndSettle();

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final profile = await repo.loadProfile();
        final states = await repo.loadMuscleStates();
        expect(profile?.purpose, TrainingPurpose.windsurfing);
        expect(states['m3']?.priorityP, 10);
        expect(states['m44']?.priorityP, 18);
      },
    );

    testWidgets(
      'T1-F10-02: injury_filter_section zeroes M-score and excludes affected machines from A1->A2',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_custom');

        expect(
          find.byKey(const Key('injury_filter_section')),
          findsOneWidget,
        );

        await tapKey(tester, 'injury_toggle_m0');
        await tapKey(tester, 'injury_toggle_m3');

        final prefs = await SharedPreferences.getInstance();
        final states = await LocalWorkoutRepository(prefs).loadMuscleStates();
        expect(states['m0']?.isInjured, isTrue);
        expect(states['m3']?.isInjured, isTrue);

        // Switch to Screen A and verify no prescribed machine involves m0 or m3
        await tapNavTab(tester, 'nav_tab_training');
        await _startWorkoutFromA1(tester, courseKey: 'course_full');
        final visitedTitles = await _advanceWorkoutToA3(tester);

        for (final title in visitedTitles) {
          final spec = kExpectedMachineSpecs.firstWhere(
            (m) => m.name == title || title.contains(m.name),
          );
          expect(
            spec.primaryMuscleIds.contains('m0') ||
                spec.synergistMuscleIds.contains('m0') ||
                spec.primaryMuscleIds.contains('m3') ||
                spec.synergistMuscleIds.contains('m3'),
            isFalse,
            reason:
                'Injured muscles m0/m3 must exclude ${spec.id} (${spec.name})',
          );
        }
      },
    );

    testWidgets(
      'T1-F10-03: group_batch_section updates P_i/B_i/S_i across all muscles in selected group',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_custom');

        expect(find.byKey(const Key('group_batch_section')), findsOneWidget);
        for (final group in MuscleGroup.values) {
          final groupFinder = find.byKey(Key('group_batch_${group.name}'));
          if (groupFinder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              groupFinder,
              200.0,
              scrollable: find.byType(Scrollable).first,
            );
          }
          expect(groupFinder, findsOneWidget);
        }

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final before = await repo.loadMuscleStates();

        await scrollToWidgetByKey(tester, 'group_batch_chest');
        final chestGroup = find.byKey(const Key('group_batch_chest'));
        await tester.ensureVisible(chestGroup);

        List<Finder> findIncrementButtonsIn(Finder root) {
          final iconAdds = find.descendant(
            of: root,
            matching: find.byIcon(Icons.add),
          );
          if (iconAdds.evaluate().isNotEmpty) {
            return List<Finder>.generate(
              iconAdds.evaluate().length,
              iconAdds.at,
            );
          }
          for (final label in const <String>['+1', '+5', '+']) {
            final textButtons = find.descendant(
              of: root,
              matching: find.byWidgetPredicate(
                (w) => w is ButtonStyleButton,
              ),
            );
            final matchingBtns = <Finder>[];
            for (var i = 0; i < textButtons.evaluate().length; i++) {
              final btnFinder = textButtons.at(i);
              if (_extractAllText(tester, btnFinder).contains(label)) {
                matchingBtns.add(btnFinder);
              }
            }
            if (matchingBtns.isNotEmpty) {
              return matchingBtns;
            }
            final exactLabelText = find.descendant(
              of: root,
              matching: find.text(label),
            );
            if (exactLabelText.evaluate().isNotEmpty) {
              return List<Finder>.generate(
                exactLabelText.evaluate().length,
                exactLabelText.at,
              );
            }
          }
          return const <Finder>[];
        }

        var chestControls = findIncrementButtonsIn(chestGroup);
        if (chestControls.isEmpty) {
          await tester.tap(chestGroup);
          await tester.pumpAndSettle();
          chestControls = findIncrementButtonsIn(chestGroup);
        }

        var tappedAny = false;
        if (chestControls.isNotEmpty) {
          for (final control in chestControls) {
            await tester.ensureVisible(control);
            await tester.tap(control);
            await tester.pumpAndSettle();
            tappedAny = true;
          }
        } else {
          // Section-level controls fallback (only when group_batch_chest is a
          // selector without child buttons): exclude any non-chest group_batch_*
          // subtrees and prefer chest-labeled rows if present.
          bool isInsideNonChestGroup(Element element) {
            var insideOther = false;
            element.visitAncestorElements((ancestor) {
              final key = ancestor.widget.key;
              if (key is ValueKey<String> &&
                  key.value.startsWith('group_batch_') &&
                  key.value != 'group_batch_chest' &&
                  key.value != 'group_batch_section') {
                insideOther = true;
                return false;
              }
              return true;
            });
            return insideOther;
          }

          bool hasChestAncestorRowWithoutOtherGroup(Element element) {
            var foundChestRow = false;
            element.visitAncestorElements((ancestor) {
              final widget = ancestor.widget;
              if (widget.key == const Key('group_batch_section')) {
                return false;
              }
              if (widget is Row || widget is Card || widget is ListTile) {
                final rowText = _extractAllText(
                  tester,
                  find.byElementPredicate((e) => identical(e, ancestor)),
                );
                if (rowText.contains('胸') &&
                    !rowText.contains('脚') &&
                    !rowText.contains('背中') &&
                    !rowText.contains('肩') &&
                    !rowText.contains('腕') &&
                    !rowText.contains('体幹')) {
                  foundChestRow = true;
                  return false;
                }
              }
              return true;
            });
            return foundChestRow;
          }

          final section = find.byKey(const Key('group_batch_section'));
          final sectionCandidates = findIncrementButtonsIn(section)
              .where(
                (f) =>
                    f.evaluate().isNotEmpty &&
                    !isInsideNonChestGroup(f.evaluate().first),
              )
              .toList();
          final chestLabeledCandidates = sectionCandidates
              .where(
                (f) => hasChestAncestorRowWithoutOtherGroup(f.evaluate().first),
              )
              .toList();
          final targetsToTap = chestLabeledCandidates.isNotEmpty
              ? chestLabeledCandidates
              : sectionCandidates;

          for (final control in targetsToTap) {
            await tester.ensureVisible(control);
            await tester.tap(control);
            await tester.pumpAndSettle();
            tappedAny = true;
          }
        }

        expect(
          tappedAny,
          isTrue,
          reason:
              'Expected increment controls in group_batch_chest or chest-scoped section controls',
        );

        final after = await repo.loadMuscleStates();
        final chestIds = kExpectedMuscleSpecs
            .where((m) => m.group == MuscleGroup.chest)
            .map((m) => m.id)
            .toList();
        final changedChest = chestIds.any(
          (id) =>
              after[id]!.blankDays != before[id]!.blankDays ||
              after[id]!.stimulationDays != before[id]!.stimulationDays ||
              after[id]!.priorityP != before[id]!.priorityP,
        );
        expect(
          changedChest,
          isTrue,
          reason: 'Chest batch controls must mutate chest muscle states',
        );
        // Non-chest muscle m0 must remain unchanged
        expect(after['m0'], before['m0']);
      },
    );

    testWidgets(
      'T1-F10-04: muscle_matrix_list displays all 54 muscles (m0..m53) with live M-score',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_custom');

        final matrix = find.byKey(const Key('muscle_matrix_list'));
        expect(matrix, findsOneWidget);

        final scrollable = _findEffectiveScrollable(matrix);
        final rowM0 = find.byKey(const Key('matrix_row_m0'));
        await tester.scrollUntilVisible(rowM0, 200.0, scrollable: scrollable);
        expect(_readTextByKey(tester, 'matrix_row_m0'), contains('大腿四頭筋'));
        expect(_readTextByKey(tester, 'matrix_row_m0'), contains('17.0'));

        for (final id in const <String>['m10', 'm27', 'm34', 'm44', 'm53']) {
          final row = find.byKey(Key('matrix_row_$id'));
          await tester.scrollUntilVisible(row, 250.0, scrollable: scrollable);
          expect(row, findsOneWidget);
          expect(
            _readTextByKey(tester, 'matrix_row_$id'),
            contains(kExpectedMuscleSpecById[id]!.name),
          );
        }
      },
    );

    testWidgets(
      'T1-F10-05: individual B_i/S_i edit on matrix_row_m0 updates M-score and persists across restart',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_custom');

        final matrix = find.byKey(const Key('muscle_matrix_list'));
        final scrollable = _findEffectiveScrollable(matrix);
        final rowM0 = find.byKey(const Key('matrix_row_m0'));
        await tester.scrollUntilVisible(rowM0, 200.0, scrollable: scrollable);

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final beforeM0 = (await repo.loadMuscleStates())['m0']!;

        final inlineAdds = find.descendant(
          of: rowM0,
          matching: find.byIcon(Icons.add),
        );
        if (inlineAdds.evaluate().isNotEmpty) {
          await tester.ensureVisible(inlineAdds.first);
          await tester.tap(inlineAdds.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tap(rowM0);
          await tester.pumpAndSettle();
          final modalAdds = find.byIcon(Icons.add);
          if (modalAdds.evaluate().isNotEmpty) {
            await tester.tap(modalAdds.first);
            await tester.pumpAndSettle();
          }
          final saveBtn = find.textContaining('保存');
          if (saveBtn.evaluate().isNotEmpty) {
            await tester.tap(saveBtn.last);
            await tester.pumpAndSettle();
          }
        }

        final afterM0 = (await repo.loadMuscleStates())['m0']!;
        expect(
          afterM0.blankDays != beforeM0.blankDays ||
              afterM0.stimulationDays != beforeM0.stimulationDays,
          isTrue,
        );

        await restartNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        final reloadedM0 = (await repo.loadMuscleStates())['m0']!;
        expect(reloadedM0, afterM0);
      },
    );

    testWidgets(
      'T1-F10-06: Screen B NEVER exposes 14日 cap or 0.75/0.45 overlap coefficients (R1)',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_custom');

        expect(find.textContaining('14日'), findsNothing);
        expect(find.textContaining('上限キャップ'), findsNothing);
        expect(find.textContaining('bCap'), findsNothing);
        expect(find.textContaining('0.75'), findsNothing);
        expect(find.textContaining('0.45'), findsNothing);
        expect(find.textContaining('重複制御'), findsNothing);
        expect(find.textContaining('Gym AI'), findsNothing);
      },
    );
  });

  // ===========================================================================
  // F11: Screen C — User Profile & Auth UI (6 tests)
  // ===========================================================================
  group('F11: Screen C User Profile & Auth UI', () {
    testWidgets(
      'T1-F11-01: renders Screen C profile/auth keys with birthYear-only input (no age brackets)',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_settings');

        expectDarkScaffoldTheme(tester);
        expect(find.byKey(const Key('gender_selector')), findsOneWidget);
        expect(find.byKey(const Key('birth_year_input')), findsOneWidget);
        expect(find.byKey(const Key('experience_selector')), findsOneWidget);
        expect(find.byKey(const Key('body_weight_input')), findsOneWidget);
        expect(find.byKey(const Key('btn_save_profile')), findsOneWidget);
        expect(find.byKey(const Key('btn_google_login')), findsOneWidget);

        // No age-bracket dropdown labels per R2
        expect(find.textContaining('10代・20代前半'), findsNothing);
        expect(find.textContaining('20代後半〜30代'), findsNothing);
        expect(find.textContaining('60代以上'), findsNothing);
        expectNoRenderOverflow(tester);
      },
    );

    testWidgets(
      'T1-F11-02: gender change auto-syncs bodyMakeMale <-> bodyMakeFemale in Screen B',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_settings');

        await _selectOptionInSelector(tester, 'gender_selector', '女性');
        await tapKey(tester, 'btn_save_profile');

        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        expect((await repo.loadProfile())?.purpose, TrainingPurpose.bodyMakeFemale);

        await tapNavTab(tester, 'nav_tab_custom');
        expect(
          _readTextByKey(tester, 'purpose_selector'),
          contains('女性向け'),
        );

        await tapNavTab(tester, 'nav_tab_settings');
        await _selectOptionInSelector(tester, 'gender_selector', '男性');
        await tapKey(tester, 'btn_save_profile');
        expect((await repo.loadProfile())?.purpose, TrainingPurpose.bodyMakeMale);
      },
    );

    testWidgets(
      'T1-F11-03: saving birthYear 1970 persists across restart and applies 50s 0.80 & 10->12 rules',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_settings');

        await _selectOptionInSelector(tester, 'gender_selector', '男性');
        await enterTextByKey(tester, 'birth_year_input', '1970');
        await _selectOptionInSelector(tester, 'experience_selector', '初級');
        await enterTextByKey(tester, 'body_weight_input', '65');
        await tapKey(tester, 'btn_save_profile');

        await restartNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        final prefs = await SharedPreferences.getInstance();
        final savedProfile = await LocalWorkoutRepository(prefs).loadProfile();
        expect(savedProfile?.birthYear, 1970);

        await tapNavTab(tester, 'nav_tab_training');
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        final title = _readTextByKey(tester, 'exercise_title');
        final spec = kExpectedMachineSpecs.firstWhere(
          (m) => m.name == title || title.contains(m.name),
        );
        final expectedWeight = oracleRoundTo25(
          65.0 * spec.bwFactor * 1.0 * 1.0 * 0.80,
        );
        expect(_readWeightFromCard(tester), expectedWeight);
        if (spec.baseReps == 10) {
          expect(_readRepsFromCard(tester), 12);
        }
      },
    );

    testWidgets(
      'T1-F11-04: saving intermediate experience and 80kg bodyWeight alters initial prescribed weights',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_settings');

        await _selectOptionInSelector(tester, 'gender_selector', '男性');
        await enterTextByKey(tester, 'birth_year_input', '1995');
        await _selectOptionInSelector(tester, 'experience_selector', '中級');
        await enterTextByKey(tester, 'body_weight_input', '80');
        await tapKey(tester, 'btn_save_profile');

        await tapNavTab(tester, 'nav_tab_training');
        await _startWorkoutFromA1(tester, courseKey: 'course_short');

        final title = _readTextByKey(tester, 'exercise_title');
        final spec = kExpectedMachineSpecs.firstWhere(
          (m) => m.name == title || title.contains(m.name),
        );
        final expectedWeight = oracleRoundTo25(
          80.0 * spec.bwFactor * 1.0 * 1.25 * 1.0,
        );
        expect(_readWeightFromCard(tester), expectedWeight);
      },
    );

    testWidgets(
      'T1-F11-05: btn_google_login signs into local fallback session offline',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_settings');

        expect(find.textContaining('ローカル'), findsAtLeastNWidgets(1));
        await tapKey(tester, 'btn_google_login');

        expect(find.byKey(const Key('btn_logout')), findsOneWidget);

        final prefs = await SharedPreferences.getInstance();
        final user = await LocalAuthService(prefs).getCurrentUser();
        expect(user, isNotNull);
        expect(user!.isLocalFallback, isTrue);
      },
    );

    testWidgets(
      'T1-F11-06: btn_logout signs out cleanly and restores signed-out UI',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockDaytime1300));
        await tapNavTab(tester, 'nav_tab_settings');

        await tapKey(tester, 'btn_google_login');
        expect(find.byKey(const Key('btn_logout')), findsOneWidget);

        await tapKey(tester, 'btn_logout');
        expect(find.byKey(const Key('btn_google_login')), findsOneWidget);

        final prefs = await SharedPreferences.getInstance();
        expect(await LocalAuthService(prefs).getCurrentUser(), isNull);
      },
    );
  });

  // ===========================================================================
  // F12: App Shell, Persistence, Supabase Config/SQL, Local Fallback & R1 (6 tests)
  // ===========================================================================
  group('F12: App Shell, Persistence, Supabase & R1 Compliance', () {
    testWidgets(
      'T1-F12-01: NoukinApp renders dark theme, のう筋（Noukin） branding, and 3-tab navigation',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));

        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        expect(materialApp.title, 'のう筋（Noukin）');
        expectDarkScaffoldTheme(tester);
        expect(find.byType(NoukinApp), findsOneWidget);
        expect(find.textContaining('のう筋'), findsAtLeastNWidgets(1));

        expect(find.byKey(const Key('nav_tab_training')), findsOneWidget);
        expect(find.byKey(const Key('nav_tab_custom')), findsOneWidget);
        expect(find.byKey(const Key('nav_tab_settings')), findsOneWidget);

        await tapKey(tester, 'course_full');
        await tapNavTab(tester, 'nav_tab_custom');
        expect(find.byKey(const Key('purpose_selector')), findsOneWidget);

        await tapNavTab(tester, 'nav_tab_settings');
        expect(find.byKey(const Key('birth_year_input')), findsOneWidget);

        await tapNavTab(tester, 'nav_tab_training');
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
        expectNoRenderOverflow(tester);
      },
    );

    test(
      'T1-F12-02: SupabaseConfig.isConfigured is false by default and .env.example has template keys only',
      () {
        expect(SupabaseConfig.url, isEmpty);
        expect(SupabaseConfig.anonKey, isEmpty);
        expect(SupabaseConfig.isConfigured, isFalse);

        expect(projectFileExists('.env.example'), isTrue);
        final envExample = readProjectFile('.env.example');
        expect(envExample, contains('SUPABASE_URL'));
        expect(envExample, contains('SUPABASE_ANON_KEY'));
        expect(
          RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+').hasMatch(envExample),
          isFalse,
        );
      },
    );

    test(
      'T1-F12-03: LocalWorkoutRepository round-trips all 5 domain entities via SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final repo1 = LocalWorkoutRepository(prefs);

        final profile = buildTestProfile(
          id: 'u-roundtrip',
          gender: Gender.female,
          birthYear: 1990,
          experience: ExperienceLevel.intermediate,
          bodyWeightKg: 56.5,
          purpose: TrainingPurpose.tennis,
          isFirstTime: false,
          email: 'local@noukin.app',
        );
        final muscleStates = buildDefaultMuscleStates(
          TrainingPurpose.tennis,
          injuredIds: const <String>{'m0', 'm34'},
          blankDays: 7,
          stimulationDays: 1.5,
        );
        final machineHistory = buildDefaultMachineHistory(
          overrides: const <String, MachineHistoryEntry>{
            'mac1': MachineHistoryEntry(
              machineId: 'mac1',
              sessionsSinceUsed: 0,
              lastWeightKg: 62.5,
              lastFeedback: WorkoutFeedback.tooLight,
            ),
          },
        );
        final session = WorkoutSessionRecord(
          id: 'sess-rt-1',
          completedAt: DateTime.utc(2026, 11, 19, 10, 0),
          durationCourse: WorkoutDurationCourse.standard45,
          condition: WorkoutCondition.great,
          timeSlot: TimeSlot.morning,
          focusMuscleId: 'm4',
          exercises: const <CompletedExerciseRecord>[
            CompletedExerciseRecord(
              machineId: 'mac1',
              machineName: 'レッグプレス',
              weightKg: 62.5,
              reps: 10,
              sets: 3,
            ),
          ],
          feedback: WorkoutFeedback.tooLight,
          createdAt: DateTime.utc(2026, 11, 19, 10, 45),
        );

        await repo1.saveProfile(profile);
        await repo1.saveMuscleStates(muscleStates);
        await repo1.saveMachineHistory(machineHistory);
        await repo1.saveSessionRecord(session);
        await repo1.saveSessionCount(7);

        final repo2 = LocalWorkoutRepository(prefs);
        expect(await repo2.loadProfile(), profile);
        expect(await repo2.loadMuscleStates(), muscleStates);
        expect(await repo2.loadMachineHistory(), machineHistory);
        expect(await repo2.loadSessionHistory(), <WorkoutSessionRecord>[
          session,
        ]);
        expect(await repo2.loadSessionCount(), 7);
      },
    );

    test(
      'T1-F12-04: LocalAuthService completes offline sign-in, persistence, and sign-out lifecycle',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final auth = LocalAuthService(prefs);

        expect(auth.isLocalFallbackMode, isTrue);

        await runWithoutNetwork(() async {
          expect(await auth.getCurrentUser(), isNull);

          final user = await auth.signInWithGoogle();
          expect(user.id, isNotEmpty);
          expect(user.isLocalFallback, isTrue);

          final reloaded = await LocalAuthService(prefs).getCurrentUser();
          expect(reloaded?.id, user.id);

          await auth.signOut();
          expect(await auth.getCurrentUser(), isNull);
        });
      },
    );

    test(
      'T1-F12-05: 001_initial_schema.sql defines 4 tables, PKs, auth.users FK, and auth.uid() = user_id RLS',
      () {
        const schemaPath = 'supabase/migrations/001_initial_schema.sql';
        expect(projectFileExists(schemaPath), isTrue);

        final sql = readProjectFile(schemaPath).toLowerCase();
        for (final table in const <String>[
          'user_profiles',
          'muscle_states',
          'machine_history',
          'workout_sessions',
        ]) {
          expect(
            RegExp('create\\s+table[^;]*$table').hasMatch(sql),
            isTrue,
            reason: 'Missing CREATE TABLE for $table',
          );
          expect(
            RegExp('alter\\s+table[^;]*$table[^;]*enable\\s+row\\s+level\\s+security')
                .hasMatch(sql),
            isTrue,
            reason: 'Missing RLS enable statement for $table',
          );
          expect(
            RegExp('create\\s+policy[^;]*on[^;]*$table').hasMatch(sql),
            isTrue,
            reason: 'Missing CREATE POLICY for $table',
          );
        }

        expect(sql, contains('references auth.users'));
        expect(
          RegExp(r'auth\.uid\(\)\s*=\s*user_id').allMatches(sql).length,
          greaterThanOrEqualTo(4),
        );
        expect(sql, contains('primary key'));
      },
    );

    test(
      'T1-F12-06: R1 static compliance scan on pubspec.yaml and lib/ confirms zero prohibited symbols',
      () {
        final pubspec = readProjectFile('pubspec.yaml');
        expect(pubspec, contains('name: noukin'));
        expect(pubspec, isNot(contains('button_controll_test')));
        expect(pubspec, isNot(contains('flutter_tts')));
        expect(pubspec, isNot(contains('audio_session')));

        final dartFiles = listProjectFiles('lib', extension: '.dart');
        expect(dartFiles, isNotEmpty);

        final prohibitedPatterns = <RegExp>[
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
          RegExp(r'_buildVolumeCard'),
          RegExp(r'_buildMediaControlBar'),
          RegExp(r'api\.openai\.com'),
          RegExp(r'api\.anthropic\.com'),
          RegExp(r'generativelanguage\.googleapis\.com'),
          RegExp(r'サウナ'),
          RegExp(r'ランニングトラッカー'),
        ];

        for (final file in dartFiles) {
          final content = file.readAsStringSync();
          for (final pattern in prohibitedPatterns) {
            expect(
              pattern.hasMatch(content),
              isFalse,
              reason:
                  'Prohibited R1 pattern ${pattern.pattern} found in ${file.path}',
            );
          }
        }
      },
    );
  });
}
