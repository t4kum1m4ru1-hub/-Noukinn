import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/config/supabase_config.dart';

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw StateError('Network access is disabled in unit tests');
  }
}

void main() {
  group('SupabaseConfig', () {
    test('defaults to unconfigured compile-time values and safe redirect URI', () {
      expect(SupabaseConfig.url, isEmpty);
      expect(SupabaseConfig.anonKey, isEmpty);
      expect(SupabaseConfig.isConfigured, isFalse);
      expect(SupabaseConfig.isInitialized, isFalse);
      expect(SupabaseConfig.oauthRedirectUri, 'io.noukin.app://login-callback');
    });

    test('parseEnvContent handles comments, exports, quotes, and equals signs', () {
      const content = '''
# Comment line
   # Indented comment

SUPABASE_URL="https://example.invalid"
export SUPABASE_ANON_KEY='test-key-with=padding=='
PLAIN_KEY=plain_value # inline comment
EMPTY_KEY=
INVALID_LINE_WITHOUT_EQUALS
''';

      final parsed = SupabaseConfig.parseEnvContent(content);
      expect(parsed['SUPABASE_URL'], 'https://example.invalid');
      expect(parsed['SUPABASE_ANON_KEY'], 'test-key-with=padding==');
      expect(parsed['PLAIN_KEY'], 'plain_value');
      expect(parsed['EMPTY_KEY'], '');
      expect(parsed.containsKey('INVALID_LINE_WITHOUT_EQUALS'), isFalse);
    });

    test('parseEnvContent handles UTF-8 BOM, export tab, and quoted values with trailing comments', () {
      const content =
          '\uFEFFBOM_KEY=bom_val\r\n'
          'export\tTAB_KEY=tab_val\r\n'
          'QUOTED_WITH_COMMENT="value" # trailing comment\r\n'
          "SINGLE_QUOTED_WITH_COMMENT='value2' # trailing comment\r\n"
          'HASH_IN_QUOTES="value # not comment"\r\n'
          'HASH_AND_TRAILING="value # not comment" # trailing comment\r\n'
          'EMPTY_QUOTED="" # empty comment\r\n'
          'URL_WITH_FRAGMENT=https://example.invalid/#section\r\n'
          'COMMENT_ONLY_VAL= # comment only\r\n';

      final parsed = SupabaseConfig.parseEnvContent(content);
      expect(parsed['BOM_KEY'], 'bom_val');
      expect(parsed['TAB_KEY'], 'tab_val');
      expect(parsed['QUOTED_WITH_COMMENT'], 'value');
      expect(parsed['SINGLE_QUOTED_WITH_COMMENT'], 'value2');
      expect(parsed['HASH_IN_QUOTES'], 'value # not comment');
      expect(parsed['HASH_AND_TRAILING'], 'value # not comment');
      expect(parsed['EMPTY_QUOTED'], '');
      expect(parsed['URL_WITH_FRAGMENT'], 'https://example.invalid/#section');
      expect(parsed['COMMENT_ONLY_VAL'], '');
    });

    test('resolveCredentials uses overrideEnv and trims whitespace', () {
      final creds = SupabaseConfig.resolveCredentials(
        overrideEnv: const <String, String>{
          'SUPABASE_URL': '  https://example.invalid  ',
          'SUPABASE_ANON_KEY': '  test-publishable-key  ',
        },
      );
      expect(creds.url, 'https://example.invalid');
      expect(creds.anonKey, 'test-publishable-key');
    });

    test('resolveCredentials reads from custom .env file path and ignores missing files', () async {
      final tempDir = await Directory.systemTemp.createTemp('noukin_env_test_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final envFile = File('${tempDir.path}${Platform.pathSeparator}.env');
      await envFile.writeAsString(
        'SUPABASE_URL=https://example.invalid\nSUPABASE_ANON_KEY=file-key\n',
      );

      final fromFile = SupabaseConfig.resolveCredentials(envFilePath: envFile.path);
      expect(fromFile.url, 'https://example.invalid');
      expect(fromFile.anonKey, 'file-key');

      final missing = SupabaseConfig.resolveCredentials(
        envFilePath: '${tempDir.path}${Platform.pathSeparator}nonexistent.env',
      );
      expect(missing.url, isEmpty);
      expect(missing.anonKey, isEmpty);
    });

    test('initializeSupabaseIfConfigured is a safe offline no-op when unconfigured or invalid', () async {
      await HttpOverrides.runZoned(() async {
        expect(
          await SupabaseConfig.initializeSupabaseIfConfigured(
            overrideEnv: const <String, String>{},
          ),
          isFalse,
        );
        expect(
          await SupabaseConfig.initializeIfConfigured(
            overrideEnv: const <String, String>{
              'SUPABASE_URL': 'https://example.invalid',
              'SUPABASE_ANON_KEY': '',
            },
          ),
          isFalse,
        );
        expect(
          await SupabaseConfig.initializeSupabaseIfConfigured(
            overrideEnv: const <String, String>{
              'SUPABASE_URL': 'ftp://example.invalid',
              'SUPABASE_ANON_KEY': 'test-key',
            },
          ),
          isFalse,
        );
        expect(
          await SupabaseConfig.initializeSupabaseIfConfigured(
            overrideEnv: const <String, String>{
              'SUPABASE_URL': 'not-a-valid-uri',
              'SUPABASE_ANON_KEY': 'test-key',
            },
          ),
          isFalse,
        );
        expect(SupabaseConfig.isInitialized, isFalse);
      }, createHttpClient: _NoNetworkHttpOverrides().createHttpClient);
    });

    test('.env.example contains template keys only with zero real secrets', () {
      final envExample = File('.env.example').readAsStringSync();
      expect(envExample, contains('SUPABASE_URL='));
      expect(envExample, contains('SUPABASE_ANON_KEY='));
      expect(
        RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}').hasMatch(envExample),
        isFalse,
      );
      expect(
        RegExp(r'https://[a-z0-9-]+\.supabase\.co', caseSensitive: false)
            .hasMatch(envExample),
        isFalse,
      );
    });
  });
}
