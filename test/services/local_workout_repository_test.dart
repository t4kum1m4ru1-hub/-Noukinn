import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/services/local_storage_service.dart';
import 'package:noukin/services/workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw StateError('Network access is disabled in unit tests');
  }
}

WorkoutSessionRecord _buildSession({
  required String id,
  required DateTime completedAt,
  WorkoutFeedback feedback = WorkoutFeedback.justRight,
  String? focusMuscleId,
}) {
  return WorkoutSessionRecord(
    id: id,
    completedAt: completedAt,
    durationCourse: WorkoutDurationCourse.short20,
    condition: WorkoutCondition.normal,
    timeSlot: TimeSlot.morning,
    focusMuscleId: focusMuscleId,
    exercises: const <CompletedExerciseRecord>[
      CompletedExerciseRecord(
        machineId: 'mac1',
        machineName: 'レッグプレス',
        weightKg: 60.0,
        reps: 10,
        sets: 3,
      ),
    ],
    feedback: feedback,
    createdAt: completedAt,
  );
}

void main() {
  group('LocalWorkoutRepository', () {
    test('returns safe defaults on empty SharedPreferences offline', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await HttpOverrides.runZoned(() async {
        final repo = LocalWorkoutRepository(prefs);
        expect(await repo.loadProfile(), isNull);
        expect(await repo.loadMuscleStates(), isEmpty);
        expect(await repo.loadMachineHistory(), isEmpty);
        expect(await repo.loadSessionHistory(), isEmpty);
        expect(await repo.loadSessionCount(), 1);
      }, createHttpClient: _NoNetworkHttpOverrides().createHttpClient);
    });

    test('round-trips full 54 muscles, 29 machines, profile, sessions, and count', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await HttpOverrides.runZoned(() async {
        final writer = LocalWorkoutRepository(prefs);

        const profile = UserProfile(
          id: 'user-rt',
          gender: Gender.female,
          birthYear: 1991,
          experience: ExperienceLevel.intermediate,
          bodyWeightKg: 54.0,
          purpose: TrainingPurpose.windsurfing,
          isFirstTime: false,
          email: 'user@noukin.app',
        );

        final muscleStates = MasterData.defaultMuscleStates(profile.purpose);
        muscleStates['m0'] = muscleStates['m0']!.copyWith(
          blankDays: 8,
          stimulationDays: 3.3,
          isInjured: true,
        );
        muscleStates['m53'] = muscleStates['m53']!.copyWith(
          priorityP: 0,
          blankDays: 2,
        );

        final machineHistory = MasterData.defaultMachineHistory();
        machineHistory['mac1'] = const MachineHistoryEntry(
          machineId: 'mac1',
          sessionsSinceUsed: 0,
          lastWeightKg: 67.5,
          lastFeedback: WorkoutFeedback.tooLight,
        );

        final s1 = _buildSession(
          id: 'sess-1',
          completedAt: DateTime.utc(2026, 11, 1, 8, 0),
          feedback: WorkoutFeedback.tooLight,
          focusMuscleId: 'm4',
        );
        final s2 = _buildSession(
          id: 'sess-2',
          completedAt: DateTime.utc(2026, 11, 4, 18, 0),
          feedback: WorkoutFeedback.tooHard,
        );
        final s3 = _buildSession(
          id: 'sess-3',
          completedAt: DateTime.utc(2026, 11, 7, 9, 0),
          feedback: WorkoutFeedback.justRight,
        );

        await writer.saveProfile(profile);
        await writer.saveMuscleStates(muscleStates);
        await writer.saveMachineHistory(machineHistory);
        await writer.saveSessionRecord(s1);
        await writer.saveSessionRecord(s2);
        await writer.saveSessionRecord(s3);
        await writer.saveSessionCount(7);

        final reader = LocalWorkoutRepository(prefs);
        expect(await reader.loadProfile(), profile);
        final loadedMuscles = await reader.loadMuscleStates();
        expect(loadedMuscles, hasLength(54));
        expect(loadedMuscles, muscleStates);

        final loadedMachines = await reader.loadMachineHistory();
        expect(loadedMachines, hasLength(29));
        expect(loadedMachines, machineHistory);

        // Chronological ascending append order preserved (T4-10 requirement).
        expect(
          await reader.loadSessionHistory(),
          <WorkoutSessionRecord>[s1, s2, s3],
        );
        expect(await reader.loadSessionCount(), 7);

        // Updating an existing session ID replaces in-place without duplicating.
        final s2Updated = s2.copyWith(feedback: WorkoutFeedback.justRight);
        await writer.saveSessionRecord(s2Updated);
        expect(
          await reader.loadSessionHistory(),
          <WorkoutSessionRecord>[s1, s2Updated, s3],
        );

        // Non-positive session counts clamp to 1.
        await writer.saveSessionCount(0);
        expect(await reader.loadSessionCount(), 1);
      }, createHttpClient: _NoNetworkHttpOverrides().createHttpClient);
    });

    test('recovers cleanly when every SharedPreferences key is overwritten with corrupted string', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalWorkoutRepository(prefs);

      await repo.saveProfile(const UserProfile());
      await repo.saveMuscleStates(
        MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale),
      );
      await repo.saveMachineHistory(MasterData.defaultMachineHistory());
      await repo.saveSessionRecord(
        _buildSession(id: 'seed-1', completedAt: DateTime.utc(2026, 11, 1)),
      );
      await repo.saveSessionCount(5);

      for (final key in prefs.getKeys().toList()) {
        await prefs.setString(key, '{corrupted_json_payload::[');
      }

      final freshRepo = LocalWorkoutRepository(prefs);
      expect(await freshRepo.loadProfile(), isNull);
      expect(await freshRepo.loadMuscleStates(), isEmpty);
      expect(await freshRepo.loadMachineHistory(), isEmpty);
      expect(await freshRepo.loadSessionHistory(), isEmpty);
      expect(await freshRepo.loadSessionCount(), 1);
    });

    test('handles wrong JSON container shapes and partially corrupted entries gracefully', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LocalStorageKeys.userProfile: '[]',
        LocalStorageKeys.muscleStates:
            '{"m0":{"muscle_id":"m0","blank_days":5},"bad":"not_a_map","empty":{}}',
        LocalStorageKeys.machineHistory:
            '{"mac1":{"machine_id":"mac1","sessions_since_used":2},"bad":123}',
        LocalStorageKeys.sessionHistory:
            '[{"id":"ok","completed_at":"2026-11-19T08:00:00Z","duration_course":"short_20","condition":"normal","time_slot":"morning","exercises_json":[],"feedback":"just_right","created_at":"2026-11-19T08:00:00Z"},{"id":"bad_date","completed_at":"not-a-date"},"not_a_map"]',
        LocalStorageKeys.sessionCount: '9',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalWorkoutRepository(prefs);

      expect(await repo.loadProfile(), isNull);

      final states = await repo.loadMuscleStates();
      expect(states.keys, <String>['m0']);
      expect(states['m0']?.blankDays, 5);

      final history = await repo.loadMachineHistory();
      expect(history.keys, <String>['mac1']);
      expect(history['mac1']?.sessionsSinceUsed, 2);

      final sessions = await repo.loadSessionHistory();
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 'ok');

      expect(await repo.loadSessionCount(), 9);
    });

    test('LocalStorageService.readInt and loadSessionCount guard NaN and Infinity safely', () async {
      for (final badValue in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          LocalStorageKeys.sessionCount: badValue,
        });
        final prefs = await SharedPreferences.getInstance();
        final storage = LocalStorageService(prefs);
        final repo = LocalWorkoutRepository(prefs);

        expect(storage.readInt(LocalStorageKeys.sessionCount), isNull);
        expect(await repo.loadSessionCount(), 1);
      }
    });

    test('loadSessionHistory sorts chronologically ascending and preserves order on equal timestamps', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalWorkoutRepository(prefs);

      final s10 = _buildSession(
        id: 's-10',
        completedAt: DateTime.utc(2026, 11, 10, 8, 0),
      );
      final s05 = _buildSession(
        id: 's-05',
        completedAt: DateTime.utc(2026, 11, 5, 8, 0),
      );
      final s08a = _buildSession(
        id: 's-08a',
        completedAt: DateTime.utc(2026, 11, 8, 8, 0),
      );
      final s08b = _buildSession(
        id: 's-08b',
        completedAt: DateTime.utc(2026, 11, 8, 8, 0),
      );

      await repo.saveSessionRecord(s10);
      await repo.saveSessionRecord(s05);
      await repo.saveSessionRecord(s08a);
      await repo.saveSessionRecord(s08b);

      final s05Updated = s05.copyWith(feedback: WorkoutFeedback.tooLight);
      await repo.saveSessionRecord(s05Updated);

      final reloaded = await LocalWorkoutRepository(prefs).loadSessionHistory();
      expect(
        reloaded.map((e) => e.id).toList(),
        <String>['s-05', 's-08a', 's-08b', 's-10'],
      );
      expect(reloaded.first.feedback, WorkoutFeedback.tooLight);
    });

    test('concurrent saveSessionRecord calls do not lose updates', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalWorkoutRepository(prefs);

      final s1 = _buildSession(
        id: 'c-1',
        completedAt: DateTime.utc(2026, 11, 3, 8, 0),
      );
      final s2 = _buildSession(
        id: 'c-2',
        completedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final s3 = _buildSession(
        id: 'c-3',
        completedAt: DateTime.utc(2026, 11, 2, 8, 0),
      );

      await Future.wait(<Future<void>>[
        repo.saveSessionRecord(s1),
        repo.saveSessionRecord(s2),
        repo.saveSessionRecord(s3),
      ]);

      final loaded = await repo.loadSessionHistory();
      expect(loaded.map((e) => e.id).toList(), <String>['c-2', 'c-3', 'c-1']);
    });
  });
}
