import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_recording.dart';
import 'call_actions.dart' as call_actions;

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
enum StorageAccessLevel {
  /// No readable access to shared storage at all.
  none,

  /// `READ_EXTERNAL_STORAGE` (Android 12 and below).
  legacy,

  /// `READ_MEDIA_AUDIO` (Android 13+). Audio files in shared storage are
  /// readable via MediaStore; other file types are not.
  mediaAudio;

  /// Wire value for capture telemetry (mirrors CaptureAccessLevel in
  /// app/schemas_capture_telemetry.py — that Literal still has an unused
  /// `all_files` value from before this permission was removed; harmless,
  /// just never sent).
  String get wireName => switch (this) {
    StorageAccessLevel.none => 'none',
    StorageAccessLevel.legacy => 'legacy',
    StorageAccessLevel.mediaAudio => 'media_audio',
  };
}

/// The outcome of [CallRecordingService.ensureStoragePermission]: whether we
/// may scan at all, and with how much reach.
class StoragePermissionOutcome {
  const StoragePermissionOutcome(this.result, this.level);

  final StoragePermissionResult result;
  final StorageAccessLevel level;

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
///   1. Ensures the ordinary media-read permission (`READ_MEDIA_AUDIO` on 13+,
///      `READ_EXTERNAL_STORAGE` below).
///   2. Queries MediaStore (via a native platform-channel call — see
///      `call_actions.findRecentAudioRecordings`) for recent audio files under
///      the known vendor recording folders.
///   3. Materializes the matched file into a local cache file and returns it
///      as a [CallRecording] so it can be uploaded for transcription.
///
/// This deliberately does NOT use `MANAGE_EXTERNAL_STORAGE` ("All files
/// access") — Google Play rejected this app's declaration of that permission,
/// requiring the MediaStore approach used here instead. The tradeoff: a
/// vendor folder the media scanner never indexed (e.g. hidden behind a
/// `.nomedia` marker) is invisible to this service, same as it would be to
/// any other app without that permission. The manual "Browse Files" picker
/// (Storage Access Framework — needs no storage permission at all) remains
/// available as a fallback for that case.
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
  /// target device. Used to build MediaStore RELATIVE_PATH hints (see
  /// [_relativePathHints]) — kept as absolute paths for readability and
  /// because the diagnostics screen displays them to the user.
  ///
  /// Keep this list broad — an extra non-existent path costs nothing, and a
  /// missing one silently drops that whole phone brand.
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

  /// The folders the scan looks under, for the diagnostics screen to report
  /// on one by one (see RecordingDiagnostics). Exposed read-only so the
  /// diagnostic and the real scan can never drift apart into two lists.
  static List<String> get candidateDirs => _candidateDirs;

  /// [_candidateDirs] translated into MediaStore RELATIVE_PATH hints (folder
  /// fragments relative to the storage volume root, e.g.
  /// `"MIUI/sound_recorder/call_rec/"`) — passed to the native query rather
  /// than duplicated as a second hardcoded list on the Kotlin side.
  static List<String> get relativePathHints => _candidateDirs
      .map(_relativePathHint)
      .where((h) => h.isNotEmpty)
      .toList(growable: false);

  static String _relativePathHint(String absolutePath) {
    const prefix = '/storage/emulated/0/';
    if (!absolutePath.startsWith(prefix)) return '';
    final rest = absolutePath.substring(prefix.length);
    return rest.endsWith('/') ? rest : '$rest/';
  }

  /// How many candidate-folder audio files to fetch per query. Generous
  /// enough to cover every candidate folder's recent files without an
  /// unbounded query; the recency window / phone-digit match narrow it down
  /// from there.
  static const int _queryLimit = 300;

  /// Below this, a file is almost certainly an empty/just-created placeholder
  /// rather than a real recording — some OEM dialers create the file the
  /// instant a call connects and only write audio into it afterward. 4KB is
  /// comfortably below even a fraction of a second of compressed speech, so
  /// this can't reject a genuinely short-but-real recording.
  static const int _minRecordingBytes = 4096;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Android API level, or 0 off-Android. Cached — it cannot change while the
  /// process lives, and the permission decision consults it on every capture.
  static int? _cachedSdkInt;

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

  /// Requests the ordinary runtime permission for reading audio in shared
  /// storage — `READ_MEDIA_AUDIO` on 33+, `READ_EXTERNAL_STORAGE` below.
  Future<StoragePermissionOutcome> ensureStoragePermission() async {
    if (!_isAndroid) {
      return const StoragePermissionOutcome(
        StoragePermissionResult.unsupported,
        StorageAccessLevel.none,
      );
    }

    final sdkInt = await androidSdkInt();
    final useMediaAudio = sdkInt >= 33;
    final mediaAudio = useMediaAudio
        ? await Permission.audio.request()
        : PermissionStatus.denied;
    final legacy = useMediaAudio
        ? PermissionStatus.denied
        : await Permission.storage.request();

    return decideAccess(
      sdkInt: sdkInt,
      mediaAudio: mediaAudio,
      legacyStorage: legacy,
    );
  }

  /// Pure permission-decision logic, split out of [ensureStoragePermission].
  ///
  /// Public so it's unit-testable, and so the Recording Check screen can
  /// report the same decision WITHOUT triggering a permission prompt (a
  /// diagnostic that changes the thing it measures is worthless).
  static StoragePermissionOutcome decideAccess({
    required int sdkInt,
    required PermissionStatus mediaAudio,
    required PermissionStatus legacyStorage,
  }) {
    final useMediaAudio = sdkInt >= 33;
    final granted = useMediaAudio ? mediaAudio : legacyStorage;
    if (granted.isGranted) {
      return StoragePermissionOutcome(
        StoragePermissionResult.granted,
        useMediaAudio
            ? StorageAccessLevel.mediaAudio
            : StorageAccessLevel.legacy,
      );
    }
    if (granted.isPermanentlyDenied) {
      return const StoragePermissionOutcome(
        StoragePermissionResult.permanentlyDenied,
        StorageAccessLevel.none,
      );
    }
    return const StoragePermissionOutcome(
      StoragePermissionResult.denied,
      StorageAccessLevel.none,
    );
  }

  /// Opens the OS settings page so the user can grant a permanently-denied
  /// permission. Mirrors the overlay-permission flow already used natively.
  Future<void> openSettings() => openAppSettings();

  /// Opens the system folder picker so the telecaller can grant durable
  /// access to their call-recordings folder — for OEMs (MIUI in particular)
  /// whose dialer writes into a folder a `.nomedia` marker hides from
  /// MediaStore entirely, which [_allCandidateRows] otherwise can never see.
  /// Returns the granted folder path/URI, or `null` if cancelled/failed.
  Future<String?> pickRecordingsFolder() => call_actions.pickRecordingsFolder();

  /// Whether a [pickRecordingsFolder] grant is currently held and valid —
  /// for the Recording Check screen to show the right button label.
  Future<bool> hasRecordingsFolderAccess() =>
      call_actions.hasRecordingsFolderAccess();

  /// MediaStore rows plus, when a folder has been granted (see
  /// [pickRecordingsFolder]), rows from that folder too — concatenated so
  /// the existing selection/sort logic can treat both sources identically
  /// (same row shape from both; see `call_actions.dart`).
  Future<List<Map<String, dynamic>>> _allCandidateRows() async {
    final mediaStoreRows = await call_actions.findRecentAudioRecordings(
      relativePathHints: relativePathHints,
      limit: _queryLimit,
    );
    if (!await hasRecordingsFolderAccess()) return mediaStoreRows;

    final folderRows = await call_actions.listRecordingsInGrantedFolder(
      limit: _queryLimit,
    );
    return [...mediaStoreRows, ...folderRows];
  }

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
  /// Returns `null` if the platform is unsupported or no audio file matches.
  Future<CallRecording?> findLatestRecording({
    Duration? within = const Duration(minutes: 30),
    String? phoneHint,
  }) async {
    if (!_isAndroid) return null;

    final rows = await _allCandidateRows();
    final chosen = selectBestMatch(
      rows,
      phoneHint: phoneHint,
      within: within,
      now: DateTime.now(),
    );
    if (chosen == null) return null;

    final localPath = await call_actions.materializeMediaStoreRecording(
      chosen['contentUri'] as String,
    );
    if (localPath == null) return null;
    try {
      return CallRecording.fromFile(File(localPath));
    } on FileSystemException {
      return null;
    }
  }

  /// The selection logic behind [findLatestRecording], pulled out as a pure
  /// function so it's unit-testable without a platform channel: picks the
  /// phone-matched newest-within-window row, falling back to newest-in-window
  /// with no filename match. Mirrors the exact selection semantics the
  /// previous raw-filesystem-scan implementation had.
  static Map<String, dynamic>? selectBestMatch(
    List<Map<String, dynamic>> rows, {
    required String? phoneHint,
    required Duration? within,
    required DateTime now,
  }) {
    final digits = phoneDigits(phoneHint);
    Map<String, dynamic>? newest;
    DateTime? newestModified;
    Map<String, dynamic>? newestMatch;
    DateTime? newestMatchModified;

    for (final row in rows) {
      final sizeBytes = (row['sizeBytes'] as num?)?.toInt() ?? 0;
      // Same placeholder-file floor the raw scan used to apply off the same
      // stat call — some OEM dialers create the file the instant a call
      // connects and only write real audio into it afterward.
      if (sizeBytes < _minRecordingBytes) continue;

      final modified = DateTime.fromMillisecondsSinceEpoch(
        (row['dateModifiedMs'] as num?)?.toInt() ?? 0,
      );
      if (within != null && now.difference(modified) > within) continue;

      if (newestModified == null || modified.isAfter(newestModified)) {
        newest = row;
        newestModified = modified;
      }
      final displayName = (row['displayName'] as String?) ?? '';
      if (digits.isNotEmpty && fileNameDigits(displayName).contains(digits)) {
        if (newestMatchModified == null ||
            modified.isAfter(newestMatchModified)) {
          newestMatch = row;
          newestMatchModified = modified;
        }
      }
    }

    return newestMatch ?? newest;
  }

  /// Lists recent call-recording files across the candidate folders, for
  /// manual "pick the recording" flows (e.g. uploading a past call) where a
  /// single best-guess file isn't enough — the telecaller needs to choose
  /// from several recent recordings for a specific call.
  ///
  /// Unlike [findLatestRecording] this has no recency cutoff and returns
  /// every match it finds, sorted rather than reduced to one. Recordings
  /// whose filename matches [phoneHint] sort first, then everything else
  /// newest-first. Capped at [limit].
  ///
  /// Results are NOT materialized to local files (that would mean copying
  /// bytes for every candidate, most of which will never be picked) — see
  /// [materialize], called lazily once the telecaller actually selects one.
  Future<List<CallRecording>> listRecentRecordings({
    String? phoneHint,
    int limit = 25,
  }) async {
    if (!_isAndroid) return const [];

    final rows = await _allCandidateRows();
    final digits = phoneDigits(phoneHint);

    final found = rows
        .where(
          (row) =>
              ((row['sizeBytes'] as num?)?.toInt() ?? 0) >= _minRecordingBytes,
        )
        .map(CallRecording.fromMediaStoreRow)
        .toList();

    found.sort((a, b) {
      if (digits.isNotEmpty) {
        final aMatch = fileNameDigits(a.fileName).contains(digits);
        final bMatch = fileNameDigits(b.fileName).contains(digits);
        if (aMatch != bMatch) return aMatch ? -1 : 1;
      }
      return b.recordedAt.compareTo(a.recordedAt);
    });

    return found.take(limit).toList();
  }

  /// Resolves a [recording] from [listRecentRecordings] to a real local file
  /// by copying its MediaStore-referenced bytes into the app's cache — a
  /// no-op passthrough if it's already backed by a real file (e.g. one from
  /// [findLatestRecording], or the manual file picker). Returns `null` if the
  /// underlying file has vanished since the list was built.
  Future<CallRecording?> materialize(CallRecording recording) async {
    final contentUri = recording.contentUri;
    if (contentUri == null) return recording;

    final localPath = await call_actions.materializeMediaStoreRecording(
      contentUri,
    );
    if (localPath == null) return null;
    try {
      return CallRecording.fromFile(File(localPath));
    } on FileSystemException {
      return null;
    }
  }

  /// Last 10 digits of a phone number (drops +91 / spaces / separators) so a
  /// number matches regardless of how the dialer formatted it in the filename.
  ///
  /// Public (not `_`-prefixed) so this — the single biggest cause of a call
  /// attaching to the wrong lead if it's wrong — can be unit tested directly.
  static String phoneDigits(String? phone) {
    if (phone == null) return '';
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  /// All digits in a recording's filename (OEM dialers embed the phone
  /// number there), for matching against [phoneDigits]. Accepts either a
  /// bare display name or a full path — only the basename is considered.
  /// Public for the same testing reason as [phoneDigits].
  static String fileNameDigits(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.replaceAll(RegExp(r'\D'), '');
  }
}
