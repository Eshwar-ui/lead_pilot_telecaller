import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/call_recording_service.dart';
import 'package:lead_pilot_telecaller/src/services/recording_diagnostics.dart';

/// The Recording Check exists because "no recent recording found" covers at
/// least five unrelated causes, each with a different fix. Getting the verdict
/// wrong is worse than showing nothing: it sends a telecaller to toggle a
/// setting that was never the problem. These pin each cause to its own verdict.
///
/// `RecordingDiagnostics.run()` itself needs real Android folders, but the
/// classification it feeds is pure — that is the part worth testing.
RecordingDiagnosticsReport _report({
  bool platformSupported = true,
  StoragePermissionResult permission = StoragePermissionResult.granted,
  StorageAccessLevel access = StorageAccessLevel.mediaAudio,
  bool allFilesUnavailable = false,
  List<DirectoryProbe> dirs = const [],
  bool foundRecording = false,
}) {
  return RecordingDiagnosticsReport(
    platformSupported: platformSupported,
    permissionResult: permission,
    accessLevel: access,
    allFilesUnavailable: allFilesUnavailable,
    dirs: dirs,
    foundRecording: foundRecording,
  );
}

const _missingDir = DirectoryProbe(
  path: '/storage/emulated/0/MIUI/sound_recorder',
  exists: false,
  readable: false,
);
const _unreadableDir = DirectoryProbe(
  path: '/storage/emulated/0/Recordings/Call',
  exists: true,
  readable: false,
);
const _emptyDir = DirectoryProbe(
  path: '/storage/emulated/0/Recordings/Call',
  exists: true,
  readable: true,
  audioFiles: 0,
);
const _stockedDir = DirectoryProbe(
  path: '/storage/emulated/0/Recordings/Call',
  exists: true,
  readable: true,
  audioFiles: 12,
);

void main() {
  group('RecordingDiagnosticsReport.verdict', () {
    test('a located recording means capture is working', () {
      final report = _report(dirs: [_stockedDir], foundRecording: true);
      expect(report.verdict, RecordingVerdict.working);
      expect(report.outcome, 'found');
    });

    test('no permission is diagnosed before anything else', () {
      // Without access, every folder reads as missing — reporting "no folders"
      // would send the user to their dialer settings over a permission problem.
      final report = _report(
        permission: StoragePermissionResult.denied,
        access: StorageAccessLevel.none,
        dirs: [_missingDir],
      );
      expect(report.verdict, RecordingVerdict.permissionMissing);
      expect(report.outcome, 'permission_denied');
    });

    test('a permanently-denied permission reports as blocked', () {
      final report = _report(
        permission: StoragePermissionResult.permanentlyDenied,
        access: StorageAccessLevel.none,
      );
      expect(report.outcome, 'permission_blocked');
    });

    test('no folder at all means the dialer is not recording anywhere', () {
      final report = _report(dirs: [_missingDir, _missingDir]);
      expect(report.verdict, RecordingVerdict.noFolders);
      expect(report.action, contains('Record calls'));
      expect(report.action, contains('All files access'));
    });

    test(
      'a folder that exists but cannot be opened is an access problem',
      () {
        // The Samsung + Android 13 signature: the recordings are right there,
        // and the app is not allowed to look.
        final report = _report(dirs: [_missingDir, _unreadableDir]);
        expect(report.verdict, RecordingVerdict.foldersUnreadable);
      },
    );

    test('a readable but empty folder means auto-record is off', () {
      final report = _report(dirs: [_emptyDir]);
      expect(report.verdict, RecordingVerdict.foldersEmpty);
    });

    test(
      'recordings present but none returned is a matching problem, not a setup one',
      () {
        final report = _report(dirs: [_stockedDir]);
        expect(report.verdict, RecordingVerdict.recordingsNotMatched);
        expect(report.outcome, 'not_found');
      },
    );

    test('off-Android is unsupported, never a misdiagnosed setup failure', () {
      final report = _report(platformSupported: false);
      expect(report.verdict, RecordingVerdict.unsupported);
      expect(report.outcome, 'unsupported');
    });
  });

  group('advice', () {
    test(
      'only a REFUSED request blames the install rather than the user',
      () {
        final report = _report(
          dirs: [_unreadableDir],
          allFilesUnavailable: true,
        );
        expect(report.action, contains('Play Store'));
      },
    );

    test('by default the advice is to grant all-files access, not to give up', () {
      // The default path matters most: on a Xiaomi the recordings sit in a
      // .nomedia folder that audio permission cannot open, and granting
      // all-files access is the entire fix.
      final report = _report(
        dirs: [_unreadableDir],
        allFilesUnavailable: false,
      );
      expect(report.action, contains('All files access'));
      expect(report.action, isNot(contains('Play Store')));
    });

    test('an empty folder probe still points at the permission first', () {
      // A folder the app may not stat reads as absent, so "no folders" must not
      // send the user straight to their dialer settings.
      final report = _report(dirs: [_missingDir]);
      expect(report.verdict, RecordingVerdict.noFolders);
      expect(report.action, contains('All files access'));
    });
  });

  group('report payload', () {
    test('carries the counts support needs and no filenames', () {
      final json = _report(
        dirs: [_missingDir, _unreadableDir, _stockedDir],
      ).toJson();

      // Mixed state: one folder unreadable, another holding recordings. The
      // readable one wins the diagnosis — "cannot open a folder" is not the
      // blocker when audio was found elsewhere.
      expect(json['verdict'], 'recordingsNotMatched');
      expect(json['access_level'], 'media_audio');
      expect(json['dirs_existing'], 2);
      expect(json['dirs_readable'], 1);
      expect(json['audio_files_seen'], 12);
      // Absent folders are dropped: 20-odd "does not exist" rows from every
      // device would bury the two lines that matter.
      expect((json['dirs'] as List), hasLength(2));
      expect(json.toString(), isNot(contains('.m4a')));
    });

    test('a folder probe never carries a file name', () {
      // The backend table is documented PII-free, and OEM dialers put the
      // contact's name and number in recording filenames.
      const probe = DirectoryProbe(
        path: '/storage/emulated/0/Recordings/Call',
        exists: true,
        readable: true,
        audioFiles: 3,
        newestAudioAge: Duration(minutes: 4),
      );
      final json = probe.toJson();

      expect(json.keys, isNot(contains('newest_file')));
      expect(json['newest_audio_age_minutes'], 4);
      expect(json['audio_files'], 3);
    });
  });
}
