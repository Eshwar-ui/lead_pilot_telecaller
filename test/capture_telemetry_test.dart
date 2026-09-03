import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_client.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_exception.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/capture_telemetry_service.dart';
import 'package:lead_pilot_telecaller/src/state/call_capture.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';

void main() {
  group('CaptureTelemetryService', () {
    test('skips the report entirely when logged out (no token)', () async {
      final client = _RecordingApiClient();
      final service = CaptureTelemetryService(
        getToken: () => null,
        client: client,
      );

      await service.report('not_found');

      expect(client.posts, isEmpty);
    });

    test('posts the outcome and device fields to the capture-attempt endpoint', () async {
      final client = _RecordingApiClient();
      final service = CaptureTelemetryService(
        getToken: () => 'jwt-123',
        client: client,
      );

      await service.report('found');

      expect(client.posts, hasLength(1));
      expect(client.posts.single.path, '/api/telemetry/capture-attempt');
      // Running on the `flutter test` host (not Android), device fields are
      // omitted rather than sent as fabricated values — see
      // CaptureTelemetryService._deviceDetails.
      expect(client.posts.single.body, {'outcome': 'found'});
    });

    test('retries once on failure, then gives up silently without throwing', () async {
      final client = _ThrowingApiClient();
      final service = CaptureTelemetryService(
        getToken: () => 'jwt-123',
        client: client,
      );

      await service.report('error');

      expect(client.attempts, 2, reason: 'one retry after the first failure');
    });

    test('an automatic report keeps the body shape it always had', () async {
      // Phase-0 fields are additive: an unchanged automatic attempt must not
      // start sending `source: auto` or empty keys, or every existing row's
      // shape changes for nothing.
      final client = _RecordingApiClient();
      final service = CaptureTelemetryService(
        getToken: () => 'jwt-123',
        client: client,
      );

      await service.report('not_found');

      expect(client.posts.single.body, {'outcome': 'not_found'});
    });

    test('carries the access level so a failure can be interpreted', () async {
      // "not_found" with all-files access and "not_found" with audio-only
      // access are different failures with different fixes; the aggregate
      // cannot separate them without this.
      final client = _RecordingApiClient();
      final service = CaptureTelemetryService(
        getToken: () => 'jwt-123',
        client: client,
      );

      await service.report('not_found', accessLevel: 'media_audio');

      expect(
        (client.posts.single.body as Map)['access_level'],
        'media_audio',
      );
    });

    test('a hand-run check is tagged diagnostic and carries its snapshot', () async {
      final client = _RecordingApiClient();
      final service = CaptureTelemetryService(
        getToken: () => 'jwt-123',
        client: client,
      );

      await service.report(
        'not_found',
        accessLevel: 'media_audio',
        source: 'diagnostic',
        details: {'dirs_existing': 2, 'dirs_readable': 0},
      );

      final body = client.posts.single.body as Map;
      expect(body['source'], 'diagnostic');
      expect(body['details'], {'dirs_existing': 2, 'dirs_readable': 0});
    });

    test('a single success does not trigger a retry', () async {
      final client = _RecordingApiClient();
      final service = CaptureTelemetryService(
        getToken: () => 'jwt-123',
        client: client,
      );

      await service.report('permission_denied');

      expect(client.posts, hasLength(1));
    });
  });

  group('CallCaptureController wiring', () {
    // captureLatest itself can't be driven all the way to `found`/`notFound`
    // in a unit test (that requires real Android dialer folders — see
    // call_recording_phone_match_test.dart's doc comment), but the
    // platform-unsupported branch is fully reachable by forcing the target
    // platform to iOS (real behaviour: "iOS has no call auto-recording and
    // is always unsupported", per CallRecordingService's own doc), and it
    // shares the exact same reporting call site pattern as every other
    // terminal outcome in captureLatest.
    //
    // `flutter test` defaults `defaultTargetPlatform` to android (Flutter
    // sets this under FLUTTER_TEST for cross-host consistency), so without
    // this override CallRecordingService.ensureStoragePermission would try
    // to reach the real permission_handler platform channel instead of
    // taking the unsupported short-circuit.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    ProviderContainer buildContainer(CaptureTelemetryService telemetry) {
      final container = ProviderContainer(
        overrides: [
          captureTelemetryServiceProvider.overrideWithValue(telemetry),
          leadsProvider.overrideWith(_NoopLeadsController.new),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'captureLatest reports the "unsupported" outcome exactly once off-Android',
      () async {
        final telemetry = _FakeCaptureTelemetryService();
        final container = buildContainer(telemetry);

        await container
            .read(callCaptureProvider.notifier)
            .captureLatest('lead1');

        expect(telemetry.reported, ['unsupported']);
      },
    );

    test(
      'repeat attempts within one capture episode report only once',
      () async {
        // One ended call runs the scan up to four times on a backoff ladder
        // (PostCallScreen._captureWithRetries) and again on every app resume.
        // Reporting each attempt put 15 identical `not_found` rows in the table
        // in one minute on a real device — which does not enrich the
        // denominator, it inflates the failure count of precisely the phones
        // that fail, biasing the rate capture-stats exists to measure.
        final telemetry = _FakeCaptureTelemetryService();
        final container = buildContainer(telemetry);

        final notifier = container.read(callCaptureProvider.notifier);
        await notifier.captureLatest('lead1');
        await notifier.captureLatest('lead1');
        await notifier.captureLatest('lead1');

        expect(telemetry.reported, ['unsupported']);
      },
    );

    test('a new call reports again — the episode is the unit, not the app run', () async {
      // The denominator must still count real calls. resetForNewCall is the
      // episode boundary, so the next call is a fresh attempt to be counted.
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(telemetry);

      final notifier = container.read(callCaptureProvider.notifier);
      await notifier.captureLatest('lead1');
      notifier.resetForNewCall('lead1');
      await notifier.captureLatest('lead1');

      expect(telemetry.reported, ['unsupported', 'unsupported']);
    });

    test('each lead is counted separately', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(telemetry);

      final notifier = container.read(callCaptureProvider.notifier);
      await notifier.captureLatest('lead1');
      await notifier.captureLatest('lead2');

      expect(telemetry.reported, ['unsupported', 'unsupported']);
    });

    test(
      'a telemetry backend failure never surfaces in the capture state',
      () async {
        // Uses the REAL CaptureTelemetryService (not a fake that violates its
        // own no-throw contract) wired to a client that always throws, so
        // this exercises the actual fail-soft path end to end.
        final realService = CaptureTelemetryService(
          getToken: () => 'jwt-123',
          client: _ThrowingApiClient(),
        );
        final container = buildContainer(realService);

        await container
            .read(callCaptureProvider.notifier)
            .captureLatest('lead1');

        final state = container
            .read(callCaptureProvider.notifier)
            .stateFor('lead1');
        // The capture flow's own status must reflect the real capture
        // outcome (unsupported off-Android), unaffected by the telemetry
        // POST failing.
        expect(state.status, CaptureStatus.unsupported);
      },
    );
  });
}

class _NoopLeadsController extends LeadsController {
  @override
  List<Lead> build() => const [];
}

class _FakeCaptureTelemetryService extends CaptureTelemetryService {
  final List<String> reported = [];
  final List<String?> reportedAccessLevels = [];

  @override
  Future<void> report(
    String outcome, {
    String? accessLevel,
    String source = 'auto',
    Map<String, dynamic>? details,
  }) async {
    reported.add(outcome);
    reportedAccessLevels.add(accessLevel);
  }
}

class _PostCall {
  const _PostCall(this.path, this.body);
  final String path;
  final Object? body;
}

class _RecordingApiClient implements ApiClient {
  final List<_PostCall> posts = [];

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    posts.add(_PostCall(path, body));
    return null;
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      throw UnimplementedError();

  @override
  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw UnimplementedError();

  @override
  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw UnimplementedError();

  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw UnimplementedError();
}

class _ThrowingApiClient implements ApiClient {
  int attempts = 0;

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    attempts++;
    throw const ApiException('backend unreachable');
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      throw UnimplementedError();

  @override
  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw UnimplementedError();

  @override
  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw UnimplementedError();

  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw UnimplementedError();
}
