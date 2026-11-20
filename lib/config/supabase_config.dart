import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 接続設定（--dart-define または .env から注入し、キー類をコードに埋め込まない）
abstract final class SupabaseConfig {
  /// コンパイル時 `--dart-define=SUPABASE_URL=...` から注入される URL
  static const String url = String.fromEnvironment('SUPABASE_URL');

  /// コンパイル時 `--dart-define=SUPABASE_ANON_KEY=...` から注入される公開キー
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// モバイル・デスクトップ OAuth コールバック URI
  static const String oauthRedirectUri = 'io.noukin.app://login-callback';

  /// コンパイル時定数により Supabase が設定済みかどうか
  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  static bool _initialized = false;

  /// `Supabase.initialize` がこのプロセスで正常完了したか（未初期化時の instance 参照を回避）
  static bool get isInitialized => _initialized;

  /// `.env` 形式のテキストをキー・値のマップにパースする
  static Map<String, String> parseEnvContent(String content) {
    final result = <String, String>{};
    final normalizedContent = content.startsWith('\uFEFF')
        ? content.substring(1)
        : content;
    for (final rawLine in normalizedContent.split(RegExp(r'\r?\n'))) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      line = line.replaceFirst(RegExp(r'^export\s+'), '');
      final eqIndex = line.indexOf('=');
      if (eqIndex <= 0) {
        continue;
      }
      final key = line.substring(0, eqIndex).trim();
      if (key.isEmpty) {
        continue;
      }
      final rawValue = line.substring(eqIndex + 1).trim();
      result[key] = _parseEnvValue(rawValue);
    }
    return result;
  }

  static String _parseEnvValue(String rawValue) {
    if (rawValue.isEmpty || rawValue.startsWith('#')) {
      return '';
    }
    final first = rawValue[0];
    if (first == '"' || first == "'") {
      var closeIndex = -1;
      for (var i = 1; i < rawValue.length; i++) {
        if (first == '"' &&
            rawValue[i] == r'\' &&
            i + 1 < rawValue.length) {
          i++;
          continue;
        }
        if (rawValue[i] == first) {
          closeIndex = i;
          break;
        }
      }
      if (closeIndex >= 1) {
        final trailing = rawValue.substring(closeIndex + 1).trim();
        if (trailing.isEmpty || trailing.startsWith('#')) {
          return rawValue.substring(1, closeIndex);
        }
      }
    }
    final commentMatch = RegExp(r'\s#').firstMatch(rawValue);
    if (commentMatch != null) {
      return rawValue.substring(0, commentMatch.start).trimRight();
    }
    return rawValue;
  }

  /// コンパイル時定数 → `overrideEnv` → `.env` ファイルの優先順で認証情報を解決する
  static ({String url, String anonKey}) resolveCredentials({
    String? envFilePath,
    Map<String, String>? overrideEnv,
  }) {
    var resolvedUrl = url.trim();
    var resolvedKey = anonKey.trim();

    if (resolvedUrl.isNotEmpty && resolvedKey.isNotEmpty) {
      return (url: resolvedUrl, anonKey: resolvedKey);
    }

    if (overrideEnv != null) {
      if (resolvedUrl.isEmpty) {
        resolvedUrl = (overrideEnv['SUPABASE_URL'] ?? '').trim();
      }
      if (resolvedKey.isEmpty) {
        resolvedKey = (overrideEnv['SUPABASE_ANON_KEY'] ?? '').trim();
      }
      if (envFilePath == null ||
          (resolvedUrl.isNotEmpty && resolvedKey.isNotEmpty)) {
        return (url: resolvedUrl, anonKey: resolvedKey);
      }
    }

    if (!kIsWeb) {
      try {
        final file = File(envFilePath ?? '.env');
        if (file.existsSync()) {
          final parsed = parseEnvContent(file.readAsStringSync());
          if (resolvedUrl.isEmpty) {
            resolvedUrl = (parsed['SUPABASE_URL'] ?? '').trim();
          }
          if (resolvedKey.isEmpty) {
            resolvedKey = (parsed['SUPABASE_ANON_KEY'] ?? '').trim();
          }
        }
      } catch (_) {
        // ファイル読み込み不可時は空設定のまま安全にフォールバックする
      }
    }

    return (url: resolvedUrl, anonKey: resolvedKey);
  }

  /// 設定が有効な場合のみ Supabase を初期化する（未設定・オフライン時は例外を投げず false）
  static Future<bool> initializeSupabaseIfConfigured({
    String? envFilePath,
    Map<String, String>? overrideEnv,
    bool? debug,
  }) async {
    if (_initialized) {
      return true;
    }

    final creds = resolveCredentials(
      envFilePath: envFilePath,
      overrideEnv: overrideEnv,
    );
    if (creds.url.isEmpty || creds.anonKey.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(creds.url);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    try {
      await Supabase.initialize(
        url: creds.url,
        publishableKey: creds.anonKey,
        postgrestOptions: const PostgrestClientOptions(
          retryEnabled: false,
          requestTimeout: Duration(seconds: 5),
        ),
        debug: debug,
      );
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `initializeSupabaseIfConfigured` のエイリアス
  static Future<bool> initializeIfConfigured({
    String? envFilePath,
    Map<String, String>? overrideEnv,
    bool? debug,
  }) {
    return initializeSupabaseIfConfigured(
      envFilePath: envFilePath,
      overrideEnv: overrideEnv,
      debug: debug,
    );
  }
}
