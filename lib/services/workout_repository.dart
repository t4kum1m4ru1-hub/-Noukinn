import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import 'local_storage_service.dart';
import 'supabase_workout_repository.dart';

/// ユーザーデータ・トレーニング履歴の永続化契約
abstract interface class WorkoutRepository {
  Future<UserProfile?> loadProfile();
  Future<void> saveProfile(UserProfile profile);

  Future<Map<String, MuscleInputState>> loadMuscleStates();
  Future<void> saveMuscleStates(Map<String, MuscleInputState> states);

  Future<Map<String, MachineHistoryEntry>> loadMachineHistory();
  Future<void> saveMachineHistory(Map<String, MachineHistoryEntry> history);

  Future<List<WorkoutSessionRecord>> loadSessionHistory();
  Future<void> saveSessionRecord(WorkoutSessionRecord record);

  Future<int> loadSessionCount();
  Future<void> saveSessionCount(int count);
}

/// SharedPreferences を用いたオフライン完結・破損耐性ローカルリポジトリ
class LocalWorkoutRepository implements WorkoutRepository {
  final LocalStorageService _storage;
  Future<void> _sessionWriteQueue = Future<void>.value();

  LocalWorkoutRepository(SharedPreferences prefs)
    : _storage = LocalStorageService(prefs);

  @override
  Future<UserProfile?> loadProfile() async {
    final map = _storage.readJsonMap(LocalStorageKeys.userProfile);
    if (map == null) {
      return null;
    }
    try {
      return UserProfile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    await _storage.writeJson(LocalStorageKeys.userProfile, profile.toJson());
  }

  @override
  Future<Map<String, MuscleInputState>> loadMuscleStates() async {
    final map = _storage.readJsonMap(LocalStorageKeys.muscleStates);
    if (map == null) {
      return <String, MuscleInputState>{};
    }

    final result = <String, MuscleInputState>{};
    for (final entry in map.entries) {
      final rawValue = entry.value;
      if (rawValue is! Map) {
        continue;
      }
      try {
        final parsed = MuscleInputState.fromJson(
          Map<String, dynamic>.from(rawValue),
        );
        if (parsed.muscleId.isNotEmpty) {
          result[entry.key] = parsed;
        }
      } catch (_) {
        // 破損した個別エントリをスキップして他データを保護する
      }
    }
    return result;
  }

  @override
  Future<void> saveMuscleStates(Map<String, MuscleInputState> states) async {
    final encoded = <String, dynamic>{
      for (final entry in states.entries) entry.key: entry.value.toJson(),
    };
    await _storage.writeJson(LocalStorageKeys.muscleStates, encoded);
  }

  @override
  Future<Map<String, MachineHistoryEntry>> loadMachineHistory() async {
    final map = _storage.readJsonMap(LocalStorageKeys.machineHistory);
    if (map == null) {
      return <String, MachineHistoryEntry>{};
    }

    final result = <String, MachineHistoryEntry>{};
    for (final entry in map.entries) {
      final rawValue = entry.value;
      if (rawValue is! Map) {
        continue;
      }
      try {
        final parsed = MachineHistoryEntry.fromJson(
          Map<String, dynamic>.from(rawValue),
        );
        if (parsed.machineId.isNotEmpty) {
          result[entry.key] = parsed;
        }
      } catch (_) {
        // 破損した個別エントリをスキップして他データを保護する
      }
    }
    return result;
  }

  @override
  Future<void> saveMachineHistory(
    Map<String, MachineHistoryEntry> history,
  ) async {
    final encoded = <String, dynamic>{
      for (final entry in history.entries) entry.key: entry.value.toJson(),
    };
    await _storage.writeJson(LocalStorageKeys.machineHistory, encoded);
  }

  static List<WorkoutSessionRecord> sortSessionsChronologically(
    List<WorkoutSessionRecord> records,
  ) {
    if (records.length <= 1) {
      return records;
    }
    final indexed = <({int index, WorkoutSessionRecord record})>[
      for (var i = 0; i < records.length; i++) (index: i, record: records[i]),
    ];
    indexed.sort((a, b) {
      final cmp = a.record.completedAt.compareTo(b.record.completedAt);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });
    return indexed.map((e) => e.record).toList();
  }

  @override
  Future<List<WorkoutSessionRecord>> loadSessionHistory() async {
    final list = _storage.readJsonList(LocalStorageKeys.sessionHistory);
    if (list == null) {
      return <WorkoutSessionRecord>[];
    }

    final result = <WorkoutSessionRecord>[];
    for (final item in list) {
      if (item is! Map) {
        continue;
      }
      try {
        result.add(
          WorkoutSessionRecord.fromJson(Map<String, dynamic>.from(item)),
        );
      } catch (_) {
        // 破損した個別セッションをスキップする
      }
    }
    return sortSessionsChronologically(result);
  }

  @override
  Future<void> saveSessionRecord(WorkoutSessionRecord record) {
    final next = _sessionWriteQueue.catchError((_) {}).then((_) async {
      final existing = await loadSessionHistory();
      final updated = List<WorkoutSessionRecord>.from(existing);
      final index = updated.indexWhere((item) => item.id == record.id);
      if (index >= 0) {
        updated[index] = record;
      } else {
        updated.add(record);
      }

      await _storage.writeJson(
        LocalStorageKeys.sessionHistory,
        sortSessionsChronologically(updated).map((e) => e.toJson()).toList(),
      );
    });
    _sessionWriteQueue = next.catchError((_) {});
    return next;
  }

  /// セッション履歴全体を一括保存する（同期時の一括書き換え用）
  Future<void> saveSessionHistory(List<WorkoutSessionRecord> records) {
    final next = _sessionWriteQueue.catchError((_) {}).then((_) async {
      await _storage.writeJson(
        LocalStorageKeys.sessionHistory,
        sortSessionsChronologically(records).map((e) => e.toJson()).toList(),
      );
    });
    _sessionWriteQueue = next.catchError((_) {});
    return next;
  }

  /// 正規化済みIDで重複排除しつつセッションを保存する（キュー直列化）
  Future<void> saveNormalizedSessionRecord(
    WorkoutSessionRecord normalizedRecord,
    String Function(String id) normalizeId,
  ) {
    final next = _sessionWriteQueue.catchError((_) {}).then((_) async {
      final existing = await loadSessionHistory();
      final deduped = <WorkoutSessionRecord>[];
      var replaced = false;
      for (final item in existing) {
        final itemNormalizedId = item.id.trim().isEmpty
            ? ''
            : normalizeId(item.id);
        if (item.id == normalizedRecord.id ||
            itemNormalizedId == normalizedRecord.id) {
          if (!replaced) {
            deduped.add(normalizedRecord);
            replaced = true;
          }
        } else {
          deduped.add(item);
        }
      }
      if (!replaced) {
        deduped.add(normalizedRecord);
      }
      await _storage.writeJson(
        LocalStorageKeys.sessionHistory,
        sortSessionsChronologically(deduped).map((e) => e.toJson()).toList(),
      );
    });
    _sessionWriteQueue = next.catchError((_) {});
    return next;
  }

  @override
  Future<int> loadSessionCount() async {
    final count = _storage.readInt(LocalStorageKeys.sessionCount);
    if (count == null || count <= 0) {
      return 1;
    }
    return count;
  }

  @override
  Future<void> saveSessionCount(int count) async {
    await _storage.writeInt(
      LocalStorageKeys.sessionCount,
      count <= 0 ? 1 : count,
    );
  }
}

/// 実行環境に応じて Supabase 同期リポジトリまたはローカルリポジトリを生成する
WorkoutRepository createWorkoutRepository({
  required SharedPreferences prefs,
  SupabaseClient? client,
}) {
  final local = LocalWorkoutRepository(prefs);
  if (client != null || SupabaseConfig.isInitialized) {
    return SupabaseWorkoutRepository(localCache: local, client: client);
  }
  return local;
}
