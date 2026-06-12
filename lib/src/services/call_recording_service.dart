import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_recording.dart';

/// Result of asking for the storage permission needed to read the dialer's
/// call-recording folder.
enum StoragePermissionResult {
  granted,

  /// User denied, but can be asked again.
  denied,

  /// User selected "Don't ask again" / blocked it. Must be sent to Settings.
  permanentlyDenied,

  /// Not Android — feature unsupported on this platform.
  unsupported,
}

/// Locates the MP3/M4A the phone's own dialer saved after a call ended.
///
/// ## How this works (and its limits)
///
/// Since Android 10 + the May 2022 Play policy, an app **cannot** record the
/// phone call itself. The only compliant way to obtain call audio from a normal
/// cellular call is to read the file the device's *built-in* dialer writes when
/// the user has enabled "auto record calls". This service does exactly that:
///
///   1. Ensures the broad-storage permission (`MANAGE_EXTERNAL_STORAGE`).
///   2. Scans the known vendor recording folders for the newest audio file.
///   3. Returns it as a [CallRecording] so it can be uploaded for transcription.
///
/// Caveats the UI should communicate to the user:
///   * Android only. iOS has no call auto-recording and is always [unsupported].
///   * Requires the user to have turned on auto-recording in their dialer — the
///     app cannot toggle that setting programmatically.
///   * Pixel / stock Android store recordings in private storage we cannot read.
class CallRecordingService {
  const CallRecordingService();

  /// Candidate folders where OEM dialers store call recordings, most-specific
  /// first. Xiaomi/MIUI/HyperOS paths are listed first since that's the primary
  /// target device.
  static const List<String> _candidateDirs = [
    // Xiaomi / MIUI / HyperOS
    '/storage/emulated/0/MIUI/sound_recorder/call_rec',
    '/storage/emulated/0/MIUI/sound_recorder/call',
    '/storage/emulated/0/Recordings/call_rec',
    // Samsung (One UI)
    '/storage/emulated/0/Recordings/Call',
    '/storage/emulated/0/Call',
    // Oppo / Realme / ColorOS
    '/storage/emulated/0/Recordings/Call Recordings',
    '/storage/emulated/0/Music/Recordings/Call Recordings',
    // Vivo / Funtouch
    '/storage/emulated/0/Record/Call',
    // Generic / other dialers
    '/storage/emulated/0/Recordings',
    '/storage/emulated/0/CallRecordings',
    '/storage/emulated/0/PhoneRecord',
  ];

  static const Set<String> _audioExtensions = {
    'mp3', 'm4a', 'amr', 'wav', 'aac', 'ogg', '3gp', 'mp4',
  };

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Requests the permission required to read the recording folder.
  ///
  /// On Android 11+ this is `MANAGE_EXTERNAL_STORAGE` ("All files access");
  /// on Android 10 and below it falls back to the legacy storage permission.
  Future<StoragePermissionResult> ensureStoragePermission() async {
    if (!_isAndroid) return StoragePermissionResult.unsupported;

    // Try scoped "All files access" first (needed on Android 11+ to read the
    // dialer's folder). On older devices this resolves immediately and we fall
    // back to the classic storage permission.
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return StoragePermissionResult.granted;

    final requested = await Permission.manageExternalStorage.request();
    if (requested.isGranted) return StoragePermissionResult.granted;

    // Fallback for Android 10 and below where manageExternalStorage is absent.
    final legacy = await Permission.storage.request();
    if (legacy.isGranted) return StoragePermissionResult.granted;

    if (requested.isPermanentlyDenied || legacy.isPermanentlyDenied) {
      return StoragePermissionResult.permanentlyDenied;
    }
    return StoragePermissionResult.denied;
  }

  /// Opens the OS settings page so the user can grant a permanently-denied
  /// permission. Mirrors the overlay-permission flow already used natively.
  Future<void> openSettings() => openAppSettings();

  /// Finds the most recently modified call recording.
  ///
  /// [within] bounds how old a file may be and still be considered "the call
  /// that just happened" — defaults to 30 minutes so a recording isn't matched
  /// to an unrelated old file. Pass `null` to ignore recency entirely (e.g. for
  /// a manual "pick the latest recording" action).
  ///
  /// Returns `null` if the platform is unsupported, no folder exists, or no
  /// audio file matches.
  Future<CallRecording?> findLatestRecording({
    Duration? within = const Duration(minutes: 30),
  }) async {
    if (!_isAndroid) return null;

    final now = DateTime.now();
    File? newest;
    DateTime? newestModified;

    for (final dirPath in _candidateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      final List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        // Folder exists but isn't readable (permission/sandbox) — skip it.
        continue;
      }

      for (final entry in entries) {
        if (entry is! File) continue;
        if (!_isAudioFile(entry.path)) continue;

        final modified = entry.statSync().modified;
        if (within != null && now.difference(modified) > within) continue;

        if (newestModified == null || modified.isAfter(newestModified)) {
          newest = entry;
          newestModified = modified;
        }
      }
    }

    if (newest == null) return null;
    return CallRecording.fromFile(newest);
  }

  bool _isAudioFile(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return _audioExtensions.contains(path.substring(dot + 1).toLowerCase());
  }
}
