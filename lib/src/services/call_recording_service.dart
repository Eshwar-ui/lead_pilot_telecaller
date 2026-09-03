import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
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

/// How much of shared storage we actually ended up with.
///
/// This matters because "the scan found nothing" means something completely
/// different at each level, and the old code could not tell them apart — it
/// only knew granted/denied for one permission.
enum StorageAccessLevel {
  /// No readable access to shared storage at all.
  none,

  /// `READ_EXTERNAL_STORAGE` (Android 12 and below).
  legacy,

  /// `READ_MEDIA_AUDIO` (Android 13+). Audio files in shared storage are
  /// readable; other file types are not.
  mediaAudio,

  /// `MANAGE_EXTERNAL_STORAGE` ("All files access") — everything, including
  /// vendor folders that hold recordings the media scanner never indexed.
  allFiles;

  /// Wire value for capture telemetry (mirrors CaptureAccessLevel in
  /// app/schemas_capture_telemetry.py).
  String get wireName => switch (this) {
    StorageAccessLevel.none => 'none',
    StorageAccessLevel.legacy => 'legacy',
    StorageAccessLevel.mediaAudio => 'media_audio',
    StorageAccessLevel.allFiles => 'all_files',
  };
}

/// The outcome of [CallRecordingService.ensureStoragePermission]: whether we
/// may scan at all, and with how much reach.
class StoragePermissionOutcome {
  const StoragePermissionOutcome(
    this.result,
    this.level, {
    this.allFilesUnavailable = false,
  });

  final StoragePermissionResult result;
  final StorageAccessLevel level;

  /// We asked for all-files access and did not get it.
  ///
  /// This is EVIDENCE, not a guess. It was originally inferred from the API
  /// level — "Android 13+ withholds all-files access from apps installed
  /// outside the Play Store" — which is true of some devices and false of
  /// others: a Xiaomi on Android 16 (API 36), sideloaded, offers a perfectly
  /// usable "Allow access to manage all files" toggle. Inferring it hid the one
  /// action that fixes that phone, so it is now set only after a real request
  /// comes back refused. Drives help text, never control flow.
  final bool allFilesUnavailable;

  bool get isGranted => result == StoragePermissionResult.granted;
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

  /// The folders [findLatestRecording] probes, for the diagnostics screen to
  /// report on one by one (see RecordingDiagnostics). Exposed read-only so the
  /// diagnostic and the real scan can never drift apart into two lists.
  static List<String> get candidateDirs => _candidateDirs;

  /// How many subfolder levels below a candidate dir to search. OEM dialers
  /// nest by number/date at most 1–2 levels; a small cap keeps the scan fast
  /// and avoids walking huge unrelated trees (e.g. all of `Recordings`).
  static const int _maxScanDepth = 2;

  /// Safety cap on how many files/dirs we'll visit per candidate root, so a
  /// pathological folder can't stall the UI thread.
  static const int _maxEntriesPerRoot = 4000;

  /// Below this, a file is almost certainly an empty/just-created placeholder
  /// rather than a real recording — some OEM dialers create the file the
  /// instant a call connects and only write audio into it afterward. 4KB is
  /// comfortably below even a fraction of a second of compressed speech, so
  /// this can't reject a genuinely short-but-real recording.
  static const int _minRecordingBytes = 4096;

  static const Set<String> _audioExtensions = {
    'mp3',
    'm4a',
    'amr',
    'wav',
    'aac',
    'ogg',
    '3gp',
    'mp4',
  };

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Android API level, or 0 off-Android. Cached — it cannot change while the
  /// process lives, and the permission decision consults it on every capture.
  static int? _cachedSdkInt;

  /// Set once a real [requestAllFilesAccess] comes back refused. Only then may
  /// the UI tell the user that all-files access is unavailable to them — see
  /// [StoragePermissionOutcome.allFilesUnavailable].
  static bool _allFilesRequestRefused = false;

  Future<int> androidSdkInt() async {
    if (!_isAndroid) return 0;
    final cached = _cachedSdkInt;
    if (cached != null) return cached;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _cachedSdkInt = info.version.sdkInt;
    } catch (_) {
      // device_info_plus failing must not leave the app unable to ask for a
      // permission at all. 0 routes to the legacy branch, which is the safe
      // guess: requesting READ_EXTERNAL_STORAGE on a modern device is a no-op,
      // whereas skipping the request entirely would be fatal.
      return 0;
    }
  }

  /// Requests the permission needed to read the dialer's recording folder,
  /// asking for the one the OS will actually hand over.
  ///
  /// The order here is deliberate, and is the fix for the "Samsung can't detect
  /// recordings" report. The previous version led with a
  /// `MANAGE_EXTERNAL_STORAGE` REQUEST, which on Android 13+ sends the user to
  /// a Settings toggle that is greyed out for any app installed outside the
  /// Play Store ("For your security, this setting is currently unavailable"),
  /// with Samsung's Auto Blocker hardening that further. That request could
  /// therefore never succeed on a sideloaded build — and the fallback,
  /// `Permission.storage` → `READ_EXTERNAL_STORAGE`, is itself inert on
  /// Android 13+ (the manifest caps it at maxSdkVersion 32). So capture dead-
  /// ended on every modern handset, telling the user to flip a switch they
  /// cannot flip.
  ///
  /// Instead: honour all-files access if it is ALREADY held (nothing beats it
  /// for reach), otherwise request the ordinary runtime permission for this OS
  /// level — `READ_MEDIA_AUDIO` on 33+, `READ_EXTERNAL_STORAGE` below — which
  /// Restricted Settings does not touch. All-files access becomes an optional
  /// upgrade, offered in context by [requestAllFilesAccess].
  Future<StoragePermissionOutcome> ensureStoragePermission() async {
    if (!_isAndroid) {
      return const StoragePermissionOutcome(
        StoragePermissionResult.unsupported,
        StorageAccessLevel.none,
      );
    }

    final sdkInt = await androidSdkInt();
    // STATUS, not request: see the doc comment above. Requesting it here is
    // what stranded users on an ungrantable Settings page.
    final allFiles = await Permission.manageExternalStorage.status;
    if (allFiles.isGranted) {
      return const StoragePermissionOutcome(
        StoragePermissionResult.granted,
        StorageAccessLevel.allFiles,
      );
    }

    final useMediaAudio = sdkInt >= 33;
    final mediaAudio = useMediaAudio
        ? await Permission.audio.request()
        : PermissionStatus.denied;
    final legacy = useMediaAudio
        ? PermissionStatus.denied
        : await Permission.storage.request();

    return decideAccess(
      sdkInt: sdkInt,
      allFiles: allFiles,
      mediaAudio: mediaAudio,
      legacyStorage: legacy,
      allFilesRefused: _allFilesRequestRefused,
    );
  }

  /// Pure permission-decision logic, split out of [ensureStoragePermission].
  ///
  /// Public for two reasons: every branch below decides whether a real
  /// telecaller can capture a call at all and none of it used to be reachable
  /// from a unit test, and the Recording Check screen needs to report the same
  /// decision WITHOUT triggering a permission prompt (a diagnostic that
  /// changes the thing it measures is worthless).
  static StoragePermissionOutcome decideAccess({
    required int sdkInt,
    required PermissionStatus allFiles,
    required PermissionStatus mediaAudio,
    required PermissionStatus legacyStorage,
    bool allFilesRefused = false,
  }) {
    if (allFiles.isGranted) {
      return const StoragePermissionOutcome(
        StoragePermissionResult.granted,
        StorageAccessLevel.allFiles,
      );
    }

    final allFilesUnavailable = allFilesRefused;

    final useMediaAudio = sdkInt >= 33;
    final granted = useMediaAudio ? mediaAudio : legacyStorage;
    if (granted.isGranted) {
      return StoragePermissionOutcome(
        StoragePermissionResult.granted,
        useMediaAudio
            ? StorageAccessLevel.mediaAudio
            : StorageAccessLevel.legacy,
        allFilesUnavailable: allFilesUnavailable,
      );
    }

    // Only the permission we actually asked for can be "permanently denied" in
    // a way the user can fix in Settings. All-files access being unavailable is
    // NOT that — routing it here is what produced the dead end.
    if (granted.isPermanentlyDenied) {
      return StoragePermissionOutcome(
        StoragePermissionResult.permanentlyDenied,
        StorageAccessLevel.none,
        allFilesUnavailable: allFilesUnavailable,
      );
    }
    return StoragePermissionOutcome(
      StoragePermissionResult.denied,
      StorageAccessLevel.none,
      allFilesUnavailable: allFilesUnavailable,
    );
  }

  /// Optional escalation to "All files access", offered in context when a scan
  /// with ordinary media access still finds nothing (some OEM dialers write to
  /// vendor folders the media scanner never indexed).
  ///
  /// Returns whether it was granted. `false` is an ordinary outcome, not an
  /// error: on a sideloaded Android 13+ build the OS may simply refuse.
  Future<bool> requestAllFilesAccess() async {
    if (!_isAndroid) return false;
    if (await Permission.manageExternalStorage.isGranted) {
      _allFilesRequestRefused = false;
      return true;
    }
    final requested = await Permission.manageExternalStorage.request();
    _allFilesRequestRefused = !requested.isGranted;
    return requested.isGranted;
  }

  /// Whether all-files access is currently held — for diagnostics and UI copy.
  Future<bool> hasAllFilesAccess() async {
    if (!_isAndroid) return false;
    return Permission.manageExternalStorage.isGranted;
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
    final digits = phoneDigits(phoneHint);
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
          final stat = entry.statSync();
          // Some OEM dialers create a placeholder file the instant the call
          // connects and only write real audio into it afterward — a scan
          // landing in that window would otherwise happily "find" an
          // empty/near-empty stub and upload it as the recording. This isn't
          // a full still-growing guard (that needs a re-stat after a delay,
          // which would slow every scan), just a cheap floor that catches
          // the common empty-placeholder case for free off the same stat
          // call already being made.
          if (stat.size < _minRecordingBytes) continue;
          modified = stat.modified;
        } on FileSystemException {
          continue; // vanished/unreadable between listing and stat — skip
        }
        if (within != null && now.difference(modified) > within) continue;

        if (newestModified == null || modified.isAfter(newestModified)) {
          newest = entry;
          newestModified = modified;
        }
        // Phone-matched candidate: filename (digits only) contains the number.
        if (digits.isNotEmpty && fileNameDigits(entry.path).contains(digits)) {
          if (newestMatchModified == null ||
              modified.isAfter(newestMatchModified)) {
            newestMatch = entry;
            newestMatchModified = modified;
          }
        }
      }
    }

    // A phone-matched recording wins over merely-newest; fall back otherwise.
    final chosen = newestMatch ?? newest;
    if (chosen == null) return null;
    try {
      // Same TOCTOU window as the scan loop's own statSync above, just at the
      // end instead of during — an OEM dialer that rotates/deletes old
      // recordings can still remove `chosen` between being selected here and
      // this final stat. Treat it the same as "not found" instead of letting
      // a raw FileSystemException surface as "Something went wrong" in the UI.
      return CallRecording.fromFile(chosen);
    } on FileSystemException {
      return null;
    }
  }

  /// Lists recent call-recording files across the candidate folders, for
  /// manual "pick the recording" flows (e.g. uploading a past call) where a
  /// single best-guess file isn't enough — the telecaller needs to choose
  /// from several recent recordings for a specific call.
  ///
  /// Unlike [findLatestRecording] this has no recency cutoff (a past call
  /// being uploaded manually could be days old) and returns every match it
  /// finds, sorted rather than reduced to one. Recordings whose filename
  /// matches [phoneHint] sort first (most likely the right one), then
  /// everything else newest-first. Capped at [limit].
  Future<List<CallRecording>> listRecentRecordings({
    String? phoneHint,
    int limit = 25,
  }) async {
    if (!_isAndroid) return const [];

    final digits = phoneDigits(phoneHint);
    final seen = <String>{};
    final found = <CallRecording>[];

    for (final dirPath in _candidateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      for (final entry in _audioFilesUnder(dir)) {
        if (!seen.add(entry.path)) continue;
        try {
          final recording = CallRecording.fromFile(entry);
          // Same placeholder-file floor as findLatestRecording — don't
          // clutter the manual picker with a stub the OEM dialer hasn't
          // actually written audio into yet.
          if (recording.sizeBytes < _minRecordingBytes) continue;
          found.add(recording);
        } on FileSystemException {
          continue; // vanished/unreadable between listing and stat — skip
        }
      }
    }

    found.sort((a, b) {
      if (digits.isNotEmpty) {
        final aMatch = fileNameDigits(a.path).contains(digits);
        final bMatch = fileNameDigits(b.path).contains(digits);
        if (aMatch != bMatch) return aMatch ? -1 : 1;
      }
      return b.recordedAt.compareTo(a.recordedAt);
    });

    return found.take(limit).toList();
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
  ///
  /// Public (not `_`-prefixed) so this — the single biggest cause of a call
  /// attaching to the wrong lead if it's wrong — can be unit tested directly;
  /// [findLatestRecording] itself can't be, since it scans real hardcoded
  /// device paths and short-circuits to null off-Android.
  static String phoneDigits(String? phone) {
    if (phone == null) return '';
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  /// All digits in a recording's filename (OEM dialers embed the phone
  /// number there), for matching against [phoneDigits]. Public for the same
  /// testing reason as [phoneDigits].
  static String fileNameDigits(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.replaceAll(RegExp(r'\D'), '');
  }

  static bool _isAudioFileStatic(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return _audioExtensions.contains(path.substring(dot + 1).toLowerCase());
  }
}
