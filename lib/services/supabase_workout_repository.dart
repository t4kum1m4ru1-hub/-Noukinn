import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import 'workout_repository.dart';

/// Supabase テーブル操作のテスト可能ゲートウェイ契約
abstract interface class SupabaseWorkoutGateway {
  Future<Map<String, dynamic>?> fetchProfileRow(String userId);
  Future<void> upsertProfileRow(Map<String, dynamic> row);
  Future<int?> fetchSessionCount(String userId);
  Future<void> upsertSessionCountRow(Map<String, dynamic> row);
  Future<List<Map<String, dynamic>>> fetchMuscleStateRows(String userId);
  Future<void> upsertMuscleStateRows(List<Map<String, dynamic>> rows);
  Future<List<Map<String, dynamic>>> fetchMachineHistoryRows(String userId);
  Future<void> upsertMachineHistoryRows(List<Map<String, dynamic>> rows);
  Future<List<Map<String, dynamic>>> fetchWorkoutSessionRows(String userId);
  Future<void> upsertWorkoutSessionRow(Map<String, dynamic> row);
}

class _PostgrestWorkoutGateway implements SupabaseWorkoutGateway {
  final SupabaseClient _client;

  const _PostgrestWorkoutGateway(this._client);

  @override
  Future<Map<String, dynamic>?> fetchProfileRow(String userId) {
    return _client
        .from('user_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
  }

  @override
  Future<void> upsertProfileRow(Map<String, dynamic> row) async {
    await _client.from('user_profiles').upsert(row, onConflict: 'user_id');
  }

  @override
  Future<int?> fetchSessionCount(String userId) async {
    final row = await _client
        .from('user_profiles')
        .select('session_count')
        .eq('user_id', userId)
        .maybeSingle();
    return (row?['session_count'] as num?)?.toInt();
  }

  @override
  Future<void> upsertSessionCountRow(Map<String, dynamic> row) async {
    await _client.from('user_profiles').upsert(row, onConflict: 'user_id');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMuscleStateRows(String userId) async {
    final rows = await _client
        .from('muscle_states')
        .select()
        .eq('user_id', userId);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<void> upsertMuscleStateRows(List<Map<String, dynamic>> rows) async {
    await _client
        .from('muscle_states')
        .upsert(rows, onConflict: 'user_id,muscle_id');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMachineHistoryRows(
    String userId,
  ) async {
    final rows = await _client
        .from('machine_history')
        .select()
        .eq('user_id', userId);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<void> upsertMachineHistoryRows(List<Map<String, dynamic>> rows) async {
    await _client
        .from('machine_history')
        .upsert(rows, onConflict: 'user_id,machine_id');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWorkoutSessionRows(
    String userId,
  ) async {
    final rows = await _client
        .from('workout_sessions')
        .select()
        .eq('user_id', userId)
        .order('completed_at', ascending: true);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<void> upsertWorkoutSessionRow(Map<String, dynamic> row) async {
    await _client.from('workout_sessions').upsert(row, onConflict: 'id');
  }
}

/// ローカルキャッシュ書き込み先行 ＋ Supabase PostgreSQL 同期リポジトリ
class SupabaseWorkoutRepository implements WorkoutRepository {
  final LocalWorkoutRepository _localCache;
  final SupabaseClient? _clientOverride;
  final String? Function()? _userIdProvider;
  final String? Function()? _userEmailProvider;
  final SupabaseWorkoutGateway? _remoteGatewayOverride;
  final DateTime Function() _clock;

  static const Uuid _uuid = Uuid();

  SupabaseWorkoutRepository({
    required this._localCache,
    SupabaseClient? client,
    this._userIdProvider,
    this._userEmailProvider,
    SupabaseWorkoutGateway? remoteGateway,
    DateTime Function()? clock,
  }) : _clientOverride = client,
       _remoteGatewayOverride = remoteGateway,
       _clock = clock ?? DateTime.now;

  SupabaseClient? _resolveClient() {
    if (_clientOverride != null) {
      return _clientOverride;
    }
    if (!SupabaseConfig.isInitialized) {
      return null;
    }
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? _resolveUserId() {
    if (_userIdProvider != null) {
      return _userIdProvider();
    }
    try {
      return _resolveClient()?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? _resolveUserEmail() {
    if (_userEmailProvider != null) {
      return _userEmailProvider();
    }
    try {
      return _resolveClient()?.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  SupabaseWorkoutGateway? _resolveGateway() {
    if (_remoteGatewayOverride != null) {
      return _remoteGatewayOverride;
    }
    final client = _resolveClient();
    if (client == null) {
      return null;
    }
    return _PostgrestWorkoutGateway(client);
  }

  /// `user_profiles` テーブル用ペイロードへ変換する（`id` / `email` / `session_count` は除外）
  static Map<String, dynamic> profileToRow(
    UserProfile profile, {
    required String userId,
    DateTime? updatedAt,
  }) {
    return <String, dynamic>{
      'user_id': userId,
      'gender': profile.gender.id,
      'birth_year': profile.birthYear,
      'experience': profile.experience.id,
      'body_weight_kg': profile.bodyWeightKg,
      'purpose': profile.purpose.id,
      'is_first_time': profile.isFirstTime,
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  /// `user_profiles` の行データを `UserProfile` へ変換する
  static UserProfile profileFromRow(
    Map<String, dynamic> row, {
    String? email,
  }) {
    final normalized = Map<String, dynamic>.from(row);
    if (email != null && normalized['email'] == null) {
      normalized['email'] = email;
    }
    return UserProfile.fromJson(normalized);
  }

  /// `muscle_states` テーブル用行リストへ変換する
  static List<Map<String, dynamic>> muscleStatesToRows(
    Map<String, MuscleInputState> states, {
    required String userId,
    DateTime? updatedAt,
  }) {
    final isoNow = (updatedAt ?? DateTime.now()).toUtc().toIso8601String();
    return states.values
        .map(
          (state) => <String, dynamic>{
            ...state.toJson(),
            'user_id': userId,
            'updated_at': isoNow,
          },
        )
        .toList();
  }

  /// `muscle_states` の行リストをマップへ変換する
  static Map<String, MuscleInputState> muscleStatesFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, MuscleInputState>{};
    for (final row in rows) {
      try {
        final parsed = MuscleInputState.fromJson(row);
        if (parsed.muscleId.isNotEmpty) {
          result[parsed.muscleId] = parsed;
        }
      } catch (_) {
        // 不正行をスキップ
      }
    }
    return result;
  }

  /// `machine_history` テーブル用行リストへ変換する
  static List<Map<String, dynamic>> machineHistoryToRows(
    Map<String, MachineHistoryEntry> history, {
    required String userId,
    DateTime? updatedAt,
  }) {
    final isoNow = (updatedAt ?? DateTime.now()).toUtc().toIso8601String();
    return history.values
        .map(
          (entry) => <String, dynamic>{
            ...entry.toJson(),
            'user_id': userId,
            'updated_at': isoNow,
          },
        )
        .toList();
  }

  /// `machine_history` の行リストをマップへ変換する
  static Map<String, MachineHistoryEntry> machineHistoryFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, MachineHistoryEntry>{};
    for (final row in rows) {
      try {
        final parsed = MachineHistoryEntry.fromJson(row);
        if (parsed.machineId.isNotEmpty) {
          result[parsed.machineId] = parsed;
        }
      } catch (_) {
        // 不正行をスキップ
      }
    }
    return result;
  }

  /// `workout_sessions.id`（uuid 型）向けに非 UUID 文字列を決定論的 UUID v5 へ正規化する
  static String normalizeSessionId(String id) {
    final trimmed = id.trim();
    if (trimmed.isNotEmpty && Uuid.isValidUUID(fromString: trimmed)) {
      return trimmed;
    }
    if (trimmed.isNotEmpty) {
      return _uuid.v5(Namespace.oid.value, trimmed);
    }
    return _uuid.v4();
  }

  /// `workout_sessions` テーブル用行データへ変換する
  static Map<String, dynamic> sessionToRow(
    WorkoutSessionRecord record, {
    required String userId,
  }) {
    return <String, dynamic>{
      'id': normalizeSessionId(record.id),
      'user_id': userId,
      'completed_at': record.completedAt.toUtc().toIso8601String(),
      'duration_course': record.durationCourse.id,
      'condition': record.condition.id,
      'time_slot': record.timeSlot.id,
      'focus_muscle_id': record.focusMuscleId,
      'feedback': record.feedback.id,
      'exercises_json': record.exercises.map((e) => e.toJson()).toList(),
      'created_at': record.createdAt.toUtc().toIso8601String(),
    };
  }

  /// `workout_sessions` の行データを `WorkoutSessionRecord` へ変換する
  static WorkoutSessionRecord sessionFromRow(Map<String, dynamic> row) {
    return WorkoutSessionRecord.fromJson(row);
  }

  @override
  Future<UserProfile?> loadProfile() async {
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        final row = await gateway.fetchProfileRow(userId);
        if (row != null) {
          final profile = profileFromRow(row, email: _resolveUserEmail());
          await _localCache.saveProfile(profile);
          final remoteCount = (row['session_count'] as num?)?.toInt();
          if (remoteCount != null && remoteCount > 0) {
            await _localCache.saveSessionCount(remoteCount);
          }
          return profile;
        }
      } catch (_) {
        // オフライン・ネットワーク障害時はローカルキャッシュへフォールバック
      }
    }
    return _localCache.loadProfile();
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    await _localCache.saveProfile(profile);
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        await gateway.upsertProfileRow(
          profileToRow(profile, userId: userId, updatedAt: _clock()),
        );
      } catch (_) {
        // ローカルキャッシュへの保存は完了しているため障害時は握りつぶす
      }
    }
  }

  @override
  Future<Map<String, MuscleInputState>> loadMuscleStates() async {
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        final rows = await gateway.fetchMuscleStateRows(userId);
        if (rows.isNotEmpty) {
          final parsed = muscleStatesFromRows(rows);
          if (parsed.isNotEmpty) {
            await _localCache.saveMuscleStates(parsed);
            return parsed;
          }
        }
      } catch (_) {
        // オフライン時はローカルキャッシュへフォールバック
      }
    }
    return _localCache.loadMuscleStates();
  }

  @override
  Future<void> saveMuscleStates(Map<String, MuscleInputState> states) async {
    await _localCache.saveMuscleStates(states);
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null &&
        userId.isNotEmpty &&
        gateway != null &&
        states.isNotEmpty) {
      try {
        await gateway.upsertMuscleStateRows(
          muscleStatesToRows(states, userId: userId, updatedAt: _clock()),
        );
      } catch (_) {
        // オフライン時はローカル保存のみで継続
      }
    }
  }

  @override
  Future<Map<String, MachineHistoryEntry>> loadMachineHistory() async {
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        final rows = await gateway.fetchMachineHistoryRows(userId);
        if (rows.isNotEmpty) {
          final parsed = machineHistoryFromRows(rows);
          if (parsed.isNotEmpty) {
            await _localCache.saveMachineHistory(parsed);
            return parsed;
          }
        }
      } catch (_) {
        // オフライン時はローカルキャッシュへフォールバック
      }
    }
    return _localCache.loadMachineHistory();
  }

  @override
  Future<void> saveMachineHistory(
    Map<String, MachineHistoryEntry> history,
  ) async {
    await _localCache.saveMachineHistory(history);
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null &&
        userId.isNotEmpty &&
        gateway != null &&
        history.isNotEmpty) {
      try {
        await gateway.upsertMachineHistoryRows(
          machineHistoryToRows(history, userId: userId, updatedAt: _clock()),
        );
      } catch (_) {
        // オフライン時はローカル保存のみで継続
      }
    }
  }

  @override
  Future<List<WorkoutSessionRecord>> loadSessionHistory() async {
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        final rows = await gateway.fetchWorkoutSessionRows(userId);
        if (rows.isNotEmpty) {
          final parsed = <WorkoutSessionRecord>[];
          for (final row in rows) {
            try {
              parsed.add(sessionFromRow(row));
            } catch (_) {
              // 不正行をスキップ
            }
          }
          if (parsed.isNotEmpty) {
            final localRecords = await _localCache.loadSessionHistory();
            final mergedById = <String, WorkoutSessionRecord>{};
            for (final localRecord in localRecords) {
              final normalizedId = normalizeSessionId(localRecord.id);
              mergedById[normalizedId] = normalizedId == localRecord.id
                  ? localRecord
                  : localRecord.copyWith(id: normalizedId);
            }
            for (final remoteRecord in parsed) {
              final normalizedId = normalizeSessionId(remoteRecord.id);
              mergedById[normalizedId] = normalizedId == remoteRecord.id
                  ? remoteRecord
                  : remoteRecord.copyWith(id: normalizedId);
            }
            final merged = LocalWorkoutRepository.sortSessionsChronologically(
              mergedById.values.toList(),
            );
            await _localCache.saveSessionHistory(merged);
            return merged;
          }
        }
      } catch (_) {
        // オフライン時はローカルキャッシュへフォールバック
      }
    }
    return _localCache.loadSessionHistory();
  }

  @override
  Future<void> saveSessionRecord(WorkoutSessionRecord record) async {
    final normalizedId = normalizeSessionId(record.id);
    final normalizedRecord = normalizedId == record.id
        ? record
        : record.copyWith(id: normalizedId);
    await _localCache.saveNormalizedSessionRecord(
      normalizedRecord,
      normalizeSessionId,
    );

    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        await gateway.upsertWorkoutSessionRow(
          sessionToRow(normalizedRecord, userId: userId),
        );
      } catch (_) {
        // オフライン時はローカル保存のみで継続
      }
    }
  }

  @override
  Future<int> loadSessionCount() async {
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        final remoteCount = await gateway.fetchSessionCount(userId);
        if (remoteCount != null) {
          final normalized = remoteCount <= 0 ? 1 : remoteCount;
          await _localCache.saveSessionCount(normalized);
          return normalized;
        }
      } catch (_) {
        // オフライン時はローカルキャッシュへフォールバック
      }
    }
    return _localCache.loadSessionCount();
  }

  @override
  Future<void> saveSessionCount(int count) async {
    final normalized = count <= 0 ? 1 : count;
    await _localCache.saveSessionCount(normalized);
    final userId = _resolveUserId();
    final gateway = _resolveGateway();
    if (userId != null && userId.isNotEmpty && gateway != null) {
      try {
        await gateway.upsertSessionCountRow(<String, dynamic>{
          'user_id': userId,
          'session_count': normalized,
          'updated_at': _clock().toUtc().toIso8601String(),
        });
      } catch (_) {
        // オフライン時はローカル保存のみで継続
      }
    }
  }
}
