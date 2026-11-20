import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/services/supabase_workout_repository.dart';
import 'package:noukin/services/workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class _BlockingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return Future<HttpClientRequest>.error(
      const SocketException('Network access is disabled in unit tests'),
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockingHttpClient();
}

class _FakeSupabaseWorkoutGateway implements SupabaseWorkoutGateway {
  Map<String, dynamic>? profileRow;
  int? remoteSessionCount;
  List<Map<String, dynamic>> muscleStateRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> machineHistoryRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> workoutSessionRows = <Map<String, dynamic>>[];

  Map<String, dynamic>? lastUpsertedProfileRow;
  Map<String, dynamic>? lastUpsertedSessionCountRow;
  List<Map<String, dynamic>>? lastUpsertedMuscleRows;
  List<Map<String, dynamic>>? lastUpsertedMachineRows;
  Map<String, dynamic>? lastUpsertedSessionRow;

  bool shouldThrow = false;

  void _checkError() {
    if (shouldThrow) {
      throw const SocketException('Simulated offline error');
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileRow(String userId) async {
    _checkError();
    return profileRow;
  }

  @override
  Future<void> upsertProfileRow(Map<String, dynamic> row) async {
    _checkError();
    lastUpsertedProfileRow = Map<String, dynamic>.from(row);
    profileRow = <String, dynamic>{
      ...?profileRow,
      ...row,
    };
  }

  @override
  Future<int?> fetchSessionCount(String userId) async {
    _checkError();
    return remoteSessionCount ?? (profileRow?['session_count'] as num?)?.toInt();
  }

  @override
  Future<void> upsertSessionCountRow(Map<String, dynamic> row) async {
    _checkError();
    lastUpsertedSessionCountRow = Map<String, dynamic>.from(row);
    remoteSessionCount = (row['session_count'] as num?)?.toInt();
    profileRow = <String, dynamic>{
      ...?profileRow,
      ...row,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMuscleStateRows(String userId) async {
    _checkError();
    return muscleStateRows;
  }

  @override
  Future<void> upsertMuscleStateRows(List<Map<String, dynamic>> rows) async {
    _checkError();
    lastUpsertedMuscleRows = rows.map((e) => Map<String, dynamic>.from(e)).toList();
    muscleStateRows = lastUpsertedMuscleRows!;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMachineHistoryRows(String userId) async {
    _checkError();
    return machineHistoryRows;
  }

  @override
  Future<void> upsertMachineHistoryRows(List<Map<String, dynamic>> rows) async {
    _checkError();
    lastUpsertedMachineRows = rows.map((e) => Map<String, dynamic>.from(e)).toList();
    machineHistoryRows = lastUpsertedMachineRows!;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWorkoutSessionRows(String userId) async {
    _checkError();
    return workoutSessionRows;
  }

  @override
  Future<void> upsertWorkoutSessionRow(Map<String, dynamic> row) async {
    _checkError();
    lastUpsertedSessionRow = Map<String, dynamic>.from(row);
    workoutSessionRows.add(lastUpsertedSessionRow!);
  }
}

void main() {
  group('SupabaseWorkoutRepository row mappers', () {
    test('profileToRow omits id, email, and session_count; profileFromRow restores user_id and email', () {
      const profile = UserProfile(
        id: 'local_user',
        gender: Gender.female,
        birthYear: 1992,
        experience: ExperienceLevel.intermediate,
        bodyWeightKg: 55.5,
        purpose: TrainingPurpose.diet,
        isFirstTime: false,
        email: 'ignored-in-row@noukin.app',
      );

      final row = SupabaseWorkoutRepository.profileToRow(
        profile,
        userId: 'uid-abc',
        updatedAt: DateTime.utc(2026, 11, 19, 8, 0),
      );

      expect(row['user_id'], 'uid-abc');
      expect(row['gender'], 'female');
      expect(row['birth_year'], 1992);
      expect(row['experience'], 'intermediate');
      expect(row['body_weight_kg'], 55.5);
      expect(row['purpose'], 'diet');
      expect(row['is_first_time'], isFalse);
      expect(row['updated_at'], '2026-11-19T08:00:00.000Z');
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('email'), isFalse);
      expect(row.containsKey('session_count'), isFalse);

      final restored = SupabaseWorkoutRepository.profileFromRow(
        row,
        email: 'auth@noukin.app',
      );
      expect(restored.id, 'uid-abc');
      expect(restored.email, 'auth@noukin.app');
      expect(restored.gender, Gender.female);
      expect(restored.birthYear, 1992);
      expect(restored.experience, ExperienceLevel.intermediate);
      expect(restored.bodyWeightKg, 55.5);
      expect(restored.purpose, TrainingPurpose.diet);
      expect(restored.isFirstTime, isFalse);
    });

    test('muscleStates and machineHistory row mappers preserve all 54/29 entries', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.tennis);
      states['m12'] = states['m12']!.copyWith(
        blankDays: 6,
        stimulationDays: 3.4,
        isInjured: true,
      );
      final muscleRows = SupabaseWorkoutRepository.muscleStatesToRows(
        states,
        userId: 'uid-1',
        updatedAt: DateTime.utc(2026, 11, 19),
      );
      expect(muscleRows, hasLength(54));
      expect(muscleRows.first['user_id'], 'uid-1');
      expect(SupabaseWorkoutRepository.muscleStatesFromRows(muscleRows), states);

      final history = MasterData.defaultMachineHistory();
      history['mac3'] = const MachineHistoryEntry(
        machineId: 'mac3',
        sessionsSinceUsed: 0,
        lastWeightKg: 42.5,
        lastFeedback: WorkoutFeedback.tooHard,
      );
      final machineRows = SupabaseWorkoutRepository.machineHistoryToRows(
        history,
        userId: 'uid-1',
        updatedAt: DateTime.utc(2026, 11, 19),
      );
      expect(machineRows, hasLength(29));
      expect(
        SupabaseWorkoutRepository.machineHistoryFromRows(machineRows),
        history,
      );
    });

    test('normalizeSessionId preserves valid UUIDs and deterministically converts non-UUID IDs', () {
      const validUuid = '550e8400-e29b-41d4-a716-446655440000';
      expect(SupabaseWorkoutRepository.normalizeSessionId(validUuid), validUuid);

      final mappedA = SupabaseWorkoutRepository.normalizeSessionId('sess-rt-1');
      final mappedB = SupabaseWorkoutRepository.normalizeSessionId('sess-rt-1');
      expect(mappedA, mappedB);
      expect(Uuid.isValidUUID(fromString: mappedA), isTrue);

      final generated = SupabaseWorkoutRepository.normalizeSessionId('   ');
      expect(Uuid.isValidUUID(fromString: generated), isTrue);
    });

    test('sessionToRow / sessionFromRow preserve all workout_sessions columns', () {
      final record = WorkoutSessionRecord(
        id: 'sess-1',
        completedAt: DateTime.utc(2026, 11, 19, 10, 0),
        durationCourse: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.tired,
        timeSlot: TimeSlot.night,
        focusMuscleId: 'm0',
        exercises: const <CompletedExerciseRecord>[
          CompletedExerciseRecord(
            machineId: 'mac1',
            machineName: 'レッグプレス',
            weightKg: 70.0,
            reps: 10,
            sets: 2,
          ),
        ],
        feedback: WorkoutFeedback.tooLight,
        createdAt: DateTime.utc(2026, 11, 19, 10, 45),
      );

      final row = SupabaseWorkoutRepository.sessionToRow(
        record,
        userId: 'uid-1',
      );
      expect(Uuid.isValidUUID(fromString: row['id'] as String), isTrue);
      expect(row['user_id'], 'uid-1');
      expect(row['duration_course'], 'standard_45');
      expect(row['condition'], 'tired');
      expect(row['time_slot'], 'night');
      expect(row['focus_muscle_id'], 'm0');
      expect(row['feedback'], 'too_light');
      expect(row['exercises_json'], isA<List<dynamic>>());

      final restored = SupabaseWorkoutRepository.sessionFromRow(row);
      expect(restored.completedAt, record.completedAt);
      expect(restored.durationCourse, record.durationCourse);
      expect(restored.condition, record.condition);
      expect(restored.timeSlot, record.timeSlot);
      expect(restored.focusMuscleId, record.focusMuscleId);
      expect(restored.feedback, record.feedback);
      expect(restored.exercises, record.exercises);
    });
  });

  group('SupabaseWorkoutRepository sync & offline fallback', () {
    test('write-through caches locally, preserves session_count on saveProfile, and sorts sessions ascending', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final local = LocalWorkoutRepository(prefs);
      final gateway = _FakeSupabaseWorkoutGateway();

      final repo = SupabaseWorkoutRepository(
        localCache: local,
        remoteGateway: gateway,
        userIdProvider: () => 'uid-sync-1',
        userEmailProvider: () => 'sync@noukin.app',
        clock: () => DateTime.utc(2026, 11, 19, 12, 0),
      );

      await repo.saveSessionCount(4);
      expect(gateway.remoteSessionCount, 4);

      const profile = UserProfile(
        id: 'local_user',
        gender: Gender.male,
        birthYear: 1990,
        experience: ExperienceLevel.intermediate,
        bodyWeightKg: 75.0,
        purpose: TrainingPurpose.bodyMakeMale,
        isFirstTime: false,
      );
      await repo.saveProfile(profile);
      expect(gateway.lastUpsertedProfileRow!.containsKey('session_count'), isFalse);
      expect(gateway.profileRow?['session_count'], 4);

      final loadedProfile = await repo.loadProfile();
      expect(loadedProfile?.id, 'uid-sync-1');
      expect(loadedProfile?.email, 'sync@noukin.app');
      expect(await local.loadSessionCount(), 4);

      // Remote returns unsorted sessions -> loadSessionHistory sorts ascending.
      final sLate = WorkoutSessionRecord(
        id: '550e8400-e29b-41d4-a716-446655440002',
        completedAt: DateTime.utc(2026, 11, 19, 18, 0),
        durationCourse: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        timeSlot: TimeSlot.evening,
        exercises: const <CompletedExerciseRecord>[],
        feedback: WorkoutFeedback.tooHard,
        createdAt: DateTime.utc(2026, 11, 19, 18, 20),
      );
      final sEarly = WorkoutSessionRecord(
        id: '550e8400-e29b-41d4-a716-446655440001',
        completedAt: DateTime.utc(2026, 11, 18, 8, 0),
        durationCourse: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.great,
        timeSlot: TimeSlot.morning,
        exercises: const <CompletedExerciseRecord>[],
        feedback: WorkoutFeedback.tooLight,
        createdAt: DateTime.utc(2026, 11, 18, 8, 20),
      );
      gateway.workoutSessionRows = <Map<String, dynamic>>[
        SupabaseWorkoutRepository.sessionToRow(sLate, userId: 'uid-sync-1'),
        SupabaseWorkoutRepository.sessionToRow(sEarly, userId: 'uid-sync-1'),
      ];

      final history = await repo.loadSessionHistory();
      expect(history.map((e) => e.id).toList(), <String>[sEarly.id, sLate.id]);
    });

    test('falls back cleanly to localCache when unauthenticated or remote throws', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final local = LocalWorkoutRepository(prefs);
      final gateway = _FakeSupabaseWorkoutGateway()..shouldThrow = true;

      String? activeUserId = 'uid-offline';
      final repo = SupabaseWorkoutRepository(
        localCache: local,
        remoteGateway: gateway,
        userIdProvider: () => activeUserId,
      );

      const profile = UserProfile(birthYear: 1988, bodyWeightKg: 68.0);
      await repo.saveProfile(profile);
      await repo.saveMuscleStates(
        MasterData.defaultMuscleStates(TrainingPurpose.health),
      );
      await repo.saveMachineHistory(MasterData.defaultMachineHistory());
      await repo.saveSessionCount(6);

      expect(await repo.loadProfile(), profile);
      expect(await repo.loadMuscleStates(), hasLength(54));
      expect(await repo.loadMachineHistory(), hasLength(29));
      expect(await repo.loadSessionCount(), 6);

      // Unauthenticated user does not touch remote gateway.
      activeUserId = null;
      gateway.shouldThrow = false;
      expect(await repo.loadProfile(), profile);
      expect(await repo.loadSessionCount(), 6);
    });

    test('real SupabaseClient falls back safely when network is blocked via HttpOverrides', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final local = LocalWorkoutRepository(prefs);
      await HttpOverrides.runZoned(() async {
        final client = SupabaseClient(
          'http://127.0.0.1:54321',
          'test-publishable-key',
          postgrestOptions: const PostgrestClientOptions(
            retryEnabled: false,
            requestTimeout: Duration(milliseconds: 500),
          ),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        final repo = SupabaseWorkoutRepository(
          localCache: local,
          client: client,
          userIdProvider: () => 'uid-blocked',
        );
        const profile = UserProfile(birthYear: 1994);
        await repo.saveProfile(profile);
        expect(await repo.loadProfile(), profile);
        expect(await repo.loadSessionCount(), 1);
        await client.dispose().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }, createHttpClient: _NoNetworkHttpOverrides().createHttpClient);
    });

    test('createWorkoutRepository returns LocalWorkoutRepository when unconfigured', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = createWorkoutRepository(prefs: prefs);
      expect(repo, isA<LocalWorkoutRepository>());
    });

    test('deduplicates non-UUID session IDs across online sync and offline fallback', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final local = LocalWorkoutRepository(prefs);
      final gateway = _FakeSupabaseWorkoutGateway();

      final repo = SupabaseWorkoutRepository(
        localCache: local,
        remoteGateway: gateway,
        userIdProvider: () => 'uid-dedup',
      );

      final localSession = WorkoutSessionRecord(
        id: 'local_sess_1',
        completedAt: DateTime.utc(2026, 11, 10, 9, 0),
        durationCourse: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        timeSlot: TimeSlot.morning,
        exercises: const <CompletedExerciseRecord>[],
        feedback: WorkoutFeedback.justRight,
        createdAt: DateTime.utc(2026, 11, 10, 9, 20),
      );

      await repo.saveSessionRecord(localSession);
      final expectedNormalizedId =
          SupabaseWorkoutRepository.normalizeSessionId('local_sess_1');

      final onlineHistory = await repo.loadSessionHistory();
      expect(onlineHistory, hasLength(1));
      expect(onlineHistory.first.id, expectedNormalizedId);

      gateway.shouldThrow = true;
      final offlineHistory = await repo.loadSessionHistory();
      expect(offlineHistory, hasLength(1));
      expect(offlineHistory.first.id, expectedNormalizedId);
    });

    test('batch-merges pre-existing non-UUID local sessions with remote rows without duplicates', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final local = LocalWorkoutRepository(prefs);
      final gateway = _FakeSupabaseWorkoutGateway();

      final legacyLocal = WorkoutSessionRecord(
        id: 'legacy_local_1',
        completedAt: DateTime.utc(2026, 11, 5, 8, 0),
        durationCourse: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        timeSlot: TimeSlot.morning,
        exercises: const <CompletedExerciseRecord>[],
        feedback: WorkoutFeedback.justRight,
        createdAt: DateTime.utc(2026, 11, 5, 8, 20),
      );
      final offlineOnly = WorkoutSessionRecord(
        id: 'offline_only_2',
        completedAt: DateTime.utc(2026, 11, 12, 8, 0),
        durationCourse: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.great,
        timeSlot: TimeSlot.morning,
        exercises: const <CompletedExerciseRecord>[],
        feedback: WorkoutFeedback.tooLight,
        createdAt: DateTime.utc(2026, 11, 12, 8, 45),
      );
      await local.saveSessionRecord(legacyLocal);
      await local.saveSessionRecord(offlineOnly);

      final remoteEarly = WorkoutSessionRecord(
        id: '550e8400-e29b-41d4-a716-446655440099',
        completedAt: DateTime.utc(2026, 11, 1, 7, 0),
        durationCourse: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.tired,
        timeSlot: TimeSlot.morning,
        exercises: const <CompletedExerciseRecord>[],
        feedback: WorkoutFeedback.tooHard,
        createdAt: DateTime.utc(2026, 11, 1, 7, 20),
      );
      gateway.workoutSessionRows = <Map<String, dynamic>>[
        SupabaseWorkoutRepository.sessionToRow(legacyLocal, userId: 'uid-merge'),
        SupabaseWorkoutRepository.sessionToRow(remoteEarly, userId: 'uid-merge'),
      ];

      final repo = SupabaseWorkoutRepository(
        localCache: local,
        remoteGateway: gateway,
        userIdProvider: () => 'uid-merge',
      );

      final mergedOnline = await repo.loadSessionHistory();
      expect(mergedOnline.map((e) => e.id).toList(), <String>[
        remoteEarly.id,
        SupabaseWorkoutRepository.normalizeSessionId('legacy_local_1'),
        SupabaseWorkoutRepository.normalizeSessionId('offline_only_2'),
      ]);

      gateway.shouldThrow = true;
      final mergedOffline = await repo.loadSessionHistory();
      expect(mergedOffline, mergedOnline);
    });
  });
}
