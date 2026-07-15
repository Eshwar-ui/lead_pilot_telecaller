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
  ///
  /// Each folder is scanned **recursively** (see [_maxScanDepth]) because many
  /// dialers nest recordings in per-number or per-date subfolders
  /// (e.g. `Recordings/Call/9876543210/Call recording ….m4a`), so a flat scan
  /// of the top folder alone misses them even on a supported phone. Keep this
  /// list broad — an extra non-existent path costs nothing (it's skipped), and
  /// a missing one silently drops that whole phone brand.
  static const List<String> _candidateDirs = [
    // Xiaomi / MIUI / HyperOS
    '/storage/emulated/0/MIUI/sound_recorder/call_rec',
    '/storage/emulated/0/MIUI/sound_recorder/call',
    '/storage/emulated/0/MIUI/sound_recorder',
    '/storage/emulated/0/Recordings/call_rec',
    // Samsung (One UI)
    '/storage/emulated/0/Recordings/Call',
    '/storage/emulated/0/Sounds', // older One UI / voice recorder
    '/storage/emulated/0/Call',
    // Oppo / Realme / OnePlus (ColorOS / OxygenOS)
    '/storage/emulated/0/Recordings/Call Recordings',
    '/storage/emulated/0/Music/Recordings/Call Recordings',
    '/storage/emulated/0/Record/PhoneRecord',
    // Vivo / iQOO (Funtouch / OriginOS)
    '/storage/emulated/0/Record/Call',
    '/storage/emulated/0/记录', // some Funtouch builds localise the folder name
    // Motorola / Lenovo
    '/storage/emulated/0/Android/data/com.motorola.dialer/files',
    // Huawei / Honor (EMUI / MagicOS)
    '/storage/emulated/0/Sounds/CallRecord',
    '/storage/emulated/0/record',
    // Transsion — Tecno / Infinix / itel (HiOS / XOS)
    '/storage/emulated/0/Recorder/call',
    // Generic / other dialers & third-party recorders
    '/storage/emulated/0/Recordings',
    '/storage/emulated/0/CallRecordings',
    '/storage/emulated/0/PhoneRecord',
    '/storage/emulated/0/Call recordings',
    '/storage/emulated/0/Music/Recordings',
  ];

  /// How many subfolder levels below a candidate dir to search. OEM dialers
  /// nest by number/date at most 1–2 levels; a small cap keeps the scan fast
  /// and avoids walking huge unrelated trees (e.g. all of `Recordings`).
  static const int _maxScanDepth = 2;

  /// Safety cap on how many files/dirs we'll visit per candidate root, so a
  /// pathological folder can't stall the UI thread.
  static const int _maxEntriesPerRoot = 4000;

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

  /// Finds the call recording that best matches the call that just happened.
  ///
  /// [within] bounds how old a file may be and still be considered "the call
  /// that just happened" — defaults to 30 minutes so a recording isn't matched
  /// to an unrelated old file. Pass `null` to ignore recency entirely (e.g. for
  /// a manual "pick the latest recording" action).
  ///
  /// [phoneHint] — when the lead's phone number is known, prefer a file whose
  /// name contains that number (most OEM dialers embed the dialed number in the
  /// recording filename, e.g. `Call recording 9876543210_251007.m4a`). This is
  /// far more reliable than "newest file wins", which can grab an unrelated
  /// recording made in the same window. Falls back to newest-in-window when no
  /// filename matches the number.
  ///
  /// Returns `null` if the platform is unsupported, no folder exists, or no
  /// audio file matches.
  Future<CallRecording?> findLatestRecording({
    Duration? within = const Duration(minutes: 30),
    String? phoneHint,
  }) async {
    if (!_isAndroid) return null;

    final now = DateTime.now();
    final digits = _phoneDigits(phoneHint);
    File? newest;
    DateTime? newestModified;
    File? newestMatch;
    DateTime? newestMatchModified;

    final seen = <String>{}; // dedupe files reachable from overlapping roots
    for (final dirPath in _candidateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      for (final entry in _audioFilesUnder(dir)) {
        if (!seen.add(entry.path)) continue;

        final DateTime modified;
        try {
          modified = entry.statSync().modified;
        } on FileSystemException {
          continue; // vanished/unreadable between listing and stat — skip
        }
        if (within != null && now.difference(modified) > within) continue;

        if (newestModified == null || modified.isAfter(newestModified)) {
          newest = entry;
          newestModified = modified;
        }
        // Phone-matched candidate: filename (digits only) contains the number.
        if (digits.isNotEmpty && _fileNameDigits(entry.path).contains(digits)) {
          if (newestMatchModified == null || modified.isAfter(newestMatchModified)) {
            newestMatch = entry;
            newestMatchModified = modified;
          }
        }
      }
    }

    // A phone-matched recording wins over merely-newest; fall back otherwise.
    final chosen = newestMatch ?? newest;
    if (chosen == null) return null;
    return CallRecording.fromFile(chosen);
  }

  /// Yields every audio file under [root], descending at most [_maxScanDepth]
  /// subfolder levels and visiting at most [_maxEntriesPerRoot] entries. Folders
  /// that aren't readable (permission/sandbox) are skipped rather than thrown,
  /// so one locked subfolder never aborts the whole scan.
  static Iterable<File> _audioFilesUnder(Directory root) sync* {
    var budget = _maxEntriesPerRoot;
    // Iterative BFS with an explicit depth so we can bound both depth and count.
    final queue = <MapEntry<Directory, int>>[MapEntry(root, 0)];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final dir = current.key;
      final depth = current.value;

      final List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue; // unreadable folder — skip, don't abort the scan
      }

      for (final entry in entries) {
        if (budget-- <= 0) return; // safety cap hit
        if (entry is File) {
          if (_isAudioFileStatic(entry.path)) yield entry;
        } else if (entry is Directory && depth < _maxScanDepth) {
          queue.add(MapEntry(entry, depth + 1));
        }
      }
    }
  }

  /// Last 10 digits of a phone number (drops +91 / spaces / separators) so a
  /// number matches regardless of how the dialer formatted it in the filename.
  static String _phoneDigits(String? phone) {
    if (phone == null) return '';
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  static String _fileNameDigits(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.replaceAll(RegExp(r'\D'), '');
  }

  static bool _isAudioFileStatic(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return _audioExtensions.contains(path.substring(dot + 1).toLowerCase());
  }
}
