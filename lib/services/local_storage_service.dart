import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 上で使用する永続化キー一覧
abstract final class LocalStorageKeys {
  static const String authUser = 'noukin_auth_user';
  static const String userProfile = 'noukin_user_profile';
  static const String muscleStates = 'noukin_muscle_states';
  static const String machineHistory = 'noukin_machine_history';
  static const String sessionHistory = 'noukin_session_history';
  static const String sessionCount = 'noukin_session_count';
}

/// 破損 JSON や型不整合に対して安全なローカルストレージ読み書きラッパー
class LocalStorageService {
  final SharedPreferences prefs;

  const LocalStorageService(this.prefs);

  /// JSON オブジェクト（Map）を安全に読み込む。破損時は null を返す。
  Map<String, dynamic>? readJsonMap(String key) {
    final raw = prefs.get(key);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// JSON 配列（List）を安全に読み込む。破損時は null を返す。
  List<dynamic>? readJsonList(String key) {
    final raw = prefs.get(key);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 整数を型安全に読み込む。文字列等で上書きされた場合や NaN/Infinity でも例外を起こさない。
  int? readInt(String key) {
    final raw = prefs.get(key);
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.isFinite ? raw.toInt() : null;
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  Future<void> writeJson(String key, Object value) async {
    await prefs.setString(key, jsonEncode(value));
  }

  Future<void> writeInt(String key, int value) async {
    await prefs.setInt(key, value);
  }

  Future<void> remove(String key) async {
    await prefs.remove(key);
  }
}
