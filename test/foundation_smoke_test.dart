import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/main.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/review_screen.dart';
import 'package:noukin/theme/app_colors.dart';
import 'package:noukin/theme/app_theme.dart';
import 'package:noukin/training_controller.dart';
import 'package:noukin/training_screen.dart';

void main() {
  group('1. NoukinApp branding & UI hygiene', () {
    testWidgets('renders NoukinApp with dark theme and Noukin branding', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const NoukinApp());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.title, 'のう筋（Noukin）');
      expect(materialApp.themeMode, ThemeMode.dark);

      expect(find.textContaining('のう筋'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Noukin'), findsAtLeastNWidgets(1));
      expect(find.textContaining('チュートリアル'), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('navigates between placeholder TrainingScreen and ReviewScreen', (
      WidgetTester tester,
    ) async {
      final controller = TrainingController(
        exerciseName: 'ベンチプレス',
        weightKg: 60.0,
        reps: 10,
        sets: 3,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TrainingScreen(controller: controller),
        ),
      );

      expect(find.byKey(const Key('exercise_title')), findsOneWidget);
      expect(find.text('ベンチプレス'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_next_workout')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.byKey(const Key('review_page_title')), findsOneWidget);
      expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);
    });
  });

  group('2. AppColors & AppTheme', () {
    test('AppColors defines exact palette tokens', () {
      expect(AppColors.background, const Color(0xFF121212));
      expect(AppColors.surface, const Color(0xFF1E1E1E));
      expect(AppColors.surfaceVariant, const Color(0xFF2C2C2C));
      expect(AppColors.border, const Color(0xFF2E2E2E));
      expect(AppColors.trackInactive, const Color(0xFF333333));
      expect(AppColors.highlightEditingSurface, const Color(0xFF2D2212));
      expect(AppColors.highlightSelectedSurface, const Color(0xFF162927));
      expect(AppColors.textPrimary, Colors.white);
      expect(AppColors.textSecondary, Colors.white70);
      expect(AppColors.textTertiary, Colors.white38);
      expect(AppColors.tealAccent, Colors.tealAccent);
      expect(AppColors.amberAccent, Colors.amberAccent);
      expect(AppColors.primaryAccent, const Color(0xFFFF9100));
      expect(AppColors.onPrimaryAccent, Colors.black);
      expect(AppColors.error, const Color(0xFFCF6679));
      expect(AppColors.onError, Colors.black);
    });

    test('AppTheme.dark and AppTheme.darkTheme match dark palette', () {
      final theme = AppTheme.dark;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(theme.colorScheme.primary, AppColors.tealAccent);
      expect(theme.colorScheme.secondary, AppColors.primaryAccent);
      expect(theme.colorScheme.surface, AppColors.surface);
      expect(theme.colorScheme.error, AppColors.error);
      expect(theme.appBarTheme.backgroundColor, AppColors.surface);
      expect(theme.appBarTheme.elevation, 0);
      expect(AppTheme.darkTheme.scaffoldBackgroundColor, AppColors.background);
    });
  });

  group('3. resolveTimeSlot boundary hours', () {
    test('maps every boundary hour accurately', () {
      final cases = <int, TimeSlot>{
        0: TimeSlot.night,
        4: TimeSlot.night,
        5: TimeSlot.morning,
        11: TimeSlot.morning,
        12: TimeSlot.daytime,
        14: TimeSlot.daytime,
        15: TimeSlot.evening,
        20: TimeSlot.evening,
        21: TimeSlot.night,
        23: TimeSlot.night,
      };

      for (final entry in cases.entries) {
        final dt = DateTime(2026, 11, 19, entry.key, 0);
        expect(
          resolveTimeSlot(dt),
          entry.value,
          reason: 'Hour ${entry.key} should map to ${entry.value}',
        );
      }

      expect(resolveTimeSlot(DateTime(2026, 11, 19, 4, 59)), TimeSlot.night);
      expect(resolveTimeSlot(DateTime(2026, 11, 19, 11, 59)), TimeSlot.morning);
      expect(resolveTimeSlot(DateTime(2026, 11, 19, 14, 59)), TimeSlot.daytime);
      expect(resolveTimeSlot(DateTime(2026, 11, 19, 20, 59)), TimeSlot.evening);
    });
  });

  group('4. Enum contract verification', () {
    test('TrainingPurpose exposes 6 purposes and exact windsurfing label', () {
      expect(TrainingPurpose.values.length, 6);
      expect(TrainingPurpose.windsurfing.label, 'ウィンドサーフィン');
      for (final p in TrainingPurpose.values) {
        expect(p.label, isNotEmpty);
        expect(TrainingPurpose.fromId(p.id), p);
        expect(TrainingPurpose.fromId(p.name), p);
      }
      expect(TrainingPurpose.fromId('body_make'), TrainingPurpose.bodyMakeMale);
    });

    test('WorkoutDurationCourse specifies course durations and counts', () {
      expect(WorkoutDurationCourse.short20.minutes, 20);
      expect(WorkoutDurationCourse.short20.exerciseCount, 2);
      expect(WorkoutDurationCourse.short20.label, 'ショート 20分');

      expect(WorkoutDurationCourse.standard45.minutes, 45);
      expect(WorkoutDurationCourse.standard45.exerciseCount, 4);
      expect(WorkoutDurationCourse.standard45.label, 'スタンダード 45分');

      expect(WorkoutDurationCourse.full60.minutes, 60);
      expect(WorkoutDurationCourse.full60.exerciseCount, 5);
      expect(WorkoutDurationCourse.full60.label, 'フル 60分');
    });

    test('WorkoutFeedback handles deltas, null tryFromId, and too_easy alias', () {
      expect(WorkoutFeedback.tooLight.weightDeltaKg, 2.5);
      expect(WorkoutFeedback.justRight.weightDeltaKg, 0.0);
      expect(WorkoutFeedback.tooHard.weightDeltaKg, -2.5);
      expect(WorkoutFeedback.tryFromId(null), isNull);
      expect(WorkoutFeedback.tryFromId(''), isNull);
      expect(WorkoutFeedback.tryFromId('unknown'), isNull);
      expect(
        WorkoutFeedback.tryFromId('too_easy'),
        WorkoutFeedback.tooLight,
      );
      expect(WorkoutFeedback.fromId(null), WorkoutFeedback.justRight);
    });

    test('other enums round-trip cleanly via fromId', () {
      for (final c in WorkoutCondition.values) {
        expect(WorkoutCondition.fromId(c.id), c);
      }
      for (final g in Gender.values) {
        expect(Gender.fromId(g.id), g);
      }
      for (final e in ExperienceLevel.values) {
        expect(ExperienceLevel.fromId(e.id), e);
      }
      expect(MuscleGroup.values.length, 6);
      for (final m in MuscleGroup.values) {
        expect(MuscleGroup.fromId(m.id), m);
        expect(MuscleGroup.fromId(m.label), m);
      }
      expect(MuscleTimeCategory.values.length, 4);
      for (final t in MuscleTimeCategory.values) {
        expect(MuscleTimeCategory.fromId(t.id), t);
      }
      expect(MuscleScoreStatus.values.length, 4);
      for (final s in MuscleScoreStatus.values) {
        expect(MuscleScoreStatus.fromId(s.id), s);
      }
      expect(TimeSlot.morning.label, '朝');
      expect(TimeSlot.daytime.label, '日中');
      expect(TimeSlot.evening.label, '夕方');
      expect(TimeSlot.night.label, '就寝前');
      for (final slot in TimeSlot.values) {
        expect(TimeSlot.fromId(slot.id), slot);
      }
    });
  });

  group('5. Model JSON round-trips & copyWith', () {
    test('UserProfile round-trips with birth_year and supports user_id alias', () {
      const profileWithEmail = UserProfile(
        id: 'user-123',
        gender: Gender.female,
        birthYear: 1992,
        experience: ExperienceLevel.intermediate,
        bodyWeightKg: 54.5,
        purpose: TrainingPurpose.windsurfing,
        isFirstTime: false,
        email: 'test@noukin.app',
      );

      final json = profileWithEmail.toJson();
      expect(json['birth_year'], 1992);
      expect(json['body_weight_kg'], 54.5);
      expect(json.containsKey('age_group'), isFalse);
      expect(json.containsKey('age_bracket'), isFalse);
      expect(UserProfile.fromJson(json), profileWithEmail);

      final supabaseRow = <String, dynamic>{
        'user_id': 'supa-999',
        'gender': 'male',
        'birth_year': 1980,
        'experience': 'beginner',
        'body_weight_kg': 72,
        'purpose': 'health',
        'is_first_time': true,
        'email': null,
      };
      final parsed = UserProfile.fromJson(supabaseRow);
      expect(parsed.id, 'supa-999');
      expect(parsed.birthYear, 1980);
      expect(parsed.bodyWeightKg, 72.0);
      expect(parsed.email, isNull);

      final cleared = profileWithEmail.copyWith(clearEmail: true);
      expect(cleared.email, isNull);
      expect(cleared.birthYear, 1992);
    });

    test('MuscleInputState round-trips with fractional stimulationDays', () {
      const state = MuscleInputState(
        muscleId: 'm12',
        blankDays: 6,
        stimulationDays: 3.5,
        priorityP: 18,
        isInjured: true,
      );

      final json = state.toJson();
      expect(json, <String, dynamic>{
        'muscle_id': 'm12',
        'blank_days': 6,
        'stimulation_days': 3.5,
        'priority_p': 18,
        'is_injured': true,
      });
      expect(MuscleInputState.fromJson(json), state);

      final updated = state.copyWith(blankDays: 8, isInjured: false);
      expect(updated.blankDays, 8);
      expect(updated.isInjured, isFalse);
      expect(updated.stimulationDays, 3.5);
    });

    test('MachineHistoryEntry preserves non-null and null optional fields', () {
      const withValues = MachineHistoryEntry(
        machineId: 'mac1',
        sessionsSinceUsed: 2,
        lastWeightKg: 62.5,
        lastFeedback: WorkoutFeedback.tooLight,
      );
      expect(MachineHistoryEntry.fromJson(withValues.toJson()), withValues);

      const withNulls = MachineHistoryEntry(
        machineId: 'mac2',
        sessionsSinceUsed: 5,
      );
      final nullJson = withNulls.toJson();
      expect(nullJson['last_weight_kg'], isNull);
      expect(nullJson['last_feedback'], isNull);
      expect(MachineHistoryEntry.fromJson(nullJson), withNulls);

      final cleared = withValues.copyWith(
        clearLastWeight: true,
        clearLastFeedback: true,
      );
      expect(cleared.lastWeightKg, isNull);
      expect(cleared.lastFeedback, isNull);
      expect(cleared.sessionsSinceUsed, 2);
    });

    test('WorkoutSessionRecord round-trips UTC and local DateTimes', () {
      final completedUtc = DateTime.utc(2026, 11, 19, 10, 30);
      final createdLocal = DateTime(2026, 11, 19, 19, 35);

      const ex1 = CompletedExerciseRecord(
        machineId: 'mac1',
        machineName: 'チェストプレス',
        weightKg: 50.0,
        reps: 10,
        sets: 3,
      );
      const ex2 = CompletedExerciseRecord(
        machineId: 'mac5',
        machineName: 'ラットプルダウン',
        weightKg: 45.0,
        reps: 10,
        sets: 3,
        completed: false,
      );

      final withFocus = WorkoutSessionRecord(
        id: 'sess-1',
        completedAt: completedUtc,
        durationCourse: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.great,
        timeSlot: TimeSlot.evening,
        focusMuscleId: 'm7',
        exercises: const <CompletedExerciseRecord>[ex1, ex2],
        feedback: WorkoutFeedback.tooLight,
        createdAt: createdLocal,
      );

      final json = withFocus.toJson();
      expect(json['exercises_json'], isA<List<dynamic>>());
      expect(WorkoutSessionRecord.fromJson(json), withFocus);

      final withoutFocus = withFocus.copyWith(clearFocusMuscleId: true);
      expect(withoutFocus.focusMuscleId, isNull);
      expect(WorkoutSessionRecord.fromJson(withoutFocus.toJson()), withoutFocus);
    });

    test('Machine JSON round-trip, nullable imageAssetPath, copyWith & isIsolationOrCore', () {
      const compound = Machine(
        id: 'mac1',
        name: 'ベンチプレス',
        category: MuscleGroup.chest,
        baseWeight: 40.0,
        bwFactor: 0.65,
        baseReps: 10,
        defaultSessionsSinceUsed: 4,
        primaryMuscleIds: <String>['m12', 'm13', 'm14'],
        synergistMuscleIds: <String>['m25', 'm26'],
        imageAssetPath: 'assets/images/workout/bench_press.avif',
      );
      expect(Machine.fromJson(compound.toJson()), compound);
      expect(compound.isIsolationOrCore, isFalse);

      final clearedImage = compound.copyWith(clearImageAssetPath: true);
      expect(clearedImage.imageAssetPath, isNull);
      expect(Machine.fromJson(clearedImage.toJson()), clearedImage);

      const nullableMachine = Machine(
        id: 'mac99',
        name: 'テスト種目',
        category: MuscleGroup.legsGlutes,
        baseWeight: 20.0,
        bwFactor: 0.5,
        baseReps: 10,
        defaultSessionsSinceUsed: 4,
        primaryMuscleIds: <String>['m0', 'm1'],
        synergistMuscleIds: <String>['m2'],
        imageAssetPath: null,
      );
      expect(nullableMachine.imageAssetPath, isNull);
      expect(nullableMachine.isIsolationOrCore, isTrue);
      expect(Machine.fromJson(nullableMachine.toJson()), nullableMachine);

      final armsCompoundCount = compound.copyWith(
        id: 'mac_arms',
        category: MuscleGroup.arms,
      );
      expect(armsCompoundCount.isIsolationOrCore, isTrue);

      final coreCompoundCount = compound.copyWith(
        id: 'mac_core',
        category: MuscleGroup.core,
      );
      expect(coreCompoundCount.isIsolationOrCore, isTrue);

      for (final overrideId in const <String>[
        'mac5',
        'mac6',
        'mac10',
        'mac14',
        'mac22',
        'mac23',
      ]) {
        final overridden = compound.copyWith(id: overrideId);
        expect(
          overridden.isIsolationOrCore,
          isTrue,
          reason: '$overrideId must be isolation/core',
        );
      }
    });

    test('AuthUser defaults, copyWith clear flags, JSON round-trip & equality', () {
      const fallbackUser = AuthUser(id: 'local-1');
      expect(fallbackUser.email, isNull);
      expect(fallbackUser.displayName, isNull);
      expect(fallbackUser.isLocalFallback, isTrue);

      const signedIn = AuthUser(
        id: 'uid-42',
        email: 'user@noukin.app',
        displayName: 'のう筋太郎',
        isLocalFallback: false,
      );
      expect(AuthUser.fromJson(signedIn.toJson()), signedIn);
      expect(AuthUser.fromJson(signedIn.toJson()).hashCode, signedIn.hashCode);

      final supaAlias = AuthUser.fromJson(<String, dynamic>{
        'user_id': 'uid-99',
        'email': 'alias@noukin.app',
        'displayName': 'Alias User',
        'isLocalFallback': false,
      });
      expect(supaAlias.id, 'uid-99');
      expect(supaAlias.displayName, 'Alias User');
      expect(supaAlias.isLocalFallback, isFalse);

      final cleared = signedIn.copyWith(
        clearEmail: true,
        clearDisplayName: true,
      );
      expect(cleared.email, isNull);
      expect(cleared.displayName, isNull);
      expect(cleared.id, 'uid-42');
      expect(cleared.isLocalFallback, isFalse);
    });

    test('Muscle copyWith & JSON round-trip', () {
      const muscle = Muscle(
        id: 'm12',
        name: '大胸筋（中部・胸骨部）',
        group: MuscleGroup.chest,
        timeCat: MuscleTimeCategory.other,
        recoveryDays: 3,
      );
      expect(Muscle.fromJson(muscle.toJson()), muscle);
      final updated = muscle.copyWith(
        recoveryDays: 2,
        timeCat: MuscleTimeCategory.nightAvoid,
      );
      expect(updated.recoveryDays, 2);
      expect(updated.timeCat, MuscleTimeCategory.nightAvoid);
      expect(updated.id, 'm12');
    });

    test('MuscleScoreInfo contracted constructor, copyWith & JSON round-trip', () {
      const score = MuscleScoreInfo(
        muscleId: 'm0',
        bRaw: 16,
        bCapped: 14,
        priorityP: 18,
        baseRecoveryDays: 3,
        effectiveRecoveryDays: 3,
        stimulationDays: 2.0,
        mVal: 27.0,
        synMVal: 27.0,
        status: MuscleScoreStatus.active,
      );
      expect(score.muscleName, isNull);
      expect(score.group, isNull);
      expect(score.timeCat, isNull);
      expect(score.isExtendedByVolume, isFalse);
      expect(score.isExtendedByAge, isFalse);
      expect(MuscleScoreInfo.fromJson(score.toJson()), score);

      final withMeta = score.copyWith(
        muscleName: '大腿四頭筋',
        group: MuscleGroup.legsGlutes,
        timeCat: MuscleTimeCategory.nightAvoid,
        isExtendedByVolume: true,
        isExtendedByAge: true,
      );
      expect(MuscleScoreInfo.fromJson(withMeta.toJson()), withMeta);
      expect(
        withMeta.copyWith(
          clearMuscleName: true,
          clearGroup: true,
          clearTimeCat: true,
          isExtendedByVolume: false,
          isExtendedByAge: false,
        ),
        score,
      );
    });

    test('PrescribedExercise JSON round-trip & copyWith', () {
      const machine = Machine(
        id: 'mac1',
        name: 'ベンチプレス',
        category: MuscleGroup.chest,
        baseWeight: 40.0,
        bwFactor: 0.65,
        baseReps: 10,
        defaultSessionsSinceUsed: 4,
        primaryMuscleIds: <String>['m12'],
        synergistMuscleIds: <String>['m25'],
      );
      const prescribed = PrescribedExercise(
        machine: machine,
        weightKg: 52.5,
        reps: 10,
        sets: 3,
        primaryMuscleNames: <String>['大胸筋'],
        synergistMuscleNames: <String>['上腕三頭筋'],
        finalScore: 42.5,
        rawScore: 34.0,
        reasons: <String>['未実施ボーナス'],
      );
      final roundTripped = PrescribedExercise.fromJson(prescribed.toJson());
      expect(roundTripped, prescribed);
      expect(roundTripped.hashCode, prescribed.hashCode);
      expect(prescribed.copyWith(weightKg: 55.0).weightKg, 55.0);
    });

    test('MenuGenerationResult deep equality, copyWith & JSON round-trip', () {
      const machine = Machine(
        id: 'mac1',
        name: 'ベンチプレス',
        category: MuscleGroup.chest,
        baseWeight: 40.0,
        bwFactor: 0.65,
        baseReps: 10,
        defaultSessionsSinceUsed: 4,
        primaryMuscleIds: <String>['m12'],
        synergistMuscleIds: <String>['m25'],
      );
      const ex = PrescribedExercise(
        machine: machine,
        weightKg: 40.0,
        reps: 10,
        sets: 3,
      );
      const s1 = MuscleScoreInfo(
        muscleId: 'm12',
        bRaw: 5,
        bCapped: 5,
        priorityP: 16,
        baseRecoveryDays: 3,
        effectiveRecoveryDays: 3,
        stimulationDays: 1.5,
        mVal: 16.5,
        synMVal: 16.5,
        status: MuscleScoreStatus.active,
      );
      const s2 = MuscleScoreInfo(
        muscleId: 'm25',
        bRaw: 2,
        bCapped: 2,
        priorityP: 10,
        baseRecoveryDays: 2,
        effectiveRecoveryDays: 2,
        stimulationDays: 0.0,
        mVal: 10.0,
        synMVal: 10.0,
        status: MuscleScoreStatus.active,
      );

      final resultA = MenuGenerationResult(
        exercises: const <PrescribedExercise>[ex],
        muscleScores: <String, MuscleScoreInfo>{'m12': s1, 'm25': s2},
        timeSlot: TimeSlot.morning,
      );
      final resultB = MenuGenerationResult(
        exercises: <PrescribedExercise>[ex.copyWith()],
        muscleScores: <String, MuscleScoreInfo>{'m25': s2, 'm12': s1},
        timeSlot: TimeSlot.morning,
      );

      expect(resultA, resultB);
      expect(resultA.hashCode, resultB.hashCode);
      expect(MenuGenerationResult.fromJson(resultA.toJson()), resultA);

      final withOptional = resultA.copyWith(
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.great,
        generatedAt: DateTime.utc(2026, 11, 19, 8, 0),
        focusMuscleId: 'm12',
      );
      expect(
        MenuGenerationResult.fromJson(withOptional.toJson()),
        withOptional,
      );
      expect(
        withOptional.copyWith(
          clearCourse: true,
          clearCondition: true,
          clearGeneratedAt: true,
          clearFocusMuscleId: true,
        ),
        resultA,
      );
    });

    test('SessionAdvanceResult deep equality, copyWith & JSON round-trip', () {
      const state1 = MuscleInputState(muscleId: 'm0', blankDays: 5);
      const state2 = MuscleInputState(muscleId: 'm1', blankDays: 1);
      const hist1 = MachineHistoryEntry(
        machineId: 'mac1',
        sessionsSinceUsed: 0,
        lastWeightKg: 50.0,
        lastFeedback: WorkoutFeedback.justRight,
      );
      const hist2 = MachineHistoryEntry(
        machineId: 'mac2',
        sessionsSinceUsed: 4,
      );

      final advanceA = SessionAdvanceResult(
        muscleStates: <String, MuscleInputState>{'m0': state1, 'm1': state2},
        machineHistory: <String, MachineHistoryEntry>{
          'mac1': hist1,
          'mac2': hist2,
        },
        sessionCount: 3,
      );
      final advanceB = SessionAdvanceResult(
        muscleStates: <String, MuscleInputState>{'m1': state2, 'm0': state1},
        machineHistory: <String, MachineHistoryEntry>{
          'mac2': hist2,
          'mac1': hist1,
        },
        sessionCount: 3,
      );

      expect(advanceA, advanceB);
      expect(advanceA.hashCode, advanceB.hashCode);
      expect(SessionAdvanceResult.fromJson(advanceA.toJson()), advanceA);
      expect(advanceA.copyWith(sessionCount: 4).sessionCount, 4);
    });
  });
}
