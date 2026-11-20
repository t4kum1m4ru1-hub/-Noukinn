import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/config/supabase_config.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/engine/workout_menu_generator.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/services/auth_service.dart';
import 'package:noukin/services/workout_repository.dart';
import 'package:noukin/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_test_helpers.dart';

typedef _SeededHarness = ({
  SharedPreferences prefs,
  LocalWorkoutRepository repo,
  LocalAuthService auth,
  AppState appState,
});

Future<_SeededHarness> _createSeededAppState({
  DateTime Function()? clock,
  UserProfile? profile,
  Map<String, MuscleInputState>? muscleStates,
  Map<String, MachineHistoryEntry>? machineHistory,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final repo = LocalWorkoutRepository(prefs);
  final auth = LocalAuthService(prefs);
  if (profile != null) {
    await repo.saveProfile(profile);
  }
  if (muscleStates != null) {
    await repo.saveMuscleStates(muscleStates);
  }
  if (machineHistory != null) {
    await repo.saveMachineHistory(machineHistory);
  }
  final appState = AppState(
    authService: auth,
    repository: repo,
    clock: clock,
  );
  await appState.initialize();
  return (prefs: prefs, repo: repo, auth: auth, appState: appState);
}

String _extractText(WidgetTester tester, Finder root) {
  expect(root, findsAtLeastNWidgets(1));
  final widget = tester.widget(root.first);
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  final texts = find.descendant(
    of: root.first,
    matching: find.byType(Text),
  );
  return tester
      .widgetList<Text>(texts)
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' ');
}

double _readCardWeight(WidgetTester tester) {
  final text = _extractText(tester, find.byKey(const Key('card_weight')));
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*kg').firstMatch(text);
  expect(
    match,
    isNotNull,
    reason: 'Expected kg value inside card_weight, got: "$text"',
  );
  return double.parse(match!.group(1)!);
}

int _readCardReps(WidgetTester tester) {
  final text = _extractText(tester, find.byKey(const Key('card_reps')));
  final match = RegExp(r'(\d+)\s*回').firstMatch(text);
  expect(
    match,
    isNotNull,
    reason: 'Expected rep count inside card_reps, got: "$text"',
  );
  return int.parse(match!.group(1)!);
}

int _readCardSets(WidgetTester tester) {
  final text = _extractText(tester, find.byKey(const Key('card_sets')));
  final match = RegExp(r'(\d+)\s*セット').firstMatch(text);
  expect(
    match,
    isNotNull,
    reason: 'Expected set count inside card_sets, got: "$text"',
  );
  return int.parse(match!.group(1)!);
}

Future<void> _selectOptionInside(
  WidgetTester tester,
  String containerKey,
  String optionText,
) async {
  await selectOptionInControl(tester, containerKey, optionText);
}

Future<void> _clearFocusDropdownToNone(WidgetTester tester) async {
  await scrollToWidgetByKey(tester, 'focus_muscle_dropdown');
  final dropdownRoot = find.byKey(const Key('focus_muscle_dropdown'));
  expect(dropdownRoot, findsAtLeastNWidgets(1));

  final dropdownDescendant = find.descendant(
    of: dropdownRoot.first,
    matching: find.byWidgetPredicate(
      (w) => w is DropdownButton || w is DropdownButtonFormField,
    ),
  );
  final rootWidget = tester.widget(dropdownRoot.first);
  final tapTarget =
      (rootWidget is DropdownButton ||
          rootWidget is DropdownButtonFormField ||
          dropdownDescendant.evaluate().isEmpty)
      ? dropdownRoot.first
      : dropdownDescendant.first;

  await tester.ensureVisible(tapTarget);
  await tester.tap(tapTarget);
  await tester.pumpAndSettle();

  final clearLabel = find.textContaining('指定なし');
  final noneLabel = find.textContaining('なし');
  final nullItem = find.byWidgetPredicate(
    (w) => w is DropdownMenuItem<String?> && w.value == null,
  );

  Finder? pickVisibleTarget() {
    for (final candidate in <Finder>[clearLabel, noneLabel, nullItem]) {
      final hit = candidate.hitTestable();
      if (hit.evaluate().isNotEmpty) {
        return hit.last;
      }
      if (candidate.evaluate().isNotEmpty) {
        return candidate.last;
      }
    }
    return null;
  }

  var target = pickVisibleTarget();
  if (target == null) {
    final scrollableElements = find
        .byType(Scrollable)
        .evaluate()
        .toList(growable: false);
    for (final element in scrollableElements.reversed) {
      final scrollableFinder = find.byWidget(element.widget);
      for (final delta in const <double>[-180.0, 180.0]) {
        for (final candidate in <Finder>[clearLabel, noneLabel, nullItem]) {
          try {
            await tester.scrollUntilVisible(
              candidate,
              delta,
              scrollable: scrollableFinder,
              maxScrolls: 60,
            );
            target = pickVisibleTarget();
            if (target != null) {
              break;
            }
          } catch (_) {
            // Try opposite direction or next candidate.
          }
        }
        if (target != null) {
          break;
        }
      }
      if (target != null) {
        break;
      }
    }
  }

  expect(
    target,
    isNotNull,
    reason: 'Expected clear/none option in focus_muscle_dropdown',
  );
  await tester.ensureVisible(target!);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _completeCurrentWorkoutToA3(
  WidgetTester tester,
  int exerciseCount,
) async {
  await advanceWorkoutToA3(tester, expectedCount: exerciseCount);
}

Future<void> _scrollToWidgetKey(
  WidgetTester tester,
  String key, {
  String? preferredContainerKey,
  double delta = 220.0,
}) async {
  await scrollToWidgetByKey(
    tester,
    key,
    preferredContainerKey:
        preferredContainerKey ??
        (key.startsWith('matrix_row_') ? 'muscle_matrix_list' : null),
    delta: delta,
  );
}

Finder _findInteractiveTextButtons(
  Finder scope,
  Set<String> labels,
) {
  return find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) {
      if (w is! Text) {
        return false;
      }
      final label = (w.data ?? '').trim();
      return labels.contains(label);
    }),
  );
}

Future<bool> _tryEditMatrixRow(
  WidgetTester tester,
  String muscleId, {
  bool? incrementB,
  bool? incrementS,
  String? enterBText,
  String? enterSText,
}) async {
  await _scrollToWidgetKey(tester, 'matrix_row_$muscleId');
  final row = find.byKey(Key('matrix_row_$muscleId'));

  Future<bool> applyInScope(Finder scope) async {
    final textFields = find.descendant(
      of: scope,
      matching: find.byType(TextField),
    );
    if (textFields.evaluate().length >= 2) {
      if (enterBText != null) {
        await tester.ensureVisible(textFields.at(0));
        await tester.enterText(textFields.at(0), enterBText);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      if (enterSText != null) {
        await tester.ensureVisible(textFields.at(1));
        await tester.enterText(textFields.at(1), enterSText);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      return true;
    }

    final minusIcons = find.descendant(
      of: scope,
      matching: find.byIcon(Icons.remove),
    );
    final plusIcons = find.descendant(
      of: scope,
      matching: find.byIcon(Icons.add),
    );
    if (minusIcons.evaluate().isNotEmpty && plusIcons.evaluate().isNotEmpty) {
      if (incrementB != null) {
        final target = incrementB ? plusIcons.first : minusIcons.first;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      if (incrementS != null) {
        if (minusIcons.evaluate().length < 2 ||
            plusIcons.evaluate().length < 2) {
          return false;
        }
        final target = incrementS ? plusIcons.at(1) : minusIcons.at(1);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      return true;
    }

    final minusTexts = _findInteractiveTextButtons(
      scope,
      const <String>{'-1', '-0.1', '-0.5', '-', '−'},
    );
    final plusTexts = _findInteractiveTextButtons(
      scope,
      const <String>{'+1', '+0.1', '+0.5', '+'},
    );
    if (minusTexts.evaluate().isNotEmpty && plusTexts.evaluate().isNotEmpty) {
      if (incrementB != null) {
        final exactB = _findInteractiveTextButtons(
          scope,
          incrementB ? const <String>{'+1'} : const <String>{'-1'},
        );
        final target = exactB.evaluate().isNotEmpty
            ? exactB.first
            : (incrementB ? plusTexts.first : minusTexts.first);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      if (incrementS != null) {
        final exactS = _findInteractiveTextButtons(
          scope,
          incrementS
              ? const <String>{'+0.1', '+0.5'}
              : const <String>{'-0.1', '-0.5'},
        );
        Finder? target;
        if (exactS.evaluate().isNotEmpty) {
          target = exactS.first;
        } else if (minusTexts.evaluate().length >= 2 &&
            plusTexts.evaluate().length >= 2) {
          target = incrementS ? plusTexts.at(1) : minusTexts.at(1);
        }
        if (target == null) {
          return false;
        }
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      return true;
    }
    return false;
  }

  if (await applyInScope(row)) {
    return true;
  }

  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();

  var dialogOrSheet = find.byWidgetPredicate(
    (w) => w is AlertDialog || w is Dialog || w is BottomSheet,
  );
  if (dialogOrSheet.evaluate().isEmpty) {
    final editIcon = find.descendant(
      of: row,
      matching: find.byIcon(Icons.edit),
    );
    if (editIcon.evaluate().isNotEmpty) {
      await tester.ensureVisible(editIcon.first);
      await tester.tap(editIcon.first);
      await tester.pumpAndSettle();
      dialogOrSheet = find.byWidgetPredicate(
        (w) => w is AlertDialog || w is Dialog || w is BottomSheet,
      );
    }
  }

  if (dialogOrSheet.evaluate().isNotEmpty) {
    final applied = await applyInScope(dialogOrSheet.last);
    final confirmButtons = find.descendant(
      of: dialogOrSheet.last,
      matching: find.byWidgetPredicate(
        (w) =>
            w is TextButton || w is ElevatedButton || w is FilledButton,
      ),
    );
    if (confirmButtons.evaluate().isNotEmpty) {
      final saveMatch = find.descendant(
        of: dialogOrSheet.last,
        matching: find.textContaining('保存'),
      );
      final applyMatch = find.descendant(
        of: dialogOrSheet.last,
        matching: find.textContaining('適用'),
      );
      final okMatch = find.descendant(
        of: dialogOrSheet.last,
        matching: find.textContaining('OK'),
      );
      final closeMatch = find.descendant(
        of: dialogOrSheet.last,
        matching: find.textContaining('閉じる'),
      );
      final btn = saveMatch.evaluate().isNotEmpty
          ? saveMatch.last
          : (applyMatch.evaluate().isNotEmpty
                ? applyMatch.last
                : (okMatch.evaluate().isNotEmpty
                      ? okMatch.last
                      : (closeMatch.evaluate().isNotEmpty
                            ? closeMatch.last
                            : confirmButtons.last)));
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }
    return applied;
  }
  return false;
}

void main() {
  // ===========================================================================
  // F7: Screen A1 — Pre-Workout Step Form Boundaries (6 tests)
  // ===========================================================================
  group('F7 Screen A1 Pre-Workout Boundaries', () {
    testWidgets(
      'T2-F7-01: 04:59 (就寝前) vs 05:00 (朝) and daytime/evening boundaries reflected in detected_timeslot_badge',
      (WidgetTester tester) async {
        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockBoundary045959),
        );
        expect(
          _extractText(tester, find.byKey(const Key('detected_timeslot_badge'))),
          contains('就寝前'),
        );

        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockBoundary0500),
        );
        expect(
          _extractText(tester, find.byKey(const Key('detected_timeslot_badge'))),
          contains('朝'),
        );

        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockBoundary145959),
        );
        expect(
          _extractText(tester, find.byKey(const Key('detected_timeslot_badge'))),
          contains('日中'),
        );

        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockBoundary205959),
        );
        expect(
          _extractText(tester, find.byKey(const Key('detected_timeslot_badge'))),
          contains('夕方'),
        );
      },
    );

    testWidgets(
      'T2-F7-02: All-injured empty menu safe guard on btn_start_workout avoids crash and stays safely on Screen A1',
      (WidgetTester tester) async {
        final allInjuredIds = kExpectedMuscleSpecs.map((m) => m.id).toSet();
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          muscleStates: buildDefaultMuscleStates(
            TrainingPurpose.bodyMakeMale,
            injuredIds: allInjuredIds,
          ),
        );

        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'btn_start_workout');

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
        expect(find.byKey(const Key('exercise_title')), findsNothing);
        expect(seeded.appState.sessionHistory, isEmpty);
      },
    );

    testWidgets(
      'T2-F7-03: Clearing focusMuscle back to none resets focus boost on generated menu',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockDaytime1300),
          profile: buildTestProfile(
            gender: Gender.male,
            purpose: TrainingPurpose.bodyMakeMale,
          ),
          muscleStates: buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale),
          machineHistory: buildDefaultMachineHistory(),
        );

        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockDaytime1300),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');
        final baselineTitle = _extractText(
          tester,
          find.byKey(const Key('exercise_title')),
        );
        final baselineMachineIds = seeded.appState.lastMenuResult!.exercises
            .map((e) => e.machine.id)
            .toList();

        await tapKey(tester, 'training_back_button');

        await selectDropdownOption(
          tester,
          'focus_muscle_dropdown',
          '三角筋中部',
        );
        await tapKey(tester, 'btn_start_workout');
        final focusedTitle = _extractText(
          tester,
          find.byKey(const Key('exercise_title')),
        );
        expect(
          focusedTitle,
          anyOf(contains('ショルダープレス'), contains('サイドレイズ')),
        );
        expect(focusedTitle, isNot(equals(baselineTitle)));

        await tapKey(tester, 'training_back_button');
        await _clearFocusDropdownToNone(tester);
        await tapKey(tester, 'btn_start_workout');

        final clearedMachineIds = seeded.appState.lastMenuResult!.exercises
            .map((e) => e.machine.id)
            .toList();
        expect(clearedMachineIds, equals(baselineMachineIds));
      },
    );

    testWidgets(
      'T2-F7-04: Screen A1 exposes zero manual timeSlot override controls',
      (WidgetTester tester) async {
        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockMorning0800),
        );

        expect(
          find.byKey(const Key('detected_timeslot_badge')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('detected_timeslot_badge')),
            matching: find.byWidgetPredicate(
              (w) => w is DropdownButton || w is DropdownButtonFormField,
            ),
          ),
          findsNothing,
        );
        expect(find.text('日中'), findsNothing);
        expect(find.text('夕方'), findsNothing);
        expect(find.text('就寝前'), findsNothing);
        expect(find.textContaining('時間帯を変更'), findsNothing);
      },
    );

    testWidgets(
      'T2-F7-05: Re-entering Screen A1 after workout completion displays clean ready-to-start state',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');
        await _completeCurrentWorkoutToA3(tester, 2);

        await tapKey(tester, 'feedback_just_right');
        await tapKey(tester, 'btn_finish_workout');

        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
        expect(find.byKey(const Key('course_short')), findsOneWidget);
        expect(find.byKey(const Key('condition_normal')), findsOneWidget);
        expect(find.byKey(const Key('exercise_title')), findsNothing);
        expect(find.byKey(const Key('btn_finish_workout')), findsNothing);

        await tapKey(tester, 'btn_start_workout');
        expect(find.byKey(const Key('exercise_title')), findsOneWidget);
        expect(
          _extractText(tester, find.byKey(const Key('exercise_progress_badge'))),
          contains('1 / 2'),
        );
      },
    );

    testWidgets(
      'T2-F7-06: Mobile (360x640) and desktop (1280x800) viewports render Screen A1 with zero overflow',
      (WidgetTester tester) async {
        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockEvening1800),
          viewportSize: const Size(360, 640),
        );
        expectNoRenderOverflow(tester);
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);

        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockEvening1800),
          viewportSize: const Size(1280, 800),
        );
        expectNoRenderOverflow(tester);
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
      },
    );
  });

  // ===========================================================================
  // F8: Screen A2 — In-Workout UI Boundaries & R1 Checks (6 tests)
  // ===========================================================================
  group('F8 Screen A2 In-Workout Boundaries & R1', () {
    testWidgets(
      'T2-F8-01: Counter lower-bound clamps enforce weight >= 2.5 kg, reps >= 1, sets >= 1',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          profile: buildTestProfile(
            gender: Gender.female,
            birthYear: 1960,
            experience: ExperienceLevel.beginner,
            bodyWeightKg: 40.0,
            purpose: TrainingPurpose.bodyMakeFemale,
          ),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');

        final initialWeight = _readCardWeight(tester);
        final weightDownTaps = (initialWeight / 2.5).ceil() + 3;
        for (var i = 0; i < weightDownTaps; i++) {
          await tapCounterButton(tester, 'card_weight', increment: false);
        }
        await tester.pumpAndSettle();
        expect(_readCardWeight(tester), equals(2.5));

        final initialReps = _readCardReps(tester);
        for (var i = 0; i < initialReps + 3; i++) {
          await tapCounterButton(tester, 'card_reps', increment: false);
        }
        await tester.pumpAndSettle();
        expect(_readCardReps(tester), equals(1));

        final initialSets = _readCardSets(tester);
        for (var i = 0; i < initialSets + 3; i++) {
          await tapCounterButton(tester, 'card_sets', increment: false);
        }
        await tester.pumpAndSettle();
        expect(_readCardSets(tester), equals(1));
      },
    );

    testWidgets(
      'T2-F8-02: Missing or .avif asset errorBuilder renders Icons.fitness_center fallback without uncaught exception',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));
        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);

        final imageFinder = find.byKey(const Key('exercise_image'));
        expect(imageFinder, findsOneWidget);

        final widget = tester.widget(imageFinder);
        final hasIconChild = find
            .descendant(
              of: imageFinder,
              matching: find.byIcon(Icons.fitness_center),
            )
            .evaluate()
            .isNotEmpty;
        final isIconSelf =
            widget is Icon && widget.icon == Icons.fitness_center;
        expect(hasIconChild || isIconSelf, isTrue);
      },
    );

    testWidgets(
      'T2-F8-03: R1 UI negative assertions confirm zero TTS slider, media control bar, or TutorialScreen elements',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));
        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');

        const prohibitedKeys = <String>[
          'card_volume',
          'volume_slider',
          'volume_value_text',
          'media_control_bar',
          'training_mode_indicator',
          'btn_media_prev',
          'btn_media_play_pause',
          'btn_media_next',
          'btn_media_vol_down',
          'btn_media_vol_up',
        ];
        for (final key in prohibitedKeys) {
          expect(find.byKey(Key(key)), findsNothing);
        }

        expect(find.byType(Slider), findsNothing);
        expect(find.textContaining('音声ガイド'), findsNothing);
        expect(find.textContaining('チュートリアル'), findsNothing);
        expect(find.textContaining('状態A'), findsNothing);
        expect(find.textContaining('状態B'), findsNothing);
        expect(find.textContaining('状態C'), findsNothing);
        expect(find.textContaining('Gym AI'), findsNothing);
      },
    );

    testWidgets(
      'T2-F8-04: training_back_button aborts cleanly without persisting incomplete session',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        final initialSessionCount = seeded.appState.sessionCount;

        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');

        await tapCounterButton(tester, 'card_weight', increment: true);
        await advanceToNextExercise(tester);
        await tapKey(tester, 'training_back_button');

        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
        expect(seeded.appState.sessionHistory, isEmpty);
        expect(seeded.appState.sessionCount, equals(initialSessionCount));
        expect(await seeded.repo.loadSessionHistory(), isEmpty);
      },
    );

    testWidgets(
      'T2-F8-05: Swapping active exercise with itself in swap bottom sheet is a safe no-op',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));
        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');

        final initialTitle = _extractText(
          tester,
          find.byKey(const Key('exercise_title')),
        );
        final initialWeight = _readCardWeight(tester);
        final initialProgress = _extractText(
          tester,
          find.byKey(const Key('exercise_progress_badge')),
        );
        final initialMuscles = _extractText(
          tester,
          find.byKey(const Key('target_muscles_badge')),
        );

        await tapKey(tester, 'btn_select_exercise');
        final option = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining(initialTitle),
        );
        expect(option, findsAtLeastNWidgets(1));
        await tester.tap(option.last);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          _extractText(tester, find.byKey(const Key('exercise_title'))),
          equals(initialTitle),
        );
        expect(_readCardWeight(tester), equals(initialWeight));
        expect(
          _extractText(tester, find.byKey(const Key('exercise_progress_badge'))),
          equals(initialProgress),
        );
        expect(
          _extractText(tester, find.byKey(const Key('target_muscles_badge'))),
          equals(initialMuscles),
        );
      },
    );

    testWidgets(
      'T2-F8-06: Weight, rep, and set edits on exercise 1 remain isolated from exercise 2',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');

        final ex2Prescribed = seeded.appState.lastMenuResult!.exercises[1];

        await tapCounterButton(tester, 'card_weight', increment: true);
        await tapCounterButton(tester, 'card_weight', increment: true);
        await tapCounterButton(tester, 'card_reps', increment: true);
        await tapCounterButton(tester, 'card_sets', increment: false);
        await tester.pumpAndSettle();

        await advanceToNextExercise(tester);

        expect(
          _extractText(tester, find.byKey(const Key('exercise_title'))),
          contains(ex2Prescribed.machine.name),
        );
        expect(_readCardWeight(tester), equals(ex2Prescribed.weightKg));
        expect(_readCardReps(tester), equals(ex2Prescribed.reps));
        expect(_readCardSets(tester), equals(ex2Prescribed.sets));
      },
    );
  });

  // ===========================================================================
  // F9: Screen A3 — Post-Workout Feedback & Save Boundaries (6 tests)
  // ===========================================================================
  group('F9 Screen A3 Feedback & Save Boundaries', () {
    testWidgets(
      'T2-F9-01: btn_finish_workout is disabled until a feedback option is selected',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');
        await _completeCurrentWorkoutToA3(tester, 2);

        final finishBtnFinder = find.byKey(const Key('btn_finish_workout'));
        final btnWidget = tester.widget(finishBtnFinder);
        if (btnWidget is ButtonStyleButton) {
          expect(btnWidget.onPressed, isNull);
        }

        await tester.tap(finishBtnFinder, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(seeded.appState.sessionHistory, isEmpty);
        expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);

        await tapKey(tester, 'feedback_just_right');
        final enabledWidget = tester.widget(finishBtnFinder);
        if (enabledWidget is ButtonStyleButton) {
          expect(enabledWidget.onPressed, isNotNull);
        }
      },
    );

    testWidgets(
      'T2-F9-02: Changing feedback choice before btn_finish_workout saves only final selection',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');
        await _completeCurrentWorkoutToA3(tester, 2);

        await tapKey(tester, 'feedback_too_light');
        await tapKey(tester, 'feedback_too_hard');
        await tapKey(tester, 'feedback_just_right');
        await tapKey(tester, 'btn_finish_workout');

        expect(seeded.appState.sessionHistory, hasLength(1));
        expect(
          seeded.appState.sessionHistory.single.feedback,
          equals(WorkoutFeedback.justRight),
        );
        final savedIds = seeded.appState.sessionHistory.single.exercises
            .map((e) => e.machineId)
            .toList();
        for (final id in savedIds) {
          expect(
            seeded.appState.machineHistory[id]?.lastFeedback,
            equals(WorkoutFeedback.justRight),
          );
        }
      },
    );

    testWidgets(
      'T2-F9-03: Next workout state reflects sessionsSinceUsed == 0 on completed machines and +1 on unpicked',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        final beforeOffsets = <String, int>{
          for (final entry in seeded.appState.machineHistory.entries)
            entry.key: entry.value.sessionsSinceUsed,
        };

        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');
        await _completeCurrentWorkoutToA3(tester, 2);
        await tapKey(tester, 'feedback_just_right');
        await tapKey(tester, 'btn_finish_workout');

        final completedIds = seeded.appState.sessionHistory.single.exercises
            .map((e) => e.machineId)
            .toSet();
        expect(completedIds, hasLength(2));

        final persistedHistory = await seeded.repo.loadMachineHistory();
        for (final entry in persistedHistory.entries) {
          if (completedIds.contains(entry.key)) {
            expect(entry.value.sessionsSinceUsed, equals(0));
          } else {
            expect(
              entry.value.sessionsSinceUsed,
              equals(beforeOffsets[entry.key]! + 1),
            );
          }
        }
      },
    );

    testWidgets(
      'T2-F9-04: Saved WorkoutSessionRecord preserves exact durationCourse, condition, timeSlot, focusMuscleId, and feedback',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockEvening1800),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockEvening1800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'condition_tired');
        await selectDropdownOption(
          tester,
          'focus_muscle_dropdown',
          '三角筋中部',
        );
        await tapKey(tester, 'btn_start_workout');
        await _completeCurrentWorkoutToA3(tester, 2);
        await tapKey(tester, 'feedback_too_light');
        await tapKey(tester, 'btn_finish_workout');

        expect(seeded.appState.sessionHistory, hasLength(1));
        final record = seeded.appState.sessionHistory.single;
        expect(record.durationCourse, equals(WorkoutDurationCourse.short20));
        expect(record.condition, equals(WorkoutCondition.tired));
        expect(record.timeSlot, equals(TimeSlot.evening));
        expect(record.focusMuscleId, equals('m35'));
        expect(record.feedback, equals(WorkoutFeedback.tooLight));
        expect(record.exercises, hasLength(2));
      },
    );

    testWidgets(
      'T2-F9-05: Rapid double-tap on btn_finish_workout saves only 1 session record and increments sessionCount once',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        final beforeCount = seeded.appState.sessionCount;

        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapKey(tester, 'course_short');
        await tapKey(tester, 'btn_start_workout');
        await _completeCurrentWorkoutToA3(tester, 2);
        await tapKey(tester, 'feedback_just_right');

        final finishBtn = find.byKey(const Key('btn_finish_workout'));
        await tester.ensureVisible(finishBtn);
        await tester.tap(finishBtn);
        await tester.tap(finishBtn, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(seeded.appState.sessionHistory, hasLength(1));
        expect(seeded.appState.sessionCount, equals(beforeCount + 1));
      },
    );

    testWidgets(
      'T2-F9-06: Mobile (360x640) and desktop (1280x800) viewports render Screen A2 and Screen A3 with zero overflow',
      (WidgetTester tester) async {
        for (final size in const <Size>[Size(360, 640), Size(1280, 800)]) {
          await pumpNoukinApp(
            tester,
            clock: fixedClock(kClockMorning0800),
            viewportSize: size,
          );
          await tapKey(tester, 'course_short');
          await tapKey(tester, 'btn_start_workout');
          expectNoRenderOverflow(tester);
          expect(find.byKey(const Key('exercise_title')), findsOneWidget);
          expect(find.byKey(const Key('btn_next_workout')), findsOneWidget);

          await _completeCurrentWorkoutToA3(tester, 2);

          expectNoRenderOverflow(tester);
          expect(find.byKey(const Key('feedback_too_light')), findsOneWidget);
          expect(find.byKey(const Key('feedback_just_right')), findsOneWidget);
          expect(find.byKey(const Key('feedback_too_hard')), findsOneWidget);
          expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);
        }
      },
    );
  });

  // ===========================================================================
  // F10: Screen B — Custom Settings, Clamps & R1 Non-Exposure (6 tests)
  // ===========================================================================
  group('F10 Screen B Custom Settings Boundaries', () {
    testWidgets(
      'T2-F10-01: B_i batch/individual controls clamp strictly to 0..30',
      (WidgetTester tester) async {
        final customStates = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: 0,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm1': MuscleInputState(
              muscleId: 'm1',
              blankDays: 30,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
            'm2': MuscleInputState(
              muscleId: 'm2',
              blankDays: 5,
              stimulationDays: 2.0,
              priorityP: 18,
            ),
          },
        );
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          muscleStates: customStates,
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapNavTab(tester, 'nav_tab_custom');

        final editedM0 = await _tryEditMatrixRow(
          tester,
          'm0',
          incrementB: false,
          enterBText: '-5',
        );
        expect(editedM0, isTrue, reason: 'm0 B_i row edit control must work');
        expect(seeded.appState.muscleStates['m0']!.blankDays, equals(0));

        final editedM1 = await _tryEditMatrixRow(
          tester,
          'm1',
          incrementB: true,
          enterBText: '45',
        );
        expect(editedM1, isTrue, reason: 'm1 B_i row edit control must work');
        expect(seeded.appState.muscleStates['m1']!.blankDays, equals(30));

        final editedM2 = await _tryEditMatrixRow(
          tester,
          'm2',
          incrementB: true,
          enterBText: '6',
        );
        expect(editedM2, isTrue, reason: 'm2 B_i row edit control must work');
        expect(seeded.appState.muscleStates['m2']!.blankDays, greaterThan(5));
        expect(
          seeded.appState.muscleStates['m2']!.blankDays,
          inInclusiveRange(6, 30),
        );

        // Verify silent bCap=14 parity at engine boundary: B=20 equals B=14.
        const generator = WorkoutMenuGenerator();
        final profile = buildTestProfile();
        final b14Scores = generator.computeMuscleScores(
          muscleStates: buildDefaultMuscleStates(
            TrainingPurpose.bodyMakeMale,
            blankDays: 14,
          ),
          profile: profile,
        );
        final b20Scores = generator.computeMuscleScores(
          muscleStates: buildDefaultMuscleStates(
            TrainingPurpose.bodyMakeMale,
            blankDays: 20,
          ),
          profile: profile,
        );
        expect(b20Scores['m0']!.mVal, equals(b14Scores['m0']!.mVal));
      },
    );

    testWidgets(
      'T2-F10-02: S_i batch/individual controls clamp to 0.0..30.0 with 0.1 precision',
      (WidgetTester tester) async {
        final customStates = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: 4,
              stimulationDays: 0.0,
              priorityP: 18,
            ),
            'm1': MuscleInputState(
              muscleId: 'm1',
              blankDays: 4,
              stimulationDays: 30.0,
              priorityP: 18,
            ),
            'm2': MuscleInputState(
              muscleId: 'm2',
              blankDays: 4,
              stimulationDays: 2.3,
              priorityP: 18,
            ),
          },
        );
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          muscleStates: customStates,
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapNavTab(tester, 'nav_tab_custom');

        final editedM0 = await _tryEditMatrixRow(
          tester,
          'm0',
          incrementS: false,
          enterSText: '-1.5',
        );
        expect(editedM0, isTrue, reason: 'm0 S_i row edit control must work');
        expect(
          seeded.appState.muscleStates['m0']!.stimulationDays,
          closeTo(0.0, 1e-6),
        );

        final editedM1 = await _tryEditMatrixRow(
          tester,
          'm1',
          incrementS: true,
          enterSText: '35.0',
        );
        expect(editedM1, isTrue, reason: 'm1 S_i row edit control must work');
        expect(
          seeded.appState.muscleStates['m1']!.stimulationDays,
          closeTo(30.0, 1e-6),
        );

        await _scrollToWidgetKey(tester, 'matrix_row_m2');
        expect(
          seeded.appState.muscleStates['m2']!.stimulationDays,
          closeTo(2.3, 0.001),
        );

        final editedM2 = await _tryEditMatrixRow(
          tester,
          'm2',
          incrementS: true,
          enterSText: '2.6',
        );
        expect(editedM2, isTrue, reason: 'm2 S_i row edit control must work');
        expect(
          seeded.appState.muscleStates['m2']!.stimulationDays,
          greaterThan(2.3),
        );
        expect(
          seeded.appState.muscleStates['m2']!.stimulationDays,
          inInclusiveRange(0.0, 30.0),
        );
      },
    );

    testWidgets(
      'T2-F10-03: Un-injuring a muscle on Screen B restores M_i > 0 and machine eligibility on Screen A',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          muscleStates: buildDefaultMuscleStates(
            TrainingPurpose.bodyMakeMale,
            injuredIds: const <String>{'m0'},
          ),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        expect(seeded.appState.muscleStates['m0']!.isInjured, isTrue);

        await tapNavTab(tester, 'nav_tab_custom');
        await _scrollToWidgetKey(tester, 'injury_toggle_m0');
        await tapKey(tester, 'injury_toggle_m0');

        expect(seeded.appState.muscleStates['m0']!.isInjured, isFalse);

        final scores = const WorkoutMenuGenerator().computeMuscleScores(
          muscleStates: seeded.appState.muscleStates,
          profile: seeded.appState.profile,
        );
        expect(scores['m0']!.mVal, greaterThan(0.0));
        expect(scores['m0']!.status, equals(MuscleScoreStatus.active));

        await tapNavTab(tester, 'nav_tab_training');
        await tapKey(tester, 'course_full');
        await tapKey(tester, 'btn_start_workout');
        final hasQuadMachine = seeded.appState.lastMenuResult!.exercises.any(
          (e) => e.machine.primaryMuscleIds.contains('m0'),
        );
        expect(hasQuadMachine, isTrue);
      },
    );

    testWidgets(
      'T2-F10-04: Group batch edit mutates only the selected MuscleGroup, leaving the other 5 groups untouched',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        final before = Map<String, MuscleInputState>.from(
          seeded.appState.muscleStates,
        );

        await tapNavTab(tester, 'nav_tab_custom');
        await _scrollToWidgetKey(tester, 'group_batch_chest');
        final chestBatch = find.byKey(const Key('group_batch_chest'));
        final batchSection = find.byKey(const Key('group_batch_section'));
        final chestIds = kExpectedMuscleSpecs
            .where((m) => m.group == MuscleGroup.chest)
            .map((m) => m.id)
            .toList();
        expect(chestIds, containsAll(const <String>['m3', 'm29', 'm30', 'm31', 'm33']));

        bool isInsideOtherGroupBatch(Element element) {
          for (final group in MuscleGroup.values) {
            if (group == MuscleGroup.chest) {
              continue;
            }
            final otherKey = Key('group_batch_${group.name}');
            var insideOther = false;
            element.visitAncestorElements((ancestor) {
              if (ancestor.widget.key == otherKey) {
                insideOther = true;
                return false;
              }
              return true;
            });
            if (insideOther) {
              return true;
            }
          }
          return false;
        }

        Finder scopedFinder(
          Finder scope,
          Finder rawMatcher, {
          required bool excludeOtherGroups,
        }) {
          final raw = find.descendant(of: scope, matching: rawMatcher);
          if (!excludeOtherGroups) {
            return raw;
          }
          return find.byElementPredicate(
            (el) =>
                raw.evaluate().contains(el) && !isInsideOtherGroupBatch(el),
          );
        }

        Future<bool> triggerBatchEdit(
          Finder scope, {
          bool excludeOtherGroups = false,
        }) async {
          if (scope.evaluate().isEmpty) {
            return false;
          }
          final plusIcon = scopedFinder(
            scope,
            find.byIcon(Icons.add),
            excludeOtherGroups: excludeOtherGroups,
          );
          if (plusIcon.evaluate().isNotEmpty) {
            await tester.ensureVisible(plusIcon.first);
            await tester.tap(plusIcon.first);
            await tester.pumpAndSettle();
            return true;
          }

          final plusTextBtn = scopedFinder(
            scope,
            find.byWidgetPredicate((w) {
              if (w is Text) {
                final text = (w.data ?? '').trim();
                return const <String>{'+1', '+5', '+0.5', '+'}.contains(text);
              }
              return false;
            }),
            excludeOtherGroups: excludeOtherGroups,
          );
          if (plusTextBtn.evaluate().isNotEmpty) {
            await tester.ensureVisible(plusTextBtn.first);
            await tester.tap(plusTextBtn.first);
            await tester.pumpAndSettle();
            return true;
          }

          final textField = scopedFinder(
            scope,
            find.byType(TextField),
            excludeOtherGroups: excludeOtherGroups,
          );
          if (textField.evaluate().isNotEmpty) {
            await tester.ensureVisible(textField.first);
            await tester.enterText(textField.first, '12');
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await tester.pumpAndSettle();
            final applyBtn = scopedFinder(
              scope,
              find.byWidgetPredicate(
                (w) =>
                    w is Text &&
                    ((w.data ?? '').contains('適用') ||
                        (w.data ?? '').contains('一括') ||
                        (w.data ?? '').contains('保存')),
              ),
              excludeOtherGroups: excludeOtherGroups,
            );
            if (applyBtn.evaluate().isNotEmpty) {
              await tester.ensureVisible(applyBtn.first);
              await tester.tap(applyBtn.first);
              await tester.pumpAndSettle();
            }
            return true;
          }

          final dropdown = scopedFinder(
            scope,
            find.byWidgetPredicate(
              (w) => w is DropdownButton || w is DropdownButtonFormField,
            ),
            excludeOtherGroups: excludeOtherGroups,
          );
          if (dropdown.evaluate().isNotEmpty) {
            await tester.ensureVisible(dropdown.first);
            await tester.tap(dropdown.first);
            await tester.pumpAndSettle();
            final candidateOpt = find.textContaining('+');
            final zeroOpt = find.textContaining('0');
            if (candidateOpt.evaluate().isNotEmpty) {
              await tester.tap(candidateOpt.last);
              await tester.pumpAndSettle();
              return true;
            }
            if (zeroOpt.evaluate().isNotEmpty) {
              await tester.tap(zeroOpt.last);
              await tester.pumpAndSettle();
              return true;
            }
          }

          final applyFallback = scopedFinder(
            scope,
            find.byWidgetPredicate((w) {
              if (w is Text) {
                final text = (w.data ?? '').trim();
                return text.contains('適用') ||
                    text.contains('一括') ||
                    text.contains('保存') ||
                    text.contains('更新');
              }
              return false;
            }),
            excludeOtherGroups: excludeOtherGroups,
          );
          if (applyFallback.evaluate().isNotEmpty) {
            await tester.ensureVisible(applyFallback.first);
            await tester.tap(applyFallback.first);
            await tester.pumpAndSettle();
            return true;
          }
          return false;
        }

        var triggered = await triggerBatchEdit(chestBatch);
        var chestMutated = chestIds.any(
          (id) => seeded.appState.muscleStates[id] != before[id],
        );
        if (!triggered || !chestMutated) {
          await tester.ensureVisible(chestBatch);
          await tester.tap(chestBatch);
          await tester.pumpAndSettle();
          triggered = await triggerBatchEdit(chestBatch);
          chestMutated = chestIds.any(
            (id) => seeded.appState.muscleStates[id] != before[id],
          );
        }
        if (!triggered || !chestMutated) {
          await triggerBatchEdit(batchSection, excludeOtherGroups: true);
        }

        final after = seeded.appState.muscleStates;
        chestMutated = chestIds.any((id) => after[id] != before[id]);
        expect(
          chestMutated,
          isTrue,
          reason:
              'Chest batch edit via group_batch_chest must mutate at least one chest muscle (m29..m32)',
        );
        for (final spec in kExpectedMuscleSpecs) {
          if (spec.group != MuscleGroup.chest) {
            expect(
              after[spec.id],
              equals(before[spec.id]),
              reason:
                  'Non-chest muscle ${spec.id} must remain untouched by chest batch edit',
            );
          }
        }
      },
    );

    testWidgets(
      'T2-F10-05: Switching TrainingPurpose updates P_i while preserving custom B_i, S_i, and isInjured',
      (WidgetTester tester) async {
        final customStates = buildDefaultMuscleStates(
          TrainingPurpose.bodyMakeMale,
          overrides: const <String, MuscleInputState>{
            'm0': MuscleInputState(
              muscleId: 'm0',
              blankDays: 10,
              stimulationDays: 3.5,
              priorityP: 18,
              isInjured: true,
            ),
            'm7': MuscleInputState(
              muscleId: 'm7',
              blankDays: 7,
              stimulationDays: 1.5,
              priorityP: 18,
              isInjured: false,
            ),
          },
        );
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          muscleStates: customStates,
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapNavTab(tester, 'nav_tab_custom');
        await _selectOptionInside(tester, 'purpose_selector', 'ウィンドサーフィン');

        expect(
          seeded.appState.profile.purpose,
          equals(TrainingPurpose.windsurfing),
        );
        expect(
          seeded.appState.muscleStates['m3']!.priorityP,
          equals(
            kExpectedPurposePriorities[TrainingPurpose.windsurfing]!['m3'],
          ),
        );
        expect(
          seeded.appState.muscleStates['m11']!.priorityP,
          equals(
            kExpectedPurposePriorities[TrainingPurpose.windsurfing]!['m11'],
          ),
        );
        expect(seeded.appState.muscleStates['m0']!.blankDays, equals(10));
        expect(
          seeded.appState.muscleStates['m0']!.stimulationDays,
          equals(3.5),
        );
        expect(seeded.appState.muscleStates['m0']!.isInjured, isTrue);
        expect(seeded.appState.muscleStates['m7']!.blankDays, equals(7));
        expect(
          seeded.appState.muscleStates['m7']!.stimulationDays,
          equals(1.5),
        );
        expect(seeded.appState.muscleStates['m7']!.isInjured, isFalse);
      },
    );

    testWidgets(
      'T2-F10-06: Scrolling all 54 rows in muscle_matrix_list at 360x640 renders cleanly and exposes zero hidden engine constants',
      (WidgetTester tester) async {
        await pumpNoukinApp(
          tester,
          clock: fixedClock(kClockMorning0800),
          viewportSize: const Size(360, 640),
        );
        await tapNavTab(tester, 'nav_tab_custom');
        expectNoRenderOverflow(tester);

        expect(find.byKey(const Key('muscle_matrix_list')), findsOneWidget);

        for (final id in const <String>['m0', 'm15', 'm30', 'm45', 'm53']) {
          await _scrollToWidgetKey(tester, 'matrix_row_$id');
          expect(
            _extractText(tester, find.byKey(Key('matrix_row_$id'))),
            contains(kExpectedMuscleSpecById[id]!.name),
          );
        }

        expectNoRenderOverflow(tester);
        expect(find.textContaining('上限キャップ'), findsNothing);
        expect(find.textContaining('重複制御'), findsNothing);
        expect(find.textContaining('0.75'), findsNothing);
        expect(find.textContaining('0.45'), findsNothing);
      },
    );
  });

  // ===========================================================================
  // F11: Screen C — User Profile & Auth UI Boundaries (6 tests)
  // ===========================================================================
  group('F11 Screen C Profile & Auth Boundaries', () {
    testWidgets(
      'T2-F11-01: R2 birthYear-only negative check confirms zero age-bracket selectors on Screen C',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));
        await tapNavTab(tester, 'nav_tab_settings');

        expect(find.byKey(const Key('birth_year_input')), findsOneWidget);
        expect(find.textContaining('10代・20代前半'), findsNothing);
        expect(find.textContaining('20代後半〜30代'), findsNothing);
        expect(find.textContaining('60代以上'), findsNothing);
        expect(find.textContaining('年齢層'), findsNothing);
        expect(find.textContaining('年代を選択'), findsNothing);
      },
    );

    testWidgets(
      'T2-F11-02: Invalid and out-of-range birthYear values (abc, 1800, 2099, empty) are safely rejected or clamped',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          profile: buildTestProfile(birthYear: 1995),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );
        await tapNavTab(tester, 'nav_tab_settings');

        for (final invalid in const <String>['abc', '1800', '2099', '']) {
          await enterTextByKey(tester, 'birth_year_input', invalid);
          await tapKey(tester, 'btn_save_profile');

          expect(tester.takeException(), isNull);
          expect(
            seeded.appState.profile.birthYear,
            inInclusiveRange(1900, 2025),
            reason:
                'Invalid birthYear "$invalid" must never persist out of range',
          );
          expect(seeded.appState.profile.birthYear, isNot(equals(1800)));
          expect(seeded.appState.profile.birthYear, isNot(equals(2099)));
        }
      },
    );

    testWidgets(
      'T2-F11-03: Invalid bodyWeight values (0, -10, abc, 500) are safely rejected or clamped',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          profile: buildTestProfile(bodyWeightKg: 65.0),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );
        await tapNavTab(tester, 'nav_tab_settings');

        for (final invalid in const <String>['0', '-10', 'abc', '500']) {
          await enterTextByKey(tester, 'body_weight_input', invalid);
          await tapKey(tester, 'btn_save_profile');

          expect(tester.takeException(), isNull);
          expect(
            seeded.appState.profile.bodyWeightKg,
            inInclusiveRange(20.0, 300.0),
            reason:
                'Invalid bodyWeight "$invalid" must never yield non-positive or extreme weight',
          );
        }
      },
    );

    testWidgets(
      'T2-F11-04: Gender change preserves non-body_make purposes (tennis and diet)',
      (WidgetTester tester) async {
        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
          profile: buildTestProfile(
            gender: Gender.male,
            purpose: TrainingPurpose.tennis,
          ),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
        );

        await tapNavTab(tester, 'nav_tab_settings');
        await _selectOptionInside(tester, 'gender_selector', '女性');
        await tapKey(tester, 'btn_save_profile');

        expect(seeded.appState.profile.gender, equals(Gender.female));
        expect(seeded.appState.profile.purpose, equals(TrainingPurpose.tennis));

        await tapNavTab(tester, 'nav_tab_custom');
        await _selectOptionInside(tester, 'purpose_selector', 'ダイエット');
        expect(seeded.appState.profile.purpose, equals(TrainingPurpose.diet));

        await tapNavTab(tester, 'nav_tab_settings');
        await _selectOptionInside(tester, 'gender_selector', '男性');
        await tapKey(tester, 'btn_save_profile');

        expect(seeded.appState.profile.gender, equals(Gender.male));
        expect(seeded.appState.profile.purpose, equals(TrainingPurpose.diet));
      },
    );

    testWidgets(
      'T2-F11-05: Saved profile persists across cold NoukinApp restart via SharedPreferences',
      (WidgetTester tester) async {
        await pumpNoukinApp(tester, clock: fixedClock(kClockMorning0800));
        await tapNavTab(tester, 'nav_tab_settings');

        await _selectOptionInside(tester, 'gender_selector', '女性');
        await enterTextByKey(tester, 'birth_year_input', '1988');
        await _selectOptionInside(tester, 'experience_selector', '中級');
        await enterTextByKey(tester, 'body_weight_input', '58.5');
        await tapKey(tester, 'btn_save_profile');

        await restartNoukinApp(
          tester,
          clock: fixedClock(kClockMorning0800),
        );

        final prefs = await SharedPreferences.getInstance();
        final reloaded = await LocalWorkoutRepository(prefs).loadProfile();
        expect(reloaded, isNotNull);
        expect(reloaded!.gender, equals(Gender.female));
        expect(reloaded.birthYear, equals(1988));
        expect(reloaded.experience, equals(ExperienceLevel.intermediate));
        expect(reloaded.bodyWeightKg, closeTo(58.5, 0.01));

        await tapNavTab(tester, 'nav_tab_settings');
        expect(find.textContaining('1988'), findsAtLeastNWidgets(1));
        expect(find.textContaining('58.5'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'T2-F11-06: Offline local fallback login and logout succeed on Screen C at 360x640 without Supabase initialization error or overflow',
      (WidgetTester tester) async {
        expect(SupabaseConfig.isConfigured, isFalse);

        final seeded = await _createSeededAppState(
          clock: fixedClock(kClockMorning0800),
        );
        await restartNoukinApp(
          tester,
          appState: seeded.appState,
          clock: fixedClock(kClockMorning0800),
          viewportSize: const Size(360, 640),
        );

        await tapNavTab(tester, 'nav_tab_settings');
        expectNoRenderOverflow(tester);
        expect(seeded.appState.isLocalFallbackMode, isTrue);

        await tapKey(tester, 'btn_google_login');
        expectNoRenderOverflow(tester);
        expect(seeded.appState.currentUser, isNotNull);
        expect(seeded.appState.currentUser!.isLocalFallback, isTrue);

        await tapKey(tester, 'btn_logout');
        expectNoRenderOverflow(tester);
        expect(seeded.appState.currentUser, isNull);
      },
    );
  });

  // ===========================================================================
  // F12: Local Fallback, Platform Config, SQL Schema & R1/R4 Boundaries (6 tests)
  // ===========================================================================
  group('F12 Persistence, SQL Schema & R1/R4 Boundaries', () {
    test(
      'T2-F12-01: Empty SharedPreferences loads clean null/default state without TypeError',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final auth = LocalAuthService(prefs);
        final repo = LocalWorkoutRepository(prefs);

        expect(auth.isLocalFallbackMode, isTrue);
        expect(await auth.getCurrentUser(), isNull);
        expect(await repo.loadProfile(), isNull);
        expect(await repo.loadMuscleStates(), isEmpty);
        expect(await repo.loadMachineHistory(), isEmpty);
        expect(await repo.loadSessionHistory(), isEmpty);

        final appState = AppState(authService: auth, repository: repo);
        await appState.initialize();
        expect(appState.isInitialized, isTrue);
        expect(appState.muscleStates, hasLength(54));
        expect(appState.machineHistory, hasLength(29));
        expect(appState.sessionHistory, isEmpty);
      },
    );

    test(
      'T2-F12-02: Corrupted JSON strings in SharedPreferences recover gracefully with defaults',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final repo = LocalWorkoutRepository(prefs);
        final auth = LocalAuthService(prefs);

        await auth.signInWithGoogle();
        await repo.saveProfile(buildTestProfile());
        await repo.saveMuscleStates(
          buildDefaultMuscleStates(TrainingPurpose.bodyMakeMale),
        );
        await repo.saveMachineHistory(buildDefaultMachineHistory());
        await repo.saveSessionRecord(
          WorkoutSessionRecord(
            id: 'seed_1',
            completedAt: kClockMorning0800,
            durationCourse: WorkoutDurationCourse.short20,
            condition: WorkoutCondition.normal,
            timeSlot: TimeSlot.morning,
            exercises: const <CompletedExerciseRecord>[],
            feedback: WorkoutFeedback.justRight,
            createdAt: kClockMorning0800,
          ),
        );
        await repo.saveSessionCount(5);

        final discoveredKeys = prefs.getKeys().toList();
        expect(discoveredKeys, isNotEmpty);
        for (final key in discoveredKeys) {
          await prefs.setString(key, '{corrupted_json_payload::[');
        }

        final freshAuth = LocalAuthService(prefs);
        final freshRepo = LocalWorkoutRepository(prefs);
        final appState = AppState(
          authService: freshAuth,
          repository: freshRepo,
        );
        await appState.initialize();

        expect(appState.isInitialized, isTrue);
        expect(appState.muscleStates, hasLength(54));
        expect(appState.machineHistory, hasLength(29));
        expect(appState.sessionHistory, isEmpty);
      },
    );

    test(
      'T2-F12-03: Platform config audit confirms Noukin branding and zero TTS/media/Gym AI in Android/iOS/Windows/pubspec',
      () {
        final pubspec = readProjectFile('pubspec.yaml');
        expect(pubspec, contains('name: noukin'));
        expect(pubspec, isNot(contains('button_controll_test')));
        expect(pubspec, isNot(contains('flutter_tts')));
        expect(pubspec, isNot(contains('audio_session')));
        expect(RegExp(r'Gym\s*AI', caseSensitive: false).hasMatch(pubspec), isFalse);

        if (projectFileExists('android/app/src/main/AndroidManifest.xml')) {
          final manifest = readProjectFile(
            'android/app/src/main/AndroidManifest.xml',
          );
          expect(manifest, isNot(contains('TTS_SERVICE')));
          expect(manifest, isNot(contains('button_controll_test')));
          expect(
            RegExp(r'Gym\s*AI', caseSensitive: false).hasMatch(manifest),
            isFalse,
          );
        }

        for (final ktFile in listProjectFiles('android', extension: '.kt')) {
          final content = ktFile.readAsStringSync();
          expect(content, isNot(contains('dispatchKeyEvent')));
          expect(content, isNot(contains('key_events')));
          expect(content, isNot(contains('MethodChannel')));
          expect(content, isNot(contains('button_controll_test')));
        }

        if (projectFileExists('ios/Runner/Info.plist')) {
          final plist = readProjectFile('ios/Runner/Info.plist');
          expect(plist, isNot(contains('button_controll_test')));
          expect(
            RegExp(r'Gym\s*AI', caseSensitive: false).hasMatch(plist),
            isFalse,
          );
          expect(plist.toLowerCase(), contains('noukin'));
        }

        for (final rel in const <String>[
          'windows/CMakeLists.txt',
          'windows/runner/Runner.rc',
        ]) {
          if (projectFileExists(rel)) {
            final content = readProjectFile(rel);
            expect(content, isNot(contains('button_controll_test')));
            expect(
              RegExp(r'Gym\s*AI', caseSensitive: false).hasMatch(content),
              isFalse,
            );
          }
        }
      },
    );

    test(
      'T2-F12-04: 001_initial_schema.sql matches all 4 contracted tables, columns, and auth.uid() = user_id RLS policies',
      () {
        expect(
          projectFileExists('supabase/migrations/001_initial_schema.sql'),
          isTrue,
        );
        final sql = readProjectFile('supabase/migrations/001_initial_schema.sql')
            .toLowerCase();

        for (final table in const <String>[
          'user_profiles',
          'muscle_states',
          'machine_history',
          'workout_sessions',
        ]) {
          expect(sql, contains(table));
        }

        expect(sql, contains('references auth.users'));

        const expectedColumns = <String>[
          'user_id',
          'gender',
          'birth_year',
          'experience',
          'body_weight_kg',
          'purpose',
          'is_first_time',
          'session_count',
          'muscle_id',
          'blank_days',
          'stimulation_days',
          'priority_p',
          'is_injured',
          'machine_id',
          'sessions_since_used',
          'last_weight_kg',
          'last_feedback',
          'completed_at',
          'duration_course',
          'condition',
          'time_slot',
          'focus_muscle_id',
          'feedback',
          'exercises_json',
          'created_at',
          'updated_at',
        ];
        for (final col in expectedColumns) {
          expect(sql, contains(col), reason: 'Missing SQL column "$col"');
        }

        final rlsEnableCount = RegExp(
          r'enable\s+row\s+level\s+security',
        ).allMatches(sql).length;
        expect(rlsEnableCount, greaterThanOrEqualTo(4));

        final authUidCount = RegExp(
          r'auth\.uid\(\)\s*=\s*user_id',
        ).allMatches(sql).length;
        expect(authUidCount, greaterThanOrEqualTo(4));
      },
    );

    test(
      'T2-F12-05: Zero hardcoded Supabase URLs, JWT secrets, LLM APIs, or prohibited R1 code in lib/ and .env.example',
      () {
        final dartFiles = listProjectFiles('lib', extension: '.dart');
        expect(dartFiles, isNotEmpty);

        final jwtPattern = RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}');
        final supabaseUrlPattern = RegExp(
          r'https://[a-z0-9-]+\.supabase\.co',
          caseSensitive: false,
        );
        final gymAiPattern = RegExp(r'Gym\s*AI', caseSensitive: false);

        const prohibitedSymbols = <String>[
          'button_controll_test',
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
          'api.openai.com',
          'api.anthropic.com',
          'generativelanguage.googleapis.com',
          'langchain',
          'サウナ',
          'プール',
          'ランニングトラッカー',
          'runningTracker',
        ];

        for (final file in dartFiles) {
          final content = file.readAsStringSync();
          expect(
            jwtPattern.hasMatch(content),
            isFalse,
            reason: 'JWT secret found in ${file.path}',
          );
          expect(
            supabaseUrlPattern.hasMatch(content),
            isFalse,
            reason: 'Hardcoded Supabase URL found in ${file.path}',
          );
          expect(
            gymAiPattern.hasMatch(content),
            isFalse,
            reason: 'Prohibited Gym AI found in ${file.path}',
          );
          for (final symbol in prohibitedSymbols) {
            expect(
              content.contains(symbol),
              isFalse,
              reason: 'Prohibited symbol "$symbol" found in ${file.path}',
            );
          }
        }

        expect(projectFileExists('.env.example'), isTrue);
        final envExample = readProjectFile('.env.example');
        expect(envExample, contains('SUPABASE_URL='));
        expect(envExample, contains('SUPABASE_ANON_KEY='));
        expect(jwtPattern.hasMatch(envExample), isFalse);
        expect(supabaseUrlPattern.hasMatch(envExample), isFalse);
      },
    );

    test(
      'T2-F12-06: HttpOverrides network blocker verifies zero HTTP requests across engine, advanceSessionDay, and local fallback persistence',
      () async {
        const generator = WorkoutMenuGenerator();
        final profile = buildTestProfile();
        final states = MasterData.defaultMuscleStates(profile.purpose);
        final history = MasterData.defaultMachineHistory();

        final result = runWithoutNetworkSync(() {
          final menu = generator.generateMenu(
            profile: profile,
            muscleStates: states,
            machineHistory: history,
            course: WorkoutDurationCourse.full60,
            condition: WorkoutCondition.normal,
            now: kClockMorning0800,
          );
          return generator.advanceSessionDay(
            muscleStates: states,
            machineHistory: history,
            completedExercises: menu.exercises,
            overallFeedback: WorkoutFeedback.justRight,
            sessionCount: 1,
          );
        });
        expect(result.sessionCount, equals(2));

        await runWithoutNetwork(() async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final prefs = await SharedPreferences.getInstance();
          final auth = LocalAuthService(prefs);
          final repo = LocalWorkoutRepository(prefs);
          final appState = AppState(
            authService: auth,
            repository: repo,
            clock: fixedClock(kClockMorning0800),
          );
          await appState.initialize();
          final user = await auth.signInWithGoogle();
          expect(user.isLocalFallback, isTrue);
          await repo.saveProfile(profile);
          expect(await repo.loadProfile(), equals(profile));
          await auth.signOut();
          expect(await auth.getCurrentUser(), isNull);
        });

        expect(HttpOverrides.current, isNull);
      },
    );
  });
}
