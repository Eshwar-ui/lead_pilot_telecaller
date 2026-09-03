import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_recording.dart';
import 'call_actions.dart' as call_actions;
import 'call_recording_service.dart';

/// Answers "why did this phone not find the recording?" on the device itself.
///
/// Auto-capture reads a file the phone's own dialer wrote (see
/// [CallRecordingService]); when it comes up empty the app can currently only
/// say "no recent recording found", which covers several unrelated causes —
/// auto-record switched off in the dialer, a permission the OS refused, a
/// vendor folder MediaStore never indexed, or a recording that exists but
/// fell outside the recency window. Support cannot tell those apart over a
/// phone call, and the `capture_telemetry` table stores only the outcome.
///
/// This runs the same MediaStore query the real scan does, grouped by
/// candidate folder, so a failing handset can report its own state instead
/// of being guessed about.
///
/// **Privacy:** the report deliberately carries no filenames. OEM dialers put
/// the contact's name and phone number in them, and both this class and the
/// backend table it feeds are documented as free of call content and PII —
/// so a folder contributes counts and ages, never names.
class RecordingDiagnostics {
  const RecordingDiagnostics({CallRecordingService? recordings})
    : _recordings = recordings ?? const CallRecordingService();

  final CallRecordingService _recordings;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<RecordingDiagnosticsReport> run() async {
    if (!_isAndroid) {
      return const RecordingDiagnosticsReport(
        platformSupported: false,
        dirs: [],
      );
    }

    final sdkInt = await _recordings.androidSdkInt();
    // STATUS, not request: see CallRecordingService.ensureStoragePermission's
    // own doc comment — a diagnostic must observe, never prompt.
    final mediaAudio = sdkInt >= 33
        ? await Permission.audio.status
        : PermissionStatus.denied;
    final legacy = sdkInt >= 33
        ? PermissionStatus.denied
        : await Permission.storage.status;

    final level = CallRecordingService.decideAccess(
      sdkInt: sdkInt,
      mediaAudio: mediaAudio,
      legacyStorage: legacy,
    );

    var dirs = const <DirectoryProbe>[];
    var audioFilesSeen = 0;
    if (level.isGranted) {
      final rows = await call_actions.findRecentAudioRecordings(
        relativePathHints: CallRecordingService.relativePathHints,
        limit: 500,
      );
      dirs = _groupByFolder(rows);
      audioFilesSeen = rows.length;
    }

    // Same call the real capture makes, with no recency bound: "is there a
    // recording on this phone at all" is a different question from "did the
    // one from 20 seconds ago show up", and the report should answer the first.
    CallRecording? found;
    String? scanError;
    if (level.isGranted) {
      try {
        found = await _recordings.findLatestRecording(within: null);
      } catch (e) {
        scanError = e.toString();
      }
    }

    final device = await _device();
    return RecordingDiagnosticsReport(
      platformSupported: true,
      manufacturer: device.manufacturer,
      model: device.model,
      osVersion: device.osVersion,
      sdkInt: sdkInt,
      accessLevel: level.level,
      permissionResult: level.result,
      dirs: dirs,
      audioFilesSeen: audioFilesSeen,
      foundRecording: found != null,
      foundRecordingAge: found == null
          ? null
          : DateTime.now().difference(found.recordedAt),
      scanError: scanError,
    );
  }

  /// Buckets MediaStore rows by which candidate folder's relative-path hint
  /// they fall under, so the report can show per-folder counts the way the
  /// old raw-filesystem probe did — without a second, separate query per
  /// folder (one combined query, grouped client-side).
  static List<DirectoryProbe> _groupByFolder(List<Map<String, dynamic>> rows) {
    final hints = CallRecordingService.relativePathHints;
    final paths = CallRecordingService.candidateDirs;

    return [
      for (var i = 0; i < hints.length; i++)
        _probeFor(path: paths[i], hint: hints[i], rows: rows),
    ];
  }

  static DirectoryProbe _probeFor({
    required String path,
    required String hint,
    required List<Map<String, dynamic>> rows,
  }) {
    var audioFiles = 0;
    DateTime? newest;
    for (final row in rows) {
      final relativePath = row['relativePath'] as String?;
      // Below API 29 (no RELATIVE_PATH column) every row is unattributed —
      // counted under audioFilesSeen only, not any specific folder.
      if (relativePath == null || !relativePath.startsWith(hint)) continue;
      audioFiles++;
      final modifiedMs = (row['dateModifiedMs'] as num?)?.toInt() ?? 0;
      final modified = DateTime.fromMillisecondsSinceEpoch(modifiedMs);
      if (newest == null || modified.isAfter(newest)) newest = modified;
    }
    return DirectoryProbe(
      path: path,
      audioFiles: audioFiles,
      newestAudioAge: newest == null ? null : DateTime.now().difference(newest),
    );
  }

  Future<_Device> _device() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _Device(
        manufacturer: info.manufacturer,
        model: info.model,
        osVersion: 'Android ${info.version.release}',
      );
    } catch (_) {
      return const _Device();
    }
  }
}

class _Device {
  const _Device({this.manufacturer, this.model, this.osVersion});
  final String? manufacturer;
  final String? model;
  final String? osVersion;
}

/// What MediaStore reported for one candidate folder. No filenames — see the
/// class doc.
@immutable
class DirectoryProbe {
  const DirectoryProbe({
    required this.path,
    this.audioFiles = 0,
    this.newestAudioAge,
  });

  final String path;
  final int audioFiles;
  final Duration? newestAudioAge;

  Map<String, dynamic> toJson() => {
    'path': path,
    'audio_files': audioFiles,
    if (newestAudioAge != null)
      'newest_audio_age_minutes': newestAudioAge!.inMinutes,
  };
}

/// What the diagnostic concluded — the single line a telecaller reads and
/// support acts on.
enum RecordingVerdict {
  /// Capture is working: a recording was located.
  working,

  /// Not Android.
  unsupported,

  /// The storage permission was never granted.
  permissionMissing,

  /// No candidate folder holds any audio: this dialer isn't recording calls
  /// (auto-record off), the recordings live somewhere MediaStore doesn't
  /// index, or the folder path isn't one we know about.
  noFolders,

  /// Folders hold audio but the scan still returned none matching.
  recordingsNotMatched,
}

@immutable
class RecordingDiagnosticsReport {
  const RecordingDiagnosticsReport({
    required this.platformSupported,
    required this.dirs,
    this.manufacturer,
    this.model,
    this.osVersion,
    this.sdkInt,
    this.accessLevel = StorageAccessLevel.none,
    this.permissionResult = StoragePermissionResult.denied,
    this.audioFilesSeen = 0,
    this.foundRecording = false,
    this.foundRecordingAge,
    this.scanError,
  });

  final bool platformSupported;
  final String? manufacturer;
  final String? model;
  final String? osVersion;
  final int? sdkInt;
  final StorageAccessLevel accessLevel;
  final StoragePermissionResult permissionResult;
  final List<DirectoryProbe> dirs;

  /// Total matching audio files MediaStore returned, across all candidate
  /// folders (and, below API 29, files it couldn't attribute to a specific
  /// one — see [DirectoryProbe]/[_groupByFolder]).
  final int audioFilesSeen;
  final bool foundRecording;
  final Duration? foundRecordingAge;
  final String? scanError;

  /// The diagnosis. Ordered most-specific first: each branch below rules out
  /// everything above it, so the first match is the actual blocker rather than
  /// a downstream symptom of it.
  RecordingVerdict get verdict {
    if (!platformSupported) return RecordingVerdict.unsupported;
    if (foundRecording) return RecordingVerdict.working;
    if (permissionResult != StoragePermissionResult.granted) {
      return RecordingVerdict.permissionMissing;
    }
    if (audioFilesSeen == 0) return RecordingVerdict.noFolders;
    return RecordingVerdict.recordingsNotMatched;
  }

  /// One sentence for the telecaller: what is wrong.
  String get headline => switch (verdict) {
    RecordingVerdict.working => 'Call recordings are being detected.',
    RecordingVerdict.unsupported =>
      'Automatic capture works on Android phones only.',
    RecordingVerdict.permissionMissing =>
      'This app does not have permission to read audio files yet.',
    RecordingVerdict.noFolders =>
      'No call recordings were found on this phone.',
    RecordingVerdict.recordingsNotMatched =>
      'Recordings exist on this phone, but none matched the last call.',
  };

  /// What to actually do about it. Written for a telecaller, not a developer —
  /// this is the text support will read out over the phone.
  String get action => switch (verdict) {
    RecordingVerdict.working =>
      'Nothing to do. If a specific call is missing, upload it manually from '
          'the call screen.',
    RecordingVerdict.unsupported =>
      'Use an Android phone for automatic capture, or upload recordings '
          'manually.',
    RecordingVerdict.permissionMissing =>
      'Tap "Grant permission" below and allow access to music and audio.',
    RecordingVerdict.noFolders =>
      'Turn on "Record calls" in your phone\'s Phone app settings and make '
          'one test call, then run this check again. If it still finds '
          'nothing, your dialer may be saving recordings somewhere this app '
          'cannot see — upload the call manually meanwhile.',
    RecordingVerdict.recordingsNotMatched =>
      'Recordings are being saved but not matched automatically. Send this '
          'report to support and upload the call manually for now.',
  };

  /// The snapshot posted to `/api/telemetry/capture-attempt` as `details`.
  Map<String, dynamic> toJson() => {
    'verdict': verdict.name,
    'access_level': accessLevel.wireName,
    'permission_result': permissionResult.name,
    'audio_files_seen': audioFilesSeen,
    'found_recording': foundRecording,
    if (foundRecordingAge != null)
      'found_recording_age_minutes': foundRecordingAge!.inMinutes,
    if (scanError != null) 'scan_error': scanError,
    // Only folders that actually hold something: shipping 20-odd zero rows
    // from every device would bury the two lines that matter.
    'dirs': [
      for (final d in dirs)
        if (d.audioFiles > 0) d.toJson(),
    ],
  };

  /// The capture-attempt `outcome` this report corresponds to, so a hand-run
  /// check lands in the same vocabulary as an automatic attempt.
  String get outcome => switch (verdict) {
    RecordingVerdict.working => 'found',
    RecordingVerdict.unsupported => 'unsupported',
    RecordingVerdict.permissionMissing =>
      permissionResult == StoragePermissionResult.permanentlyDenied
          ? 'permission_blocked'
          : 'permission_denied',
    _ => 'not_found',
  };
}
