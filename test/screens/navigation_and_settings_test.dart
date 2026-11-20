import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/app.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('M5 Navigation, Screen B, Screen C & AppState Integration', () {
    testWidgets(
      '3-tab navigation switches cleanly between Screen A, Screen B, and Screen C',
      (WidgetTester tester) async {
        final fixedNow = DateTime(2026, 11, 20, 9, 0);
        await tester.pumpWidget(NoukinApp(clock: () => fixedNow));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
        expect(find.byKey(const Key('detected_timeslot_badge')), findsOneWidget);

        // Navigate to Screen B
        await tester.tap(find.byKey(const Key('nav_tab_custom')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('purpose_selector')), findsOneWidget);
        expect(find.byKey(const Key('injury_filter_section')), findsOneWidget);
        expect(find.byKey(const Key('group_batch_section')), findsOneWidget);
        expect(find.byKey(const Key('muscle_matrix_list')), findsOneWidget);

        // Navigate to Screen C
        await tester.tap(find.byKey(const Key('nav_tab_settings')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('gender_selector')), findsOneWidget);
        expect(find.byKey(const Key('birth_year_input')), findsOneWidget);
        expect(find.byKey(const Key('experience_selector')), findsOneWidget);
        expect(find.byKey(const Key('body_weight_input')), findsOneWidget);
        expect(find.byKey(const Key('btn_save_profile')), findsOneWidget);
        expect(find.byKey(const Key('btn_google_login')), findsOneWidget);

        // Return to Screen A
        await tester.tap(find.byKey(const Key('nav_tab_training')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
      },
    );

    test(
      'AppState enforces B_i (0..30), S_i (0.0..30.0), P_i (0..18), and profile validation bounds',
      () async {
        final appState = AppState(clock: () => DateTime(2026, 11, 20, 12, 0));
        await appState.initialize();

        await appState.updateMuscleState(
          'm0',
          blankDays: 99,
          stimulationDays: -5.0,
          priorityP: 40,
        );
        expect(appState.muscleStates['m0']!.blankDays, 30);
        expect(appState.muscleStates['m0']!.stimulationDays, 0.0);
        expect(appState.muscleStates['m0']!.priorityP, 18);

        await appState.updateMuscleState(
          'm0',
          blankDays: -10,
          stimulationDays: 99.9,
          priorityP: -3,
        );
        expect(appState.muscleStates['m0']!.blankDays, 0);
        expect(appState.muscleStates['m0']!.stimulationDays, 30.0);
        expect(appState.muscleStates['m0']!.priorityP, 0);

        // Invalid birthYear and bodyWeightKg are ignored, keeping previous valid values
        await appState.updateProfile(
          birthYear: 1850,
          bodyWeightKg: 5.0,
        );
        expect(appState.profile.birthYear, 1995);
        expect(appState.profile.bodyWeightKg, 65.0);

        // Valid update + gender auto-sync
        await appState.updateProfile(
          gender: Gender.female,
          birthYear: 1990,
          experience: ExperienceLevel.intermediate,
          bodyWeightKg: 54.0,
        );
        expect(appState.profile.gender, Gender.female);
        expect(appState.profile.purpose, TrainingPurpose.bodyMakeFemale);
        expect(appState.profile.birthYear, 1990);
        expect(appState.profile.experience, ExperienceLevel.intermediate);
        expect(appState.profile.bodyWeightKg, 54.0);
      },
    );
  });
}
