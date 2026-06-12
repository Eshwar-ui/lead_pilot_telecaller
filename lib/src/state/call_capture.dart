import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/call_recording.dart';
import '../services/call_recording_service.dart';
import '../services/transcription_service.dart';

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

/// Immutable per-lead capture state held in the [callCaptureProvider] map.
class CallCaptureState {
  const CallCaptureState({
    this.status = CaptureStatus.idle,
    this.recording,
    this.transcription,
    this.message,
  });

  final CaptureStatus status;
  final CallRecording? recording;
  final CallTranscription? transcription;

  /// User-facing detail for [CaptureStatus.error]/permission states.
  final String? message;

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
  }) {
    return CallCaptureState(
      status: status ?? this.status,
      recording: recording ?? this.recording,
      transcription: transcription ?? this.transcription,
      message: message,
    );
  }
}

final callRecordingServiceProvider = Provider<CallRecordingService>(
  (ref) => const CallRecordingService(),
);

final transcriptionServiceProvider = Provider<TranscriptionService>(
  (ref) => const TranscriptionService(),
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

  /// Finds the recording the dialer saved for the call that just ended and
  /// stores it against [leadId]. Safe to call repeatedly (e.g. on resume).
  Future<void> captureLatest(String leadId) async {
    final service = ref.read(callRecordingServiceProvider);
    final existing = stateFor(leadId);

    // Don't re-scan while busy or once we already have a recording for it.
    if (existing.isBusy || existing.hasRecording) return;

    _set(leadId, existing.copyWith(status: CaptureStatus.checkingPermission));

    final permission = await service.ensureStoragePermission();
    switch (permission) {
      case StoragePermissionResult.unsupported:
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.unsupported,
            message: 'Call recording capture is available on Android only.',
          ),
        );
        return;
      case StoragePermissionResult.denied:
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.permissionDenied,
            message: 'Storage access is needed to read the call recording.',
          ),
        );
        return;
      case StoragePermissionResult.permanentlyDenied:
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.permissionBlocked,
            message: 'Enable "All files access" in Settings to read recordings.',
          ),
        );
        return;
      case StoragePermissionResult.granted:
        break;
    }

    _set(leadId, existing.copyWith(status: CaptureStatus.scanning));

    try {
      final recording = await service.findLatestRecording();
      if (recording == null) {
        _set(
          leadId,
          existing.copyWith(
            status: CaptureStatus.notFound,
            message: 'No recent recording found. Is auto-record on in your '
                'dialer?',
          ),
        );
        return;
      }
      _set(
        leadId,
        existing.copyWith(status: CaptureStatus.found, recording: recording),
      );
    } catch (e) {
      _set(
        leadId,
        existing.copyWith(status: CaptureStatus.error, message: '$e'),
      );
    }
  }

  /// Opens OS settings so the user can grant a blocked permission.
  Future<void> openPermissionSettings() =>
      ref.read(callRecordingServiceProvider).openSettings();

  /// Uploads the captured recording for speech-to-text.
  Future<void> transcribe(String leadId) async {
    final current = stateFor(leadId);
    final recording = current.recording;
    if (recording == null || current.status == CaptureStatus.transcribing) {
      return;
    }

    _set(leadId, current.copyWith(status: CaptureStatus.transcribing));

    try {
      final result = await ref
          .read(transcriptionServiceProvider)
          .transcribe(recording: recording, leadId: leadId);
      _set(
        leadId,
        current.copyWith(
          status: CaptureStatus.transcribed,
          transcription: result,
        ),
      );
    } catch (e) {
      _set(
        leadId,
        current.copyWith(status: CaptureStatus.error, message: '$e'),
      );
    }
  }
}
