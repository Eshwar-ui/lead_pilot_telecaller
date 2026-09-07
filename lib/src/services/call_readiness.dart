import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'call_actions.dart' as call_actions;
import 'call_recording_service.dart';

/// Why a call cannot start yet.
enum CallBlockReason {
  /// The app has no permission to read audio in shared storage, so a
  /// recording the dialer writes could never be picked up.
  permissionMissing,

  /// Permission is held, but nothing this phone can see looks like a call
  /// recording — the dialer's auto-record is off, or it writes somewhere
  /// MediaStore never indexes (a `.nomedia` folder, typically MIUI).
  noRecordingsVisible,
}

/// Gate in front of placing a call: a call this app cannot record is a call
/// that produces no transcript, no score and no memory, so the whole point of
/// making it through the app is lost.
///
/// Deliberately checks *capability*, not history. "Has a recording ever been
/// found" would deadlock a freshly-issued phone — no recording can exist until
/// a call is made, and no call could be made until one existed. Instead this
/// asks whether this phone is set up such that a recording *would* land
/// somewhere visible, which a telecaller can satisfy before their first call
/// by pointing the folder picker at their dialer's recordings folder.
class CallReadiness {
  const CallReadiness({CallRecordingService? recordings})
    : _recordings = recordings ?? const CallRecordingService();

  final CallRecordingService _recordings;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Null when the call may go ahead.
  ///
  /// Cheap by design — this runs before every call attempt. It queries
  /// MediaStore once and never materializes a file (unlike
  /// [RecordingDiagnostics], which copies one out to prove it is readable).
  Future<CallBlockReason?> check() async {
    if (!_isAndroid) return null;

    // A folder the telecaller granted explicitly is the strongest signal
    // there is, and settles it without any query: recordings written there
    // are readable whether or not MediaStore has ever indexed them.
    if (await _recordings.hasRecordingsFolderAccess()) return null;

    final sdkInt = await _recordings.androidSdkInt();
    final useMediaAudio = sdkInt >= 33;
    // STATUS, not request: the blocking dialog is what asks, so that the
    // telecaller reads why before the system prompt appears.
    final outcome = CallRecordingService.decideAccess(
      sdkInt: sdkInt,
      mediaAudio: useMediaAudio
          ? await Permission.audio.status
          : PermissionStatus.denied,
      legacyStorage: useMediaAudio
          ? PermissionStatus.denied
          : await Permission.storage.status,
    );
    if (outcome.result != StoragePermissionResult.granted) {
      return CallBlockReason.permissionMissing;
    }

    final rows = await call_actions.findRecentAudioRecordings(
      relativePathHints: CallRecordingService.relativePathHints,
      limit: _probeLimit,
    );
    return decide(
      sdkInt: sdkInt,
      permissionGranted: true,
      hasFolderGrant: false,
      rows: rows,
    );
  }

  /// How many MediaStore rows to look at. Only presence matters, so this is
  /// small — but not 1: the query biases toward recording folders rather than
  /// filtering to them, so a handful of unrelated audio files could otherwise
  /// crowd out the one row that would have proved capture works.
  static const _probeLimit = 60;

  /// The pure decision behind [check], so the branch that can lock a
  /// telecaller out of calling is testable without a device.
  ///
  /// Below Android 10 MediaStore has no RELATIVE_PATH column, so rows carry no
  /// folder at all; there, any audio on the phone is the best signal
  /// available and is accepted rather than blocking every such handset
  /// outright.
  static CallBlockReason? decide({
    required int sdkInt,
    required bool permissionGranted,
    required bool hasFolderGrant,
    required List<Map<String, dynamic>> rows,
  }) {
    if (hasFolderGrant) return null;
    if (!permissionGranted) return CallBlockReason.permissionMissing;
    if (rows.isEmpty) return CallBlockReason.noRecordingsVisible;
    if (sdkInt < 29) return null;

    final hints = CallRecordingService.relativePathHints;
    final inRecordingFolder = rows.any((row) {
      final path = row['relativePath'] as String?;
      return path != null && hints.any(path.startsWith);
    });
    return inRecordingFolder ? null : CallBlockReason.noRecordingsVisible;
  }
}
