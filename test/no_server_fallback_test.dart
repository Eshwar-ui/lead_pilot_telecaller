import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_client.dart';
import 'package:lead_pilot_telecaller/src/services/session_store.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression cover for the "no server" screen work: LeadsController._load()
// used to fall back to mock leads on ANY fetch failure, with no way for
// HomeScreen to tell "the server is genuinely unreachable" apart from "that
// one fetch happened to fail". It now checks serverReachableProvider and
// skips the mock fallback specifically when the server is known to be
// unreachable, leaving the list empty so HomeScreen can show a dedicated
// "can't reach the server" screen instead of a fake-looking inbox.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'a genuinely unreachable server leaves the list empty instead of mock leads',
    () async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_FakeLoggedInSession.new),
          serverReachableProvider.overrideWith(_FakeUnreachable.new),
          apiClientProvider.overrideWith((ref) => _FailingApiClient()),
        ],
      );
      addTearDown(container.dispose);

      container.read(leadsProvider);
      await pumpEventQueue();

      expect(
        container.read(leadsProvider),
        isEmpty,
        reason:
            'nothing honest to show while the server is unreachable — '
            'HomeScreen renders the no-server screen for this, not a fake inbox',
      );
      expect(container.read(leadsUsingFallbackProvider), isFalse);
    },
  );

  test(
    'a one-off fetch failure while the server is reachable still falls back to mock leads',
    () async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_FakeLoggedInSession.new),
          // Default (unoverridden) serverReachableProvider starts `true`.
          apiClientProvider.overrideWith((ref) => _FailingApiClient()),
        ],
      );
      addTearDown(container.dispose);

      container.read(leadsProvider);
      await pumpEventQueue();

      expect(
        container.read(leadsProvider),
        isNotEmpty,
        reason:
            'guard against over-triggering: a transient/non-connectivity '
            'failure must keep the existing mock-fallback behavior',
      );
      expect(container.read(leadsUsingFallbackProvider), isTrue);
    },
  );
}

class _FakeLoggedInSession extends SessionController {
  @override
  Session build() => const Session(token: 'tok-123', userId: 'u1');
}

class _FakeUnreachable extends ServerReachabilityController {
  @override
  bool build() => false;
}

class _FailingApiClient implements ApiClient {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      throw Exception('boom');
  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => null;
  @override
  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => null;
  @override
  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => null;
  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => null;
}
