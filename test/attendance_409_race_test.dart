import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_client.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_endpoints.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_exception.dart';
import 'package:lead_pilot_telecaller/src/services/session_store.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';

// checkIn/checkOut/closePastShift all treat a 409 (another tap/device beat
// this one to the same action) as a harmless race: refresh state instead of
// surfacing a scary error, and explicitly reset actionInProgress afterward
// (the inline comments in providers.dart call out that _load()'s copyWith
// doesn't touch actionInProgress on its own, so skipping that explicit reset
// would leave the Check In/Out button stuck busy forever). None of this was
// under test before — attendance_provider_test.dart only checks build()
// doesn't throw.
void main() {
  Future<ProviderContainer> buildContainer(_FakeApiClient client) async {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWith((ref) => client),
        sessionProvider.overrideWith(_FakeLoggedInSession.new),
      ],
    );
    addTearDown(container.dispose);
    // build() schedules its own initial _load() as a microtask — let that
    // fully settle before the test proceeds, so it can't still be in flight
    // (and write to `state` after the container is disposed) once the test
    // body finishes and tears the container down.
    container.read(attendanceProvider);
    await pumpEventQueue();
    return container;
  }

  Map<String, dynamic> record({String? checkInAt, String? checkOutAt}) => {
    'id': 'r1',
    'date': '2026-08-20',
    if (checkInAt != null) 'check_in_at': checkInAt,
    if (checkOutAt != null) 'check_out_at': checkOutAt,
  };

  test(
    'checkIn 409 refreshes and clears actionInProgress instead of erroring',
    () async {
      final client = _FakeApiClient({
        ApiEndpoints.attendanceCheckIn: (_) =>
            throw const ApiException('conflict', statusCode: 409),
        ApiEndpoints.attendanceToday: (_) =>
            record(checkInAt: '2026-08-20T09:00:00Z'),
        ApiEndpoints.attendanceMine: (_) => {'records': []},
      });
      final container = await buildContainer(client);

      await container.read(attendanceProvider.notifier).checkIn();

      final state = container.read(attendanceProvider);
      expect(
        state.error,
        isNull,
        reason: '409 is a harmless race, not a user-facing error',
      );
      expect(
        state.actionInProgress,
        isFalse,
        reason: 'must not stay stuck busy after the 409 race path',
      );
      expect(
        state.record?.checkInAt,
        isNotNull,
        reason: 'should reflect the refreshed record',
      );
    },
  );

  test(
    'checkOut 409 refreshes and clears actionInProgress instead of erroring',
    () async {
      final client = _FakeApiClient({
        ApiEndpoints.attendanceCheckOut: (_) =>
            throw const ApiException('conflict', statusCode: 409),
        ApiEndpoints.attendanceToday: (_) => record(
          checkInAt: '2026-08-20T09:00:00Z',
          checkOutAt: '2026-08-20T18:00:00Z',
        ),
        ApiEndpoints.attendanceMine: (_) => {'records': []},
      });
      final container = await buildContainer(client);

      await container.read(attendanceProvider.notifier).checkOut();

      final state = container.read(attendanceProvider);
      expect(state.error, isNull);
      expect(state.actionInProgress, isFalse);
      expect(state.record?.checkOutAt, isNotNull);
    },
  );

  test(
    'checkOut 404 (no check-in yet) is a genuine error and is surfaced',
    () async {
      final client = _FakeApiClient({
        // build() itself fires an initial _load() via a microtask, independent
        // of the checkOut() call under test — needs its own handlers.
        ApiEndpoints.attendanceToday: (_) => record(),
        ApiEndpoints.attendanceMine: (_) => {'records': []},
        ApiEndpoints.attendanceCheckOut: (_) =>
            throw const ApiException('no check-in today', statusCode: 404),
      });
      final container = await buildContainer(client);

      await container.read(attendanceProvider.notifier).checkOut();

      final state = container.read(attendanceProvider);
      expect(state.error, 'no check-in today');
      expect(state.actionInProgress, isFalse);
    },
  );

  test(
    'closePastShift 409 (already closed) refreshes and clears actionInProgress',
    () async {
      final client = _FakeApiClient({
        ApiEndpoints.attendanceClose('r2'): (_) =>
            throw const ApiException('conflict', statusCode: 409),
        ApiEndpoints.attendanceToday: (_) =>
            record(checkInAt: '2026-08-20T09:00:00Z'),
        ApiEndpoints.attendanceMine: (_) => {'records': []},
      });
      final container = await buildContainer(client);

      await container.read(attendanceProvider.notifier).closePastShift('r2');

      final state = container.read(attendanceProvider);
      expect(state.error, isNull);
      expect(state.actionInProgress, isFalse);
    },
  );

  test(
    'a non-409 checkIn failure surfaces the error and clears actionInProgress',
    () async {
      final client = _FakeApiClient({
        // build()'s own initial _load() — see the comment in the 404 test above.
        ApiEndpoints.attendanceToday: (_) => record(),
        ApiEndpoints.attendanceMine: (_) => {'records': []},
        ApiEndpoints.attendanceCheckIn: (_) =>
            throw const ApiException('server error', statusCode: 500),
      });
      final container = await buildContainer(client);

      await container.read(attendanceProvider.notifier).checkIn();

      final state = container.read(attendanceProvider);
      expect(state.error, 'server error');
      expect(state.actionInProgress, isFalse);
    },
  );
}

/// Minimal fake — routes by path only (attendance calls carry no meaningful
/// body/query for these tests), throwing or returning per a per-path handler.
class _FakeApiClient implements ApiClient {
  _FakeApiClient(this._handlers);
  final Map<String, dynamic Function(String path)> _handlers;

  dynamic _handle(String path) {
    final handler = _handlers[path];
    if (handler == null) {
      throw StateError(
        'Unexpected call to $path — no handler registered for this test',
      );
    }
    return handler(path);
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _handle(path);
  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _handle(path);
  @override
  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _handle(path);
  @override
  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _handle(path);
  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _handle(path);
}

/// A session that's already "logged in" synchronously, so AttendanceController's
/// `isLoggedIn` guard doesn't skip the fetch and there's no real secure-storage
/// restore race to account for in these tests.
class _FakeLoggedInSession extends SessionController {
  @override
  Session build() => const Session(token: 'tok-123', userId: 'u1');
}
