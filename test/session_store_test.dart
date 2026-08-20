import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SessionController holds the JWT/session identity and had zero direct test
// coverage before this — everything else (the router redirect, the 401
// force-logout hook, every screen watching sessionProvider) depends on its
// behavior being correct. Backed by a fake in-memory implementation of the
// flutter_secure_storage platform channel so this runs under plain
// `flutter test`, no real keychain/keystore needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> fakeSecureStore;

  setUp(() {
    fakeSecureStore = {};
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          switch (call.method) {
            case 'write':
              fakeSecureStore[args['key'] as String] = args['value'] as String;
              return null;
            case 'read':
              return fakeSecureStore[args['key'] as String];
            case 'delete':
              fakeSecureStore.remove(args['key'] as String);
              return null;
            case 'deleteAll':
              fakeSecureStore.clear();
              return null;
            case 'containsKey':
              return fakeSecureStore.containsKey(args['key'] as String);
            case 'readAll':
              return fakeSecureStore;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'restore populates the session from previously-written storage',
    () async {
      fakeSecureStore['leadpilot_token'] = 'tok-123';
      fakeSecureStore['leadpilot_user'] = jsonEncode({
        'id': 'u1',
        'name': 'Priya',
        'email': 'priya@example.com',
        'role': 'telecaller',
        'org_name': 'Acme',
        'must_reset_password': false,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // build() starts empty; _restore() runs as a fire-and-forget microtask.
      expect(container.read(sessionProvider).isLoggedIn, isFalse);
      await pumpEventQueue();

      final session = container.read(sessionProvider);
      expect(session.isLoggedIn, isTrue);
      expect(session.token, 'tok-123');
      expect(session.name, 'Priya');
    },
  );

  test('restore leaves the session empty when nothing was stored', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpEventQueue();
    expect(container.read(sessionProvider).isLoggedIn, isFalse);
  });

  test('logout clears secure storage and resets state to empty', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpEventQueue();

    await container
        .read(sessionProvider.notifier)
        .setSession(token: 'tok-123', user: {'id': 'u1', 'name': 'Priya'});
    expect(container.read(sessionProvider).isLoggedIn, isTrue);

    await container.read(sessionProvider.notifier).logout();

    expect(container.read(sessionProvider).isLoggedIn, isFalse);
    expect(fakeSecureStore.containsKey('leadpilot_token'), isFalse);
    expect(fakeSecureStore.containsKey('leadpilot_user'), isFalse);
  });

  test('clearMustResetPassword flips the flag and persists it', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpEventQueue();

    await container
        .read(sessionProvider.notifier)
        .setSession(
          token: 'tok-123',
          user: {'id': 'u1', 'name': 'Priya', 'must_reset_password': true},
        );
    expect(container.read(sessionProvider).mustResetPassword, isTrue);

    await container.read(sessionProvider.notifier).clearMustResetPassword();

    expect(container.read(sessionProvider).mustResetPassword, isFalse);
    final persisted = jsonDecode(fakeSecureStore['leadpilot_user']!) as Map;
    expect(persisted['must_reset_password'], isFalse);
  });

  // Regression cover for the null-token race fix: a concurrent force-logout
  // can clear secure storage while clearMustResetPassword() is still in
  // flight (e.g. the token just expired mid password-change) — it must
  // no-op instead of force-unwrapping the now-cleared token and throwing.
  test(
    'clearMustResetPassword does not throw when storage was cleared concurrently',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpEventQueue();

      await container
          .read(sessionProvider.notifier)
          .setSession(
            token: 'tok-123',
            user: {'id': 'u1', 'name': 'Priya', 'must_reset_password': true},
          );

      // Simulate a concurrent logout clearing storage first.
      fakeSecureStore.clear();

      await expectLater(
        container.read(sessionProvider.notifier).clearMustResetPassword(),
        completes,
      );
    },
  );
}
