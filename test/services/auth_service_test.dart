import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/config/supabase_config.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/services/auth_service.dart';
import 'package:noukin/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw StateError('Network access is disabled in unit tests');
  }
}

class _FakeGoTrueClient implements GoTrueClient {
  final StreamController<AuthState> authController =
      StreamController<AuthState>.broadcast();

  User? fakeCurrentUser;
  bool signOutCalled = false;
  SignOutScope? lastSignOutScope;

  @override
  User? get currentUser => fakeCurrentUser;

  @override
  Stream<AuthState> get onAuthStateChange => authController.stream;

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutCalled = true;
    lastSignOutScope = scope;
    fakeCurrentUser = null;
  }

  @override
  Future<void> dispose() async {
    await authController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _buildSupabaseUser({
  String id = 'supa-user-1',
  String? email = 'athlete@noukin.app',
  Map<String, dynamic>? userMetadata = const <String, dynamic>{
    'full_name': 'テスト選手',
  },
}) {
  return User(
    id: id,
    appMetadata: const <String, dynamic>{'provider': 'google'},
    userMetadata: userMetadata,
    aud: 'authenticated',
    email: email,
    createdAt: '2026-11-19T00:00:00Z',
  );
}

Session _buildSession(User user) {
  return Session(
    accessToken: 'fake-access-token',
    tokenType: 'bearer',
    user: user,
  );
}

void main() {
  group('LocalAuthService', () {
    test('completes offline sign-in, persistence across instances, and sign-out', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await HttpOverrides.runZoned(() async {
        final auth = LocalAuthService(prefs);
        expect(auth.isLocalFallbackMode, isTrue);
        expect(await auth.getCurrentUser(), isNull);

        final user = await auth.signInWithGoogle();
        expect(user.id, 'local_user');
        expect(user.email, 'local@noukin.app');
        expect(user.displayName, 'ローカルユーザー');
        expect(user.isLocalFallback, isTrue);

        final reloaded = await LocalAuthService(prefs).getCurrentUser();
        expect(reloaded, user);

        await auth.signOut();
        expect(await auth.getCurrentUser(), isNull);
      }, createHttpClient: _NoNetworkHttpOverrides().createHttpClient);
    });

    test('recovers cleanly from corrupted JSON or wrong scalar type in prefs', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LocalStorageKeys.authUser: '{corrupted_json_payload::[',
      });
      final prefs = await SharedPreferences.getInstance();
      final auth = LocalAuthService(prefs);
      expect(await auth.getCurrentUser(), isNull);

      await prefs.setString(LocalStorageKeys.authUser, '[]');
      expect(await auth.getCurrentUser(), isNull);

      await prefs.setString(LocalStorageKeys.authUser, '{"id": ""}');
      expect(await auth.getCurrentUser(), isNull);

      await prefs.setInt(LocalStorageKeys.authUser, 42);
      expect(await auth.getCurrentUser(), isNull);
    });
  });

  group('SupabaseAuthService', () {
    test('maps currentUser metadata and handles null user', () async {
      final fakeClient = _FakeGoTrueClient();
      addTearDown(fakeClient.dispose);

      final service = SupabaseAuthService(authClient: fakeClient);
      expect(service.isLocalFallbackMode, isFalse);
      expect(await service.getCurrentUser(), isNull);

      fakeClient.fakeCurrentUser = _buildSupabaseUser(
        id: 'uid-1',
        email: 'u1@noukin.app',
        userMetadata: const <String, dynamic>{'full_name': 'のう筋 太郎'},
      );
      expect(
        await service.getCurrentUser(),
        const AuthUser(
          id: 'uid-1',
          email: 'u1@noukin.app',
          displayName: 'のう筋 太郎',
          isLocalFallback: false,
        ),
      );

      fakeClient.fakeCurrentUser = _buildSupabaseUser(
        id: 'uid-2',
        email: null,
        userMetadata: const <String, dynamic>{'name': 'Fallback Name'},
      );
      expect(
        await service.getCurrentUser(),
        const AuthUser(
          id: 'uid-2',
          email: null,
          displayName: 'Fallback Name',
          isLocalFallback: false,
        ),
      );

      fakeClient.fakeCurrentUser = _buildSupabaseUser(
        id: 'uid-3',
        userMetadata: const <String, dynamic>{'full_name': '   '},
      );
      expect((await service.getCurrentUser())?.displayName, isNull);
    });

    test('signInWithGoogle returns immediately if already signed in', () async {
      final fakeClient = _FakeGoTrueClient();
      addTearDown(fakeClient.dispose);
      fakeClient.fakeCurrentUser = _buildSupabaseUser(id: 'existing-uid');

      var launched = false;
      final service = SupabaseAuthService(
        authClient: fakeClient,
        oauthLauncher: (_, _) async {
          launched = true;
          return true;
        },
      );

      final user = await service.signInWithGoogle();
      expect(launched, isFalse);
      expect(user.id, 'existing-uid');
      expect(user.isLocalFallback, isFalse);
    });

    test('signInWithGoogle subscribes before launch and completes on signedIn event', () async {
      final fakeClient = _FakeGoTrueClient();
      addTearDown(fakeClient.dispose);

      OAuthProvider? capturedProvider;
      String? capturedRedirect;
      final service = SupabaseAuthService(
        authClient: fakeClient,
        oauthLauncher: (provider, redirectTo) async {
          capturedProvider = provider;
          capturedRedirect = redirectTo;
          final user = _buildSupabaseUser(id: 'oauth-uid-99');
          fakeClient.fakeCurrentUser = user;
          fakeClient.authController.add(
            AuthState(AuthChangeEvent.signedIn, _buildSession(user)),
          );
          return true;
        },
      );

      final user = await service.signInWithGoogle();
      expect(capturedProvider, OAuthProvider.google);
      expect(capturedRedirect, SupabaseConfig.oauthRedirectUri);
      expect(user.id, 'oauth-uid-99');
      expect(user.isLocalFallback, isFalse);
    });

    test('signInWithGoogle throws AuthException when browser launch fails', () async {
      final fakeClient = _FakeGoTrueClient();
      addTearDown(fakeClient.dispose);

      final service = SupabaseAuthService(
        authClient: fakeClient,
        oauthLauncher: (_, _) async => false,
      );

      await expectLater(
        service.signInWithGoogle(),
        throwsA(isA<AuthException>()),
      );
    });

    test('signInWithGoogle propagates stream errors and times out cleanly', () async {
      final fakeClient = _FakeGoTrueClient();
      addTearDown(fakeClient.dispose);

      final errorService = SupabaseAuthService(
        authClient: fakeClient,
        oauthLauncher: (_, _) async {
          scheduleMicrotask(() {
            fakeClient.authController.addError(
              const AuthException('network failure'),
            );
          });
          return true;
        },
      );
      await expectLater(
        errorService.signInWithGoogle(),
        throwsA(isA<AuthException>()),
      );

      final timeoutService = SupabaseAuthService(
        authClient: fakeClient,
        oauthTimeout: const Duration(milliseconds: 20),
        oauthLauncher: (_, _) async => true,
      );
      await expectLater(
        timeoutService.signInWithGoogle(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('signOut delegates to GoTrueClient.signOut', () async {
      final fakeClient = _FakeGoTrueClient();
      addTearDown(fakeClient.dispose);
      fakeClient.fakeCurrentUser = _buildSupabaseUser();

      final service = SupabaseAuthService(authClient: fakeClient);
      await service.signOut();
      expect(fakeClient.signOutCalled, isTrue);
      expect(await service.getCurrentUser(), isNull);
    });

    test('createAuthService falls back to LocalAuthService when uninitialized', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = createAuthService(prefs: prefs);
      expect(service, isA<LocalAuthService>());
      expect(service.isLocalFallbackMode, isTrue);
    });

    test('getCurrentUser handles non-String userMetadata values safely without dropping user', () async {
      final fakeClient = _FakeGoTrueClient();
      addTearDown(fakeClient.dispose);

      final service = SupabaseAuthService(authClient: fakeClient);

      fakeClient.fakeCurrentUser = _buildSupabaseUser(
        id: 'uid-non-string-1',
        email: 'nonstring@noukin.app',
        userMetadata: const <String, dynamic>{'full_name': 12345},
      );
      final user1 = await service.getCurrentUser();
      expect(user1, isNotNull);
      expect(user1!.id, 'uid-non-string-1');
      expect(user1.email, 'nonstring@noukin.app');
      expect(user1.displayName, isNull);

      fakeClient.fakeCurrentUser = _buildSupabaseUser(
        id: 'uid-non-string-2',
        userMetadata: const <String, dynamic>{
          'full_name': <String>['invalid'],
          'name': 'Fallback String Name',
        },
      );
      final user2 = await service.getCurrentUser();
      expect(user2, isNotNull);
      expect(user2!.displayName, 'Fallback String Name');

      fakeClient.fakeCurrentUser = _buildSupabaseUser(
        id: 'uid-non-string-3',
        userMetadata: const <String, dynamic>{'full_name': true, 'name': 99},
      );
      final user3 = await service.getCurrentUser();
      expect(user3, isNotNull);
      expect(user3!.displayName, isNull);
    });

    test('signInWithGoogle produces no unhandled Zone error if stream errors before launch failure', () async {
      final unhandledErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final fakeClient = _FakeGoTrueClient();
          addTearDown(fakeClient.dispose);

          final falseLaunchService = SupabaseAuthService(
            authClient: fakeClient,
            oauthLauncher: (_, _) async {
              fakeClient.authController.addError(
                const AuthException('stream error before launch return'),
              );
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return false;
            },
          );

          await expectLater(
            falseLaunchService.signInWithGoogle(),
            throwsA(isA<AuthException>()),
          );

          final throwLaunchService = SupabaseAuthService(
            authClient: fakeClient,
            oauthLauncher: (_, _) async {
              fakeClient.authController.addError(
                const AuthException('stream error before launch throw'),
              );
              await Future<void>.delayed(const Duration(milliseconds: 20));
              throw StateError('launcher threw');
            },
          );

          await expectLater(
            throwLaunchService.signInWithGoogle(),
            throwsA(isA<StateError>()),
          );

          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
        (error, _) {
          unhandledErrors.add(error);
        },
      );

      expect(unhandledErrors, isEmpty);
    });
  });
}
