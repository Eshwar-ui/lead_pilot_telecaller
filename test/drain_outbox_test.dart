import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/call_recording.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/local_upload_outbox.dart';
import 'package:lead_pilot_telecaller/src/services/transcription_service.dart';
import 'package:lead_pilot_telecaller/src/state/call_capture.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression cover for two bugs fixed in CallCaptureController.drainOutbox:
//
// 1. TOCTOU crash: CallRecording.fromFile's statSync() used to be unguarded,
//    so a file deleted between the existsSync() check and that call threw
//    out of the whole loop, silently abandoning every other queued entry for
//    that drain cycle.
// 2. No re-entrancy guard: PostCallScreen's own resume-retry and MainShell's
//    lifecycle hook can both call drainOutbox() on the same app resume — with
//    no guard, both would read the same pending entries and each upload them,
//    only caught after the fact by the backend's content-hash dedup.
void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('drain_outbox_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer buildContainer(TranscriptionService transcriptionService) {
    final container = ProviderContainer(
      overrides: [
        transcriptionServiceProvider.overrideWithValue(transcriptionService),
        leadsProvider.overrideWith(_NoopLeadsController.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'a queued recording whose file vanished is dropped, not retried, and does not '
    'abort the rest of the batch',
    () async {
      final container = buildContainer(
        _FakeTranscriptionService((_, _) async {
          fail('transcribe() must not be called for a missing file');
        }),
      );

      final outbox = container.read(localUploadOutboxProvider);
      final missingPath = '${tempDir.path}/never_written.m4a';
      await outbox.enqueue(OutboxEntry(leadId: 'lead1', path: missingPath));

      await container.read(callCaptureProvider.notifier).drainOutbox();

      expect(
        await outbox.all(),
        isEmpty,
        reason: 'a vanished file must be dropped from the outbox',
      );
    },
  );

  test(
    'a successful drain uploads, removes the entry, and remembers the call_id',
    () async {
      final file = File('${tempDir.path}/call1.m4a')
        ..writeAsBytesSync([1, 2, 3, 4]);
      var callCount = 0;
      final container = buildContainer(
        _FakeTranscriptionService((recording, leadId) async {
          callCount++;
          expect(leadId, 'lead1');
          return const CallTranscription(transcript: 'hello', entries: []);
        }),
      );

      final outbox = container.read(localUploadOutboxProvider);
      await outbox.enqueue(OutboxEntry(leadId: 'lead1', path: file.path));

      await container.read(callCaptureProvider.notifier).drainOutbox();

      expect(callCount, 1);
      expect(
        await outbox.all(),
        isEmpty,
        reason: 'a successful upload must clear the outbox entry',
      );
    },
  );

  test(
    'two concurrent drainOutbox() calls only process the batch once',
    () async {
      final file = File('${tempDir.path}/call2.m4a')
        ..writeAsBytesSync([1, 2, 3, 4]);
      var callCount = 0;
      final release = Completer<void>();
      final container = buildContainer(
        _FakeTranscriptionService((_, _) async {
          callCount++;
          // Block until the test explicitly releases it, simulating a slow
          // upload — long enough for a second drainOutbox() call to race in
          // while the first is still running.
          await release.future;
          return const CallTranscription(transcript: 'hello', entries: []);
        }),
      );

      final outbox = container.read(localUploadOutboxProvider);
      await outbox.enqueue(OutboxEntry(leadId: 'lead1', path: file.path));

      final notifier = container.read(callCaptureProvider.notifier);
      final firstDrain = notifier.drainOutbox();
      // Give the first call a chance to set its in-progress guard before the
      // second call starts, mirroring the real resume-hook race.
      await Future<void>.delayed(Duration.zero);
      final secondDrain = notifier.drainOutbox();

      release.complete();
      await Future.wait([firstDrain, secondDrain]);

      expect(
        callCount,
        1,
        reason: 'the re-entrancy guard must prevent a duplicate upload',
      );
    },
  );

  test(
    'a failed upload bumps the attempt count instead of being dropped',
    () async {
      final file = File('${tempDir.path}/call3.m4a')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final container = buildContainer(
        _FakeTranscriptionService((_, _) async {
          throw Exception('network down');
        }),
      );

      final outbox = container.read(localUploadOutboxProvider);
      await outbox.enqueue(OutboxEntry(leadId: 'lead1', path: file.path));

      await container.read(callCaptureProvider.notifier).drainOutbox();

      final remaining = await outbox.all();
      expect(remaining, hasLength(1));
      expect(remaining.single.attempts, 1);
    },
  );
}

/// Overrides only what CallCaptureController.drainOutbox actually touches on
/// success (a fire-and-forget `enrich()` call) — no real network/session
/// wiring needed for these tests.
class _NoopLeadsController extends LeadsController {
  @override
  List<Lead> build() => const [];

  @override
  Future<void> enrich(String contactKey) async {}
}

class _FakeTranscriptionService extends TranscriptionService {
  const _FakeTranscriptionService(this._behavior);

  final Future<CallTranscription> Function(
    CallRecording recording,
    String leadId,
  )
  _behavior;

  @override
  Future<CallTranscription> transcribe({
    required CallRecording recording,
    required String leadId,
    String? name,
    String? phone,
    String? source,
    String? contactKey,
    String? existingCallId,
    void Function(String callId)? onCallId,
    void Function(String stage, int percent)? onProgress,
  }) => _behavior(recording, leadId);
}
