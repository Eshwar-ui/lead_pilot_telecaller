// Regression cover for the "missing token" errors right after logout: a
// bunch of providers get invalidated as soon as the session token is
// cleared, and their build()/_load() methods used to fire an authenticated
// request anyway — which the backend correctly 401'd, but as a confusing
// raw error instead of the clean fail-soft path every caller already has.
// HttpApiClient now fails fast, locally, with no network call at all, for
// any path other than the two that don't need a token.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_exception.dart';
import 'package:lead_pilot_telecaller/src/core/api/http_api_client.dart';

void main() {
  group('HttpApiClient auth guard', () {
    test('a non-public path with no token throws locally, no network call made', () async {
      var called = false;
      final client = HttpApiClient(
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
        getToken: () => null,
      );

      await expectLater(
        client.get('/api/inbox'),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
      expect(called, isFalse, reason: 'must not hit the network at all');
    });

    test('login still works with no token (public path)', () async {
      final client = HttpApiClient(
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response('{"access_token":"t"}', 200,
              headers: {'content-type': 'application/json'});
        }),
        getToken: () => null,
      );

      final result = await client.post('/api/auth/login', body: {'email': 'a', 'password': 'b'});
      expect(result, {'access_token': 't'});
    });

    test('an authenticated request with a token attaches the bearer header', () async {
      final client = HttpApiClient(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer abc123');
          return http.Response('{"ok":true}', 200,
              headers: {'content-type': 'application/json'});
        }),
        getToken: () => 'abc123',
      );

      final result = await client.get('/api/inbox');
      expect(result, {'ok': true});
    });
  });

  // Regression cover for the force-logout hook added to providers.dart's
  // apiClientProvider (onUnauthorized: () => _forceLogout(ref, guard)) —
  // previously nothing exercised whether a 401 from the backend (as opposed
  // to the local "no token" short-circuit above) actually fires the
  // callback that triggers it.
  group('HttpApiClient onUnauthorized hook', () {
    test('fires on a 401 response when a token was sent', () async {
      var fired = 0;
      final client = HttpApiClient(
        client: MockClient((request) async => http.Response('{"detail":"expired"}', 401,
            headers: {'content-type': 'application/json'})),
        getToken: () => 'stale-token',
        onUnauthorized: () => fired++,
      );

      await expectLater(client.get('/api/inbox'), throwsA(isA<ApiException>()));
      expect(fired, 1);
    });

    test('does not fire on a 403 (forbidden is not an expired-session signal)', () async {
      var fired = 0;
      final client = HttpApiClient(
        client: MockClient((request) async => http.Response('{"detail":"forbidden"}', 403,
            headers: {'content-type': 'application/json'})),
        getToken: () => 'valid-token',
        onUnauthorized: () => fired++,
      );

      await expectLater(client.get('/api/inbox'), throwsA(isA<ApiException>()));
      expect(fired, 0);
    });

    test('does not fire on a 401 with no token (the local short-circuit above, not a real 401)',
        () async {
      var fired = 0;
      var networkCalled = false;
      final client = HttpApiClient(
        client: MockClient((request) async {
          networkCalled = true;
          return http.Response('{}', 401);
        }),
        getToken: () => null,
        onUnauthorized: () => fired++,
      );

      await expectLater(client.get('/api/inbox'), throwsA(isA<ApiException>()));
      expect(networkCalled, isFalse);
      expect(fired, 0, reason: 'no session was ever active, so there is nothing to force-logout');
    });
  });
}
