import 'dart:async' show unawaited;
import 'dart:io' show File;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/call_recording.dart';
import '../models/lead.dart';
import '../services/call_detection_bridge.dart';
import '../services/call_recording_service.dart';
import '../services/capture_telemetry_service.dart';
import '../services/lead_call_matcher.dart';
import '../services/local_call_store.dart';
import '../services/local_transcript_store.dart';
import '../services/local_upload_ledger.dart';
import '../services/local_upload_outbox.dart';
import '../services/session_store.dart';
import '../services/transcription_service.dart';
import 'providers.dart';

/// Where a given lead's call recording is in the capture → transcribe flow.
enum CaptureStatus {
  idle,

  /// Looking for / requesting the storage permission.
  checkingPermission,

  /// Permission denied; can prompt again.
  permissionDenied,

  /// Permission permanently denied; must go to Settings.
  permissionBlocked,

  /// Scanning the dialer folders.
  scanning,

  /// A recording file was located on the device.
  found,

  /// Scan finished but no recent recording was found.
  notFound,

  /// Not supported on this platform (iOS / web).
  unsupported,

  /// Uploading the file to the backend for speech-to-text.
  transcribing,

  /// Transcript received.
  transcribed,

  /// Something failed (scan or transcription).
  error,
}

/// How a recording reached the app. Sent to `/api/calls/upload` as
/// `capture_source` and stored on the call, so a call that appeared without
/// the telecaller ever opening the app can be explained afterwards.
abstract final class CaptureSource {
  /// The telecaller tapped Call in the app and came back to PostCallScreen.
  static const appCall = 'app_call';

  /// A call detected as it ended, placed or received outside the app.
  static const autoDetectedRealtime = 'auto_detected_realtime';

  /// A call found later by sweeping the phone's own call log — the app wasn't
  /// running when it ended.
  static const autoDetectedBackfill = 'auto_detected_backfill';

  /// The capture-telemetry `source` for a given capture source. Auto-detected
  /// calls are reported under their own labels so their success rate (a call
  /// log entry whose recording is long gone is normal here, and not in the
  /// app-placed flow) doesn't distort `/api/telemetry/capture-stats`, which
  /// counts `source="auto"` only.
  static String telemetryLabel(String captureSource) => switch (captureSource) {
    autoDetectedRealtime => 'auto_detect_realtime',
    autoDetectedBackfill => 'auto_detect_backfill',
    _ => 'auto',
  };
}

/// Immutable per-lead capture state held in the [callCaptureProvider] map.
class CallCaptureState {
  const CallCaptureState({
    this.status = CaptureStatus.idle,
    this.recording,
    this.transcription,
    this.message,
    this.processingLabel,
    this.processingPercent,
    this.reportedOutcome,
  });

  final CaptureStatus status;
  final CallRecording? recording;
  final CallTranscription? transcription;

  /// The capture-telemetry outcome already reported for THIS capture episode,
  /// so the retry ladder doesn't report the same result over and over.
  ///
  /// Cleared by [CallCaptureController.resetForNewCall], which is exactly the
  /// episode boundary: one real call in, one outcome out.
  final String? reportedOutcome;

  /// User-facing detail for [CaptureStatus.error]/permission states.
  final String? message;

  /// Live backend stage label shown during [CaptureStatus.transcribing],
  /// e.g. "Uploading…", "Speech to text…", "Analysing…".
  final String? processingLabel;

  /// Backend processing progress 0–100, updated each polling tick.
  final int? processingPercent;

  bool get isBusy =>
      status == CaptureStatus.checkingPermission ||
      status == CaptureStatus.scanning ||
      status == CaptureStatus.transcribing;

  bool get hasRecording => recording != null;

  CallCaptureState copyWith({
    CaptureStatus? status,
    CallRecording? recording,
    CallTranscription? transcription,
    String? message,
    String? processingLabel,
    int? processingPercent,
    String? reportedOutcome,
  }) {
    return CallCaptureState(
      status: status ?? this.status,
      recording: recording ?? this.recording,
      transcription: transcription ?? this.transcription,
      message: message,
      processingLabel: processingLabel ?? this.processingLabel,
      processingPercent: processingPercent ?? this.processingPercent,
      // Carried forward, unlike `message`: it must survive every state change
      // within an episode or the dedupe below forgets what it already sent.
      reportedOutcome: reportedOutcome ?? this.reportedOutcome,
    );
  }
}

final callRecordingServiceProvider = Provider<CallRecordingService>(
  (ref) => const CallRecordingService(),
);

final transcriptionServiceProvider = Provider<TranscriptionService>(
  (ref) =>
      TranscriptionService(getToken: () => ref.read(sessionProvider).token),
);

/// Fire-and-forget capture-attempt telemetry (see class doc) — overridable in
/// tests so `captureLatest`'s reporting can be verified without a real
/// backend/device.
final captureTelemetryServiceProvider = Provider<CaptureTelemetryService>(
  (ref) => CaptureTelemetryService(
    getToken: () => ref.read(sessionProvider).token,
  ),
);

/// Drives capturing the dialer's recording and turning it into a transcript,
/// keyed by lead id (mirrors [CallNotesController]'s `Notifier<Map<...>>`).
final callCaptureProvider =
    NotifierProvider<CallCaptureController, Map<String, CallCaptureState>>(
      CallCaptureController.new,
    );

class CallCaptureController extends Notifier<Map<String, CallCaptureState>> {
  @override
  Map<String, CallCaptureState> build() => {};

  CallCaptureState stateFor(String leadId) =>
      state[leadId] ?? const CallCaptureState();

  void _set(String leadId, CallCaptureState value) {
    state = {...state, leadId: value};
  }

  /// Clears this lead's capture state so a fresh recording can be found for a
  /// new call. No-ops while transcription is already in flight.
  void resetForNewCall(String leadId) {
    if (stateFor(leadId).isBusy) return;
    _set(leadId, const CallCaptureState());
  }

  /// Loads the last-saved transcript from device storage and populates the
  /// state as [CaptureStatus.transcribed]. Call on PostCallScreen open when
  /// it's NOT a new call (i.e. reviewing a previous call).
  Future<void> restoreSaved(String leadId) async {
    final existing = stateFor(leadId);
    if (existing.isBusy ||
        existing.hasRecording ||
        existing.status == CaptureStatus.transcribed) {
      return;
    }

    final saved = await ref.read(localTranscriptStoreProvider).load(leadId);
    if (saved == null) return;

    _set(
      leadId,
      CallCaptureState(status: CaptureStatus.transcribed, transcription: saved),
    );
  }

  /// Finds the recording the dialer saved for the call that just ended and
  /// stores it against [leadId]. Safe to call repeatedly (e.g. on resume).
  ///
  /// [manual] marks an explicit user-initiated call (the "Retry" button),
  /// as opposed to the automatic scan right after a call ends. The automatic
  /// scan is deliberately bounded to a 30-minute-old file so it can't grab an
  /// unrelated old recording — but that same bound made a manual retry
  /// permanently unable to find a real recording once 30 minutes had passed
  /// (e.g. while the user was troubleshooting permissions), no matter how
  /// many times they tapped it. A manual retry searches with no recency
  /// limit instead, matching findLatestRecording's own documented intent
  /// for "a manual 'pick the latest recording' action".
  ///
  /// [captureSource] labels how this call reached the app — see
  /// [CaptureSource]. It rides through to the upload so a call the telecaller
  /// never placed from here is distinguishable afterwards.
  Future<void> captureLatest(
    String leadId, {
    bool manual = false,
    String captureSource = CaptureSource.appCall,
  }) async {
    final service = ref.read(callRecordingServiceProvider);
    final existing = stateFor(leadId);
    final telemetrySource = CaptureSource.telemetryLabel(captureSource);

    // Skip if busy, already have a recording, or already transcribed.
    if (existing.isBusy ||
        existing.hasRecording ||
        existing.status == CaptureStatus.transcribed) {
      return;
    }

    _set(leadId, existing.copyWith(status: CaptureStatus.checkingPermission));

    final permission = await service.ensureStoragePermission();
    final accessLevel = permission.level.wireName;
    switch (permission.result) {
      case StoragePermissionResult.unsupported:
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.unsupported,
            message: 'Call recording capture is available on Android only.',
          ),
        );
        unawaited(_reportCaptureTelemetry(leadId, 'unsupported', accessLevel, telemetrySource));
        return;
      case StoragePermissionResult.denied:
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.permissionDenied,
            message:
                'Allow access to music and audio so the recording can be read.',
          ),
        );
        unawaited(_reportCaptureTelemetry(leadId, 'permission_denied', accessLevel, telemetrySource));
        return;
      case StoragePermissionResult.permanentlyDenied:
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.permissionBlocked,
            // Names the permission the user can actually grant. The old copy
            // sent them to "All files access", which Android 13+ greys out for
            // apps installed outside the Play Store — a dead end that looked
            // like the telecaller's fault.
            message:
                'Open Settings → Permissions and allow "Music and audio" for '
                'LeadPilot.',
          ),
        );
        unawaited(_reportCaptureTelemetry(leadId, 'permission_blocked', accessLevel, telemetrySource));
        return;
      case StoragePermissionResult.granted:
        break;
    }

    _set(leadId, existing.copyWith(status: CaptureStatus.scanning));

    // Pass the lead's phone so the scanner prefers the recording whose filename
    // contains that number (OEM dialers embed it) instead of just the newest
    // file — the single biggest cause of a call attaching to the wrong lead.
    final leads = ref.read(leadsProvider);
    final matches = leads.where((l) => l.id == leadId);
    final phoneHint = matches.isEmpty ? null : matches.first.phone;

    try {
      final recording = await service.findLatestRecording(
        phoneHint: phoneHint,
        within: manual ? null : const Duration(minutes: 30),
      );
      if (recording == null) {
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.notFound,
            message:
                'No recent recording found. Check that call recording is on '
                'in your Phone app, or run the Recording Check in Profile.',
          ),
        );
        unawaited(_reportCaptureTelemetry(leadId, 'not_found', accessLevel, telemetrySource));
        return;
      }
      _set(
        leadId,
        existing.copyWith(status: CaptureStatus.found, recording: recording),
      );
      unawaited(_reportCaptureTelemetry(leadId, 'found', accessLevel, telemetrySource));
      // A recording exists → a real call happened. Log it to My Calls now (real
      // evidence, unlike merely opening the dialer). It later merges with the
      // transcribed backend entry for the same call once the lead is enriched.
      final loggedLead = matches.isEmpty ? null : matches.first;
      unawaited(
        ref
            .read(localCallsProvider.notifier)
            .record(
              CallLogEntry(
                id: '${leadId}_${recording.recordedAt.millisecondsSinceEpoch}',
                leadName: loggedLead?.name ?? '',
                phone: loggedLead?.phone ?? '',
                intent: loggedLead?.intent ?? '',
                source: loggedLead?.source ?? LeadSource.organic,
                duration: Duration.zero,
                score: loggedLead?.score ?? 0,
                calledAt: recording.recordedAt,
                leadId: leadId,
              ),
            ),
      );
      // Auto-start transcription immediately — no manual tap required.
      unawaited(transcribe(leadId, captureSource: captureSource));
    } catch (e) {
      _set(
        leadId,
        existing.copyWith(status: CaptureStatus.error, message: '$e'),
      );
      unawaited(_reportCaptureTelemetry(leadId, 'error', accessLevel, telemetrySource));
    }
  }

  /// Handles a call that just ended on this phone, whoever placed it.
  ///
  /// Silent by design: if the number belongs to a lead, the recording is
  /// captured, uploaded and analysed in the background and simply turns up in
  /// that lead's history. Nothing navigates and nothing interrupts — the
  /// telecaller may not even have had the app open when the call happened.
  Future<void> handleDetectedCall(DetectedCall call) async {
    // durationSeconds == 0 covers both a missed/unanswered call (no recording
    // exists) and the fallback path where the call log couldn't be read; in
    // neither case is there anything to find right now, and the backfill sweep
    // re-examines the call log later with real duration data.
    if (call.durationSeconds <= 0) return;

    final leadId = await ref.read(leadCallMatcherProvider).matchLeadId(
      call.number,
    );
    // Not a lead — leave it alone. Uploading it would create one.
    if (leadId == null) return;

    final existing = stateFor(leadId);
    if (existing.isBusy) return;
    if (existing.hasRecording ||
        existing.status == CaptureStatus.transcribed) {
      // A previous call to this lead is still parked in state; without this the
      // guard inside captureLatest would silently drop the call that just
      // ended.
      resetForNewCall(leadId);
    }

    await captureLatest(
      leadId,
      captureSource: CaptureSource.autoDetectedRealtime,
    );
  }

  /// How far back a backfill sweep looks. A day covers "I called them
  /// yesterday evening and only opened the app this morning" without
  /// re-examining weeks of history on every launch — and OEM dialers rotate
  /// their recording folders long before that anyway.
  static const backfillWindow = Duration(hours: 24);

  bool _sweeping = false;

  /// Picks up calls the telecaller made or took OUTSIDE the app.
  ///
  /// The real-time listener only fires while the app process is alive, which
  /// on OEMs with aggressive battery management often isn't the case when a
  /// call ends. The phone's own call log kept the record regardless, so this
  /// walks it on app open and pushes anything matching a lead through exactly
  /// the same capture → upload → analyse path an app-placed call takes.
  ///
  /// Silent by design: no navigation, no interruption. A picked-up call simply
  /// appears in the lead's history once it has been processed.
  ///
  /// Fail-soft throughout — a lead that can't be matched, or a call whose
  /// recording the dialer already deleted, is skipped, not surfaced as an
  /// error. Requires [callLogSyncProvider] to have synced first (the caller
  /// does that) so the entries being read are current.
  Future<void> sweepBackfill() async {
    if (_sweeping) return;
    _sweeping = true;
    try {
      final cutoff = DateTime.now().subtract(backfillWindow);
      final candidates =
          [
            for (final e in ref.read(localCallsProvider))
              // deviceCallId: only entries from the phone's real call log —
              // an app-placed call is already handled by PostCallScreen.
              // callId == null: not already uploaded.
              // duration > 0: a missed/unanswered call has no recording to find,
              // and scanning for one only produces noise in the telemetry.
              if (e.deviceCallId != null &&
                  e.callId == null &&
                  e.duration > Duration.zero &&
                  e.calledAt.isAfter(cutoff))
                e,
          ]..sort((a, b) => b.calledAt.compareTo(a.calledAt));
      if (candidates.isEmpty) return;

      final matcher = ref.read(leadCallMatcherProvider);
      for (final entry in candidates) {
        final leadId = entry.leadId ?? await matcher.matchLeadId(entry.phone);
        // Not a lead — leave it alone. Uploading it would CREATE one.
        if (leadId == null) continue;

        final existing = stateFor(leadId);
        if (existing.isBusy) continue;
        if (existing.hasRecording ||
            existing.status == CaptureStatus.transcribed) {
          final captured = existing.recording?.recordedAt;
          // The state already covers a recording at least as new as this call,
          // so there's nothing older to go back for.
          if (captured != null && !captured.isBefore(entry.calledAt)) continue;
          // A previous, older call to the same lead is still parked in state;
          // clear it or captureLatest's guard would drop this one silently.
          resetForNewCall(leadId);
        }

        // manual: true — no 30-minute recency bound. That bound exists for the
        // call that JUST ended; a backfilled call is hours old by definition,
        // and the phone-in-filename hint is what picks the right file here.
        await captureLatest(
          leadId,
          manual: true,
          captureSource: CaptureSource.autoDetectedBackfill,
        );
      }
    } finally {
      _sweeping = false;
    }
  }

  /// Opens OS settings so the user can grant a blocked permission.
  Future<void> openPermissionSettings() =>
      ref.read(callRecordingServiceProvider).openSettings();

  /// Fire-and-forget capture-attempt telemetry — see
  /// [CaptureTelemetryService] doc for why this exists and its fail-soft
  /// contract. Never awaited by callers; never throws.
  ///
  /// [accessLevel] rides along on every outcome: "not_found" means one thing
  /// with all-files access and something else entirely with audio-only access,
  /// and the aggregate cannot tell those apart without it.
  ///
  /// ONE report per outcome per capture episode. A single ended call runs the
  /// scan up to four times on a backoff ladder (see PostCallScreen's
  /// `_captureWithRetries`, which exists because some dialers flush the file
  /// late) and runs it again on every app resume — measured on a real device,
  /// that put 15 identical `not_found` rows in the table inside a minute for
  /// ONE call. That is worse than noise: it inflates the failure count of
  /// exactly the phones that fail, biasing the very failure rate
  /// `/api/telemetry/capture-stats` exists to measure.
  ///
  /// A CHANGE of outcome still reports — "not_found then found" is the retry
  /// ladder doing its job, and that transition is worth knowing about.
  Future<void> _reportCaptureTelemetry(
    String leadId,
    String outcome, [
    String? accessLevel,
    String telemetrySource = 'auto',
  ]) async {
    final current = stateFor(leadId);
    if (current.reportedOutcome == outcome) return;
    _set(leadId, current.copyWith(reportedOutcome: outcome));
    await ref
        .read(captureTelemetryServiceProvider)
        .report(outcome, accessLevel: accessLevel, source: telemetrySource);
  }

  static String _stageLabel(String stage) => switch (stage) {
    'upload' => 'Uploading recording…',
    'transcribe' => 'Speech to text…',
    'analyse' || 'analyze' => 'Analysing call…',
    'done' => 'Done',
    _ => 'Processing…',
  };

  static String _friendlyError(String raw) {
    if (raw.contains('reach') ||
        raw.contains('SocketException') ||
        raw.contains('Connection refused')) {
      return 'Cannot reach the transcription server. '
          'Make sure the backend is running on the same Wi-Fi.';
    }
    // Matches TranscriptionService's two _pollUntilProcessed deadline
    // messages ("Transcription timed out." / "...taking too long..."), which
    // don't contain the literal substring "timeout" so they fell through to
    // the raw `ApiException(network): ...` string below before this check.
    if (raw.contains('timed out') || raw.contains('taking too long')) {
      return 'Still processing on the server — this can take a few minutes '
          'on a slow connection. Please try again shortly.';
    }
    return raw;
  }

  /// Uploads the captured recording for speech-to-text.
  Future<void> transcribe(
    String leadId, {
    String captureSource = CaptureSource.appCall,
  }) async {
    final current = stateFor(leadId);
    final recording = current.recording;
    if (recording == null || current.status == CaptureStatus.transcribing) {
      return;
    }

    _set(
      leadId,
      current.copyWith(
        status: CaptureStatus.transcribing,
        processingLabel: 'Uploading recording…',
        processingPercent: 0,
      ),
    );

    // Look up the lead so the upload carries the real phone/name/source and
    // attaches to this exact lead (contact_key). The auto-capture path used to
    // send only leadId as `name`, so calls could re-slugify to a different lead
    // and never carried a phone number for the backend's phone-based keying.
    final leads = ref.read(leadsProvider);
    final matches = leads.where((l) => l.id == leadId);
    final lead = matches.isEmpty ? null : matches.first;

    // If this exact recording was already uploaded, reuse its call_id instead of
    // re-uploading the same bytes (survives restarts / folder re-scans).
    final ledger = ref.read(localUploadLedgerProvider);
    final existingCallId = await ledger.callIdFor(recording);

    try {
      final result = await ref
          .read(transcriptionServiceProvider)
          .transcribe(
            recording: recording,
            leadId: leadId,
            name: lead?.name,
            phone: lead?.phone,
            source: lead?.source.name,
            contactKey: leadId,
            existingCallId: existingCallId,
            captureSource: captureSource,
            onCallId: (id) => unawaited(ledger.remember(recording, id)),
            onProgress: (stage, percent) {
              final prior = stateFor(leadId).processingPercent ?? 0;
              _set(
                leadId,
                stateFor(leadId).copyWith(
                  processingLabel: _stageLabel(stage),
                  // The backend's stages don't share one continuous scale (a
                  // later stage's first tick can report a lower percent than
                  // the previous stage's last one), so clamp to monotonic —
                  // otherwise the progress bar visibly jumps backward.
                  processingPercent: percent > prior ? percent : prior,
                ),
              );
            },
          );
      _set(
        leadId,
        current.copyWith(
          status: CaptureStatus.transcribed,
          transcription: result,
        ),
      );
      // Persist to device storage so transcript survives app restarts.
      unawaited(ref.read(localTranscriptStoreProvider).save(leadId, result));
      // Succeeded — clear any queued retry for this recording.
      unawaited(ref.read(localUploadOutboxProvider).remove(recording.path));
      // Re-fetch lead detail so the call history panel reflects the new call.
      unawaited(ref.read(leadsProvider.notifier).enrich(leadId));
    } catch (e) {
      // Queue the recording for automatic retry (survives app kill / offline),
      // so a failed upload isn't lost the moment the user leaves this screen.
      // The dedup ledger + backend content-hash guard make the retry idempotent.
      unawaited(
        ref
            .read(localUploadOutboxProvider)
            .enqueue(
              OutboxEntry(
                leadId: leadId,
                path: recording.path,
                name: lead?.name,
                phone: lead?.phone,
                source: lead?.source.name,
                contactKey: leadId,
                callDateIso: recording.recordedAt.toIso8601String(),
                captureSource: captureSource,
              ),
            ),
      );
      _set(
        leadId,
        current.copyWith(
          status: CaptureStatus.error,
          message: _friendlyError('$e'),
        ),
      );
    }
  }

  /// True while [drainOutbox] is running — guards against two concurrent
  /// drains (e.g. PostCallScreen's own resume-retry and MainShell's lifecycle
  /// hook both firing on the same resume) racing to read the same pending
  /// entries and each uploading them, which only the backend's content-hash
  /// dedup would catch after the fact.
  bool _drainingOutbox = false;

  /// Best-effort background retry of every recording queued by a previous failed
  /// upload. Call on app resume. Each entry is retried once per drain; a success
  /// removes it, a failure bumps its attempt count (and drops it after the
  /// outbox's max attempts). Fail-soft: any error just leaves the entry queued.
  Future<void> drainOutbox() async {
    if (_drainingOutbox) return;
    _drainingOutbox = true;
    try {
      final outbox = ref.read(localUploadOutboxProvider);
      final pending = await outbox.all();
      for (final entry in pending) {
        final file = File(entry.path);
        if (!file.existsSync()) {
          // The dialer deleted the recording — nothing to retry, stop tracking it.
          await outbox.remove(entry.path);
          continue;
        }
        final CallRecording recording;
        try {
          // `statSync()` inside `fromFile` races the dialer/OS deleting the
          // file between the `existsSync()` check above and here — without
          // this try/catch that throws out of the whole loop, silently
          // abandoning every other queued entry for this drain cycle.
          recording = CallRecording.fromFile(file);
        } catch (_) {
          await outbox.remove(entry.path);
          continue;
        }
        final ledger = ref.read(localUploadLedgerProvider);
        final existingCallId = await ledger.callIdFor(recording);
        try {
          await ref
              .read(transcriptionServiceProvider)
              .transcribe(
                recording: recording,
                leadId: entry.leadId,
                name: entry.name,
                phone: entry.phone,
                source: entry.source,
                contactKey: entry.contactKey ?? entry.leadId,
                existingCallId: existingCallId,
                captureSource: entry.captureSource,
                onCallId: (id) => unawaited(ledger.remember(recording, id)),
              );
          await outbox.remove(entry.path);
          unawaited(ref.read(leadsProvider.notifier).enrich(entry.leadId));
        } catch (e) {
          await outbox.markFailure(entry.path, '$e');
        }
      }
    } finally {
      _drainingOutbox = false;
    }
  }
}
