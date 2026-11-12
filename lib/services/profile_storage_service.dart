import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

/// ユーザープロフィールと初回起動状態を永続化・管理するインターフェース
abstract class ProfileStorageService {
  /// 初回オンボーディングが完了済みかどうかを取得
  Future<bool> isOnboardingCompleted();

  /// 初回オンボーディングの完了状態とプロフィールを保存
  Future<void> saveUserProfile(UserProfile profile);

  /// 保存されたプロフィールを取得（未保存なら null）
  Future<UserProfile?> getUserProfile();

  /// 保存データをクリア（デバッグ・テスト用）
  Future<void> clear();
}

/// SharedPreferences を用いた本番用実装
class SharedPrefsProfileStorageService implements ProfileStorageService {
  static const String _keyOnboardingCompleted = 'onboarding_completed';
  static const String _keyUserProfile = 'user_profile_data';

  final SharedPreferencesAsync _asyncPrefs;

  SharedPrefsProfileStorageService({SharedPreferencesAsync? asyncPrefs})
      : _asyncPrefs = asyncPrefs ?? SharedPreferencesAsync();

  @override
  Future<bool> isOnboardingCompleted() async {
    final completed = await _asyncPrefs.getBool(_keyOnboardingCompleted);
    return completed ?? false;
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    final jsonString = jsonEncode(profile.toJson());
    await _asyncPrefs.setString(_keyUserProfile, jsonString);
    await _asyncPrefs.setBool(_keyOnboardingCompleted, true);
  }

  @override
  Future<UserProfile?> getUserProfile() async {
    final raw = await _asyncPrefs.getString(_keyUserProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _asyncPrefs.remove(_keyUserProfile);
    await _asyncPrefs.remove(_keyOnboardingCompleted);
  }
}

/// 自動テスト用のインメモリ実装
class InMemoryProfileStorageService implements ProfileStorageService {
  bool _isCompleted = false;
  UserProfile? _profile;

  InMemoryProfileStorageService({bool initialCompleted = false, UserProfile? initialProfile})
      : _isCompleted = initialCompleted,
        _profile = initialProfile;

  @override
  Future<bool> isOnboardingCompleted() async => _isCompleted;

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    _profile = profile;
    _isCompleted = true;
  }

  @override
  Future<UserProfile?> getUserProfile() async => _profile;

  @override
  Future<void> clear() async {
    _isCompleted = false;
    _profile = null;
  }
}
