// Covers the backfill sweep that picks up calls the telecaller made or took
// OUTSIDE the app (native dialer, inbound), plus the phone→lead matching that
// gates it.
//
// The gate is the part worth guarding hardest: `/api/calls/upload` CREATES a
// lead for whatever number it's handed, so a sweep that captured non-lead
// calls would turn every personal call on the telecaller's phone into a lead
// with a recording and an AI analysis attached.
//
// Like capture_telemetry_test.dart, these run with the target platform forced
// to iOS so `captureLatest` short-circuits at "unsupported" instead of
// reaching real Android dialer folders — which still proves exactly what this
// sweep decides, since a capture attempt is observable through the telemetry
// it reports and the per-lead state it writes.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_client.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_exception.dart';
import 'package:lead_pilot_telecaller/src/data/lead_repository.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/call_detection_bridge.dart';
import 'package:lead_pilot_telecaller/src/services/capture_telemetry_service.dart';
import 'package:lead_pilot_telecaller/src/services/lead_call_matcher.dart';
import 'package:lead_pilot_telecaller/src/services/local_call_store.dart';
import 'package:lead_pilot_telecaller/src/state/call_capture.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';

Lead _lead({required String id, required String phone, String name = 'Priya'}) =>
    Lead(
      id: id,
      name: name,
      phone: phone,
      score: 0,
      temperature: LeadTemperature.warm,
      source: LeadSource.meta,
      intent: '',
      lastContact: DateTime(2026, 9, 1),
      totalCalls: 0,
      averageScore: 0,
      memory: const [],
      script: const AiScript(
        generatedAgo: '',
        openingLine: '',
        keyPoints: [],
        steps: [],
      ),
      objections: const [],
      checklist: const [],
      history: const [],
    );

CallLogEntry _deviceCall({
  required String deviceCallId,
  required String phone,
  DateTime? at,
  Duration duration = const Duration(minutes: 3),
  String? callId,
  String? leadId,
}) => CallLogEntry(
  id: deviceCallId,
  leadName: '',
  phone: phone,
  intent: '',
  source: LeadSource.organic,
  duration: duration,
  score: 0,
  calledAt: at ?? DateTime.now().subtract(const Duration(hours: 2)),
  deviceCallId: deviceCallId,
  callId: callId,
  leadId: leadId,
);

void main() {
  group('LeadCallMatcher.matchInLeads', () {
    final leads = [
      _lead(id: 'lead-priya', phone: '+91 98765 43210'),
      _lead(id: 'lead-ravi', phone: '9000000001', name: 'Ravi'),
    ];

    test('matches regardless of how either side formatted the number', () {
      expect(
        LeadCallMatcher.matchInLeads(leads, '9876543210'),
        'lead-priya',
        reason: 'the dialer reports digits; the lead was saved with +91 and spaces',
      );
      expect(LeadCallMatcher.matchInLeads(leads, '+919000000001'), 'lead-ravi');
    });

    test('returns null for a number that is not a lead', () {
      expect(LeadCallMatcher.matchInLeads(leads, '9111111111'), isNull);
    });

    test('never matches a short number', () {
      // Service/short codes have no business colliding with each other, and a
      // false match here would attach a stranger's recording to a real lead.
      final shortCodeLeads = [_lead(id: 'lead-short', phone: '12345')];
      expect(LeadCallMatcher.matchInLeads(shortCodeLeads, '12345'), isNull);
    });
  });

  group('CallCaptureController.sweepBackfill', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    ProviderContainer buildContainer({
      required List<CallLogEntry> calls,
      required List<Lead> leads,
      required CaptureTelemetryService telemetry,
    }) {
      final container = ProviderContainer(
        overrides: [
          captureTelemetryServiceProvider.overrideWithValue(telemetry),
          leadsProvider.overrideWith(() => _FixedLeadsController(leads)),
          localCallsProvider.overrideWith(() => _FixedLocalCalls(calls)),
          // Every number that isn't in the local lead list falls through to the
          // backend dedupe check; here it always answers "not a lead".
          leadRepositoryProvider.overrideWithValue(_NoMatchLeadRepository()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('captures a call placed outside the app to a lead number', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [_deviceCall(deviceCallId: 'dev-1', phone: '+919876543210')],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).sweepBackfill();

      expect(telemetry.reported, ['unsupported']);
      expect(
        telemetry.sources,
        ['auto_detect_backfill'],
        reason: 'a backfilled call must not be counted in the app-placed '
            '"auto" success rate — its failure modes are different',
      );
      expect(
        container.read(callCaptureProvider.notifier).stateFor('lead-priya').status,
        CaptureStatus.unsupported,
      );
    });

    test('ignores a call to a number that is not a lead', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [_deviceCall(deviceCallId: 'dev-personal', phone: '+919111111111')],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).sweepBackfill();

      expect(
        telemetry.reported,
        isEmpty,
        reason: 'uploading a non-lead call would create a lead out of a '
            "telecaller's personal call",
      );
    });

    test('ignores a missed call — there is no recording to find', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [
          _deviceCall(
            deviceCallId: 'dev-missed',
            phone: '9876543210',
            duration: Duration.zero,
          ),
        ],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).sweepBackfill();

      expect(telemetry.reported, isEmpty);
    });

    test('ignores a call older than the backfill window', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [
          _deviceCall(
            deviceCallId: 'dev-old',
            phone: '9876543210',
            at: DateTime.now().subtract(const Duration(days: 3)),
          ),
        ],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).sweepBackfill();

      expect(telemetry.reported, isEmpty);
    });

    test('ignores a call that already has a backend call id', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [
          _deviceCall(
            deviceCallId: 'dev-done',
            phone: '9876543210',
            callId: 'call-abc',
          ),
        ],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).sweepBackfill();

      expect(telemetry.reported, isEmpty);
    });

    test('ignores an app-placed entry with no device call-log id', () async {
      // PostCallScreen already owns that call; sweeping it too would race the
      // screen's own capture for the same recording.
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [
          CallLogEntry(
            id: 'local-1',
            leadName: 'Priya',
            phone: '9876543210',
            intent: '',
            source: LeadSource.organic,
            duration: const Duration(minutes: 2),
            score: 0,
            calledAt: DateTime.now().subtract(const Duration(minutes: 20)),
            leadId: 'lead-priya',
          ),
        ],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).sweepBackfill();

      expect(telemetry.reported, isEmpty);
    });

    test('a second sweep does not re-attempt the same call', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [_deviceCall(deviceCallId: 'dev-1', phone: '9876543210')],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      final notifier = container.read(callCaptureProvider.notifier);
      await notifier.sweepBackfill();
      await notifier.sweepBackfill();

      expect(telemetry.reported, ['unsupported']);
    });

    test('a detected call to a lead is captured as a realtime detection', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: const [],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).handleDetectedCall(
        DetectedCall(
          number: '+91 98765 43210',
          isInbound: true,
          durationSeconds: 95,
          endedAt: DateTime.now(),
        ),
      );

      expect(telemetry.reported, ['unsupported']);
      expect(telemetry.sources, ['auto_detect_realtime']);
    });

    test('a detected call from a stranger is ignored', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: const [],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).handleDetectedCall(
        DetectedCall(
          number: '9111111111',
          isInbound: true,
          durationSeconds: 95,
          endedAt: DateTime.now(),
        ),
      );

      expect(telemetry.reported, isEmpty);
    });

    test('a zero-duration detection is left to the backfill sweep', () async {
      // Either the call was never answered (no recording exists) or the call
      // log couldn't be read — neither is worth a scan right now.
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: const [],
        leads: [_lead(id: 'lead-priya', phone: '9876543210')],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).handleDetectedCall(
        DetectedCall(
          number: '9876543210',
          isInbound: false,
          durationSeconds: 0,
          endedAt: DateTime.now(),
        ),
      );

      expect(telemetry.reported, isEmpty);
    });

    test('handles several leads in one sweep', () async {
      final telemetry = _FakeCaptureTelemetryService();
      final container = buildContainer(
        calls: [
          _deviceCall(deviceCallId: 'dev-1', phone: '9876543210'),
          _deviceCall(deviceCallId: 'dev-2', phone: '9000000001'),
          _deviceCall(deviceCallId: 'dev-3', phone: '9111111111'),
        ],
        leads: [
          _lead(id: 'lead-priya', phone: '9876543210'),
          _lead(id: 'lead-ravi', phone: '9000000001', name: 'Ravi'),
        ],
        telemetry: telemetry,
      );

      await container.read(callCaptureProvider.notifier).sweepBackfill();

      expect(telemetry.reported, hasLength(2));
      final notifier = container.read(callCaptureProvider.notifier);
      expect(notifier.stateFor('lead-priya').status, CaptureStatus.unsupported);
      expect(notifier.stateFor('lead-ravi').status, CaptureStatus.unsupported);
    });
  });
}

class _FixedLeadsController extends LeadsController {
  _FixedLeadsController(this._leads);
  final List<Lead> _leads;

  @override
  List<Lead> build() => _leads;
}

class _FixedLocalCalls extends LocalCallsController {
  _FixedLocalCalls(this._calls);
  final List<CallLogEntry> _calls;

  @override
  List<CallLogEntry> build() => _calls;
}

class _NoMatchLeadRepository extends LeadRepository {
  _NoMatchLeadRepository() : super(_UnusedApiClient());

  @override
  Future<DedupeResult> dedupe(String phone) async =>
      const DedupeResult(duplicate: false);
}

class _FakeCaptureTelemetryService extends CaptureTelemetryService {
  final List<String> reported = [];
  final List<String> sources = [];

  @override
  Future<void> report(
    String outcome, {
    String? accessLevel,
    String source = 'auto',
    Map<String, dynamic>? details,
  }) async {
    reported.add(outcome);
    sources.add(source);
  }
}

class _UnusedApiClient implements ApiClient {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      throw const ApiException('not used in this test');

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw const ApiException('not used in this test');

  @override
  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw const ApiException('not used in this test');

  @override
  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw const ApiException('not used in this test');

  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => throw const ApiException('not used in this test');
}
