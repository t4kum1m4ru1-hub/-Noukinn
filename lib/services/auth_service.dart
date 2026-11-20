import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../config/supabase_config.dart';
import '../models/models.dart';
import 'local_storage_service.dart';

/// 認証サービス契約（Supabase Auth / ローカルフォールバック共通）
abstract interface class AuthService {
  Future<AuthUser?> getCurrentUser();
  Future<AuthUser> signInWithGoogle();
  Future<void> signOut();
  bool get isLocalFallbackMode;
}

/// Supabase 未設定・オフライン時に利用するローカルフォールバック認証
class LocalAuthService implements AuthService {
  final LocalStorageService _storage;

  LocalAuthService(SharedPreferences prefs)
    : _storage = LocalStorageService(prefs);

  @override
  bool get isLocalFallbackMode => true;

  @override
  Future<AuthUser?> getCurrentUser() async {
    final map = _storage.readJsonMap(LocalStorageKeys.authUser);
    if (map == null) {
      return null;
    }
    try {
      final user = AuthUser.fromJson(map);
      if (user.id.trim().isEmpty) {
        return null;
      }
      return user;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    const user = AuthUser(
      id: 'local_user',
      email: 'local@noukin.app',
      displayName: 'ローカルユーザー',
      isLocalFallback: true,
    );
    await _storage.writeJson(LocalStorageKeys.authUser, user.toJson());
    return user;
  }

  @override
  Future<void> signOut() async {
    await _storage.remove(LocalStorageKeys.authUser);
  }
}

/// Supabase Google OAuth 認証サービス
class SupabaseAuthService implements AuthService {
  final GoTrueClient? _authClientOverride;
  final String _redirectTo;
  final Duration _oauthTimeout;
  final Future<bool> Function(OAuthProvider provider, String? redirectTo)?
  _oauthLauncherOverride;

  SupabaseAuthService({
    GoTrueClient? authClient,
    this._redirectTo = SupabaseConfig.oauthRedirectUri,
    this._oauthTimeout = const Duration(minutes: 3),
    Future<bool> Function(OAuthProvider provider, String? redirectTo)?
    oauthLauncher,
  }) : _authClientOverride = authClient,
       _oauthLauncherOverride = oauthLauncher;

  GoTrueClient get _auth {
    final override = _authClientOverride;
    if (override != null) {
      return override;
    }
    if (!SupabaseConfig.isInitialized) {
      throw StateError('Supabase is not initialized');
    }
    return Supabase.instance.client.auth;
  }

  @override
  bool get isLocalFallbackMode => false;

  AuthUser _mapUser(User user) {
    final rawFullName = user.userMetadata?['full_name'];
    final rawName = user.userMetadata?['name'];
    final fullName = rawFullName is String ? rawFullName : null;
    final name = rawName is String ? rawName : null;
    final candidate = (fullName ?? name)?.trim();
    return AuthUser(
      id: user.id,
      email: user.email,
      displayName: (candidate == null || candidate.isEmpty) ? null : candidate,
      isLocalFallback: false,
    );
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return null;
      }
      return _mapUser(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    final existing = _auth.currentUser;
    if (existing != null) {
      return _mapUser(existing);
    }

    final completer = Completer<AuthUser>();
    completer.future.ignore();
    final subscription = _auth.onAuthStateChange.listen(
      (AuthState state) {
        final sessionUser = state.session?.user;
        if (sessionUser != null &&
            (state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.tokenRefreshed ||
                state.event == AuthChangeEvent.userUpdated ||
                state.event == AuthChangeEvent.initialSession)) {
          if (!completer.isCompleted) {
            completer.complete(_mapUser(sessionUser));
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    try {
      final targetRedirect = kIsWeb ? null : _redirectTo;
      final launched = _oauthLauncherOverride != null
          ? await _oauthLauncherOverride(OAuthProvider.google, targetRedirect)
          : await _auth.signInWithOAuth(
              OAuthProvider.google,
              redirectTo: targetRedirect,
            );
      if (!launched) {
        throw const AuthException('Google OAuth launch failed');
      }

      final currentAfterLaunch = _auth.currentUser;
      if (currentAfterLaunch != null && !completer.isCompleted) {
        completer.complete(_mapUser(currentAfterLaunch));
      }

      return await completer.future.timeout(_oauthTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }
}

/// 実行環境に応じて SupabaseAuthService または LocalAuthService を生成する
AuthService createAuthService({
  required SharedPreferences prefs,
  SupabaseClient? client,
}) {
  if (client != null || SupabaseConfig.isInitialized) {
    return SupabaseAuthService(authClient: client?.auth);
  }
  return LocalAuthService(prefs);
}
