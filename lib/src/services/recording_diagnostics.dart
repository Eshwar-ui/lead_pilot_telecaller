import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_recording.dart';
import 'call_recording_service.dart';

/// Answers "why did this phone not find the recording?" on the device itself.
///
/// Auto-capture reads a file the phone's own dialer wrote (see
/// [CallRecordingService]); when it comes up empty the app can currently only
/// say "no recent recording found", which covers at least five unrelated
/// causes — auto-record switched off in the dialer, a vendor folder nobody
/// hardcoded, a folder that exists but is unreadable at the access level we
/// hold, a permission the OS refused, or a recording that exists but fell
/// outside the recency window. Support cannot tell those apart over a phone
/// call, and the `capture_telemetry` table stores only the outcome.
///
/// This walks the same candidate folders the real scan does and records what
/// it saw, so a failing handset can report its own state instead of being
/// guessed about.
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

  /// Cap on files counted per folder. A "Recordings" folder can hold thousands;
  /// the diagnosis only needs to know whether it holds any and roughly how
  /// fresh they are, and this runs on the UI thread from a button press.
  static const int _maxFilesCounted = 500;

  Future<RecordingDiagnosticsReport> run() async {
    if (!_isAndroid) {
      return const RecordingDiagnosticsReport(
        platformSupported: false,
        dirs: [],
      );
    }

    final sdkInt = await _recordings.androidSdkInt();
    final allFiles = await Permission.manageExternalStorage.status;
    // STATUS only — a diagnostic must observe, never prompt. A permission
    // dialog opening mid-report would change the very thing being measured.
    final mediaAudio = sdkInt >= 33
        ? await Permission.audio.status
        : PermissionStatus.denied;
    final legacy = sdkInt >= 33
        ? PermissionStatus.denied
        : await Permission.storage.status;

    final level = CallRecordingService.decideAccess(
      sdkInt: sdkInt,
      allFiles: allFiles,
      mediaAudio: mediaAudio,
      legacyStorage: legacy,
    );

    final dirs = [
      for (final path in CallRecordingService.candidateDirs) _probe(path),
    ];

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
      allFilesUnavailable: level.allFilesUnavailable,
      dirs: dirs,
      foundRecording: found != null,
      foundRecordingAge: found == null
          ? null
          : DateTime.now().difference(found.recordedAt),
      scanError: scanError,
    );
  }

  /// Inspects one candidate folder. Never throws: an unreadable folder is a
  /// FINDING (it is the signature of holding too little access), not an error
  /// that should abort the rest of the report.
  static DirectoryProbe _probe(String path) {
    final dir = Directory(path);
    bool exists;
    try {
      exists = dir.existsSync();
    } catch (_) {
      // A sandboxed path can throw rather than answer false.
      return DirectoryProbe(path: path, exists: false, readable: false);
    }
    if (!exists) return DirectoryProbe(path: path, exists: false, readable: false);

    var audioFiles = 0;
    var subdirs = 0;
    DateTime? newest;
    try {
      var counted = 0;
      for (final entry in dir.listSync(followLinks: false)) {
        if (counted++ >= _maxFilesCounted) break;
        if (entry is Directory) {
          subdirs++;
          continue;
        }
        if (entry is! File || !_isAudio(entry.path)) continue;
        audioFiles++;
        try {
          final modified = entry.statSync().modified;
          if (newest == null || modified.isAfter(newest)) newest = modified;
        } on FileSystemException {
          continue; // rotated away mid-scan
        }
      }
    } on FileSystemException {
      return DirectoryProbe(path: path, exists: true, readable: false);
    }

    return DirectoryProbe(
      path: path,
      exists: true,
      readable: true,
      audioFiles: audioFiles,
      subdirectories: subdirs,
      newestAudioAge: newest == null ? null : DateTime.now().difference(newest),
    );
  }

  static bool _isAudio(String path) {
    const extensions = {'mp3', 'm4a', 'amr', 'wav', 'aac', 'ogg', '3gp', 'mp4'};
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return extensions.contains(path.substring(dot + 1).toLowerCase());
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

/// What one candidate folder looked like. No filenames — see the class doc.
@immutable
class DirectoryProbe {
  const DirectoryProbe({
    required this.path,
    required this.exists,
    required this.readable,
    this.audioFiles = 0,
    this.subdirectories = 0,
    this.newestAudioAge,
  });

  final String path;
  final bool exists;

  /// Whether the folder could be listed. A folder that exists but cannot be
  /// listed is the fingerprint of insufficient storage access — the single
  /// most useful bit in the whole report.
  final bool readable;
  final int audioFiles;
  final int subdirectories;
  final Duration? newestAudioAge;

  Map<String, dynamic> toJson() => {
    'path': path,
    'exists': exists,
    'readable': readable,
    if (exists && readable) 'audio_files': audioFiles,
    if (exists && readable) 'subdirectories': subdirectories,
    if (newestAudioAge != null) 'newest_audio_age_minutes': newestAudioAge!.inMinutes,
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

  /// A recording folder exists but cannot be read at the access level held —
  /// the Android 13+ / sideloaded-build signature.
  foldersUnreadable,

  /// No candidate folder exists at all: this dialer isn't writing recordings
  /// anywhere we know of (auto-record off, or an unknown vendor path).
  noFolders,

  /// Folders are readable but hold no audio — auto-record is off in the dialer.
  foldersEmpty,

  /// Recordings exist on the device but the scan still returned none.
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
    this.allFilesUnavailable = false,
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
  final bool allFilesUnavailable;
  final List<DirectoryProbe> dirs;
  final bool foundRecording;
  final Duration? foundRecordingAge;
  final String? scanError;

  List<DirectoryProbe> get existingDirs => dirs.where((d) => d.exists).toList();
  List<DirectoryProbe> get readableDirs =>
      dirs.where((d) => d.exists && d.readable).toList();
  int get audioFilesSeen =>
      readableDirs.fold(0, (sum, d) => sum + d.audioFiles);

  /// The diagnosis. Ordered most-specific first: each branch below rules out
  /// everything above it, so the first match is the actual blocker rather than
  /// a downstream symptom of it.
  RecordingVerdict get verdict {
    if (!platformSupported) return RecordingVerdict.unsupported;
    if (foundRecording) return RecordingVerdict.working;
    if (permissionResult != StoragePermissionResult.granted) {
      return RecordingVerdict.permissionMissing;
    }
    if (existingDirs.isEmpty) return RecordingVerdict.noFolders;
    if (readableDirs.isEmpty) return RecordingVerdict.foldersUnreadable;
    if (audioFilesSeen == 0) return RecordingVerdict.foldersEmpty;
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
      'No call-recording folder was found on this phone.',
    RecordingVerdict.foldersUnreadable =>
      'The recording folder exists but this app cannot open it.',
    RecordingVerdict.foldersEmpty =>
      'The recording folder is empty — your dialer is not saving calls.',
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
      // A folder the app may not even stat reads as "absent", so this is not
      // purely a dialer-settings problem: on MIUI the recordings folder is
      // unlistable without all-files access and disappears from this probe
      // entirely. Name both, cheapest first.
      'Tap "Grant All files access" below, then run this check again. If it '
          'still finds nothing, turn on "Record calls" in your phone\'s Phone '
          'app settings and make one test call.',
    RecordingVerdict.foldersUnreadable => allFilesUnavailable
        ? 'Your phone refused "All files access". If the toggle is greyed out, '
              'Android is blocking it because the app was not installed from '
              'the Play Store — ask your admin. Upload recordings manually '
              'meanwhile.'
        : 'Tap "Grant All files access" below. Your dialer saves recordings in '
              'a private folder that this app cannot open without it.',
    RecordingVerdict.foldersEmpty =>
      'Turn on call recording in your Phone app, then make one test call and '
          'run this check again.',
    RecordingVerdict.recordingsNotMatched =>
      'Recordings are being saved but not matched automatically. Send this '
          'report to support and upload the call manually for now.',
  };

  /// The snapshot posted to `/api/telemetry/capture-attempt` as `details`.
  Map<String, dynamic> toJson() => {
    'verdict': verdict.name,
    'access_level': accessLevel.wireName,
    'permission_result': permissionResult.name,
    'all_files_unavailable': allFilesUnavailable,
    'dirs_existing': existingDirs.length,
    'dirs_readable': readableDirs.length,
    'audio_files_seen': audioFilesSeen,
    'found_recording': foundRecording,
    if (foundRecordingAge != null)
      'found_recording_age_minutes': foundRecordingAge!.inMinutes,
    if (scanError != null) 'scan_error': scanError,
    // Only folders that exist: shipping 20-odd "does not exist" rows from every
    // device would bury the two lines that matter.
    'dirs': [for (final d in existingDirs) d.toJson()],
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
