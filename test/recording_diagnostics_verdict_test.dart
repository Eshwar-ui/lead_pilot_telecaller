import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/call_recording_service.dart';
import 'package:lead_pilot_telecaller/src/services/recording_diagnostics.dart';

/// The Recording Check exists because "no recent recording found" covers
/// several unrelated causes, each with a different fix. Getting the verdict
/// wrong is worse than showing nothing: it sends a telecaller to toggle a
/// setting that was never the problem. These pin each cause to its own verdict.
///
/// `RecordingDiagnostics.run()` itself needs a real device (it queries
/// MediaStore over a platform channel), but the classification it feeds is
/// pure — that is the part worth testing.
RecordingDiagnosticsReport _report({
  bool platformSupported = true,
  StoragePermissionResult permission = StoragePermissionResult.granted,
  StorageAccessLevel access = StorageAccessLevel.mediaAudio,
  List<DirectoryProbe> dirs = const [],
  int audioFilesSeen = 0,
  bool foundRecording = false,
}) {
  return RecordingDiagnosticsReport(
    platformSupported: platformSupported,
    permissionResult: permission,
    accessLevel: access,
    dirs: dirs,
    audioFilesSeen: audioFilesSeen,
    foundRecording: foundRecording,
  );
}

const _emptyDir = DirectoryProbe(path: '/storage/emulated/0/Recordings/Call');
const _stockedDir = DirectoryProbe(
  path: '/storage/emulated/0/Recordings/Call',
  audioFiles: 12,
);

void main() {
  group('RecordingDiagnosticsReport.verdict', () {
    test('a located recording means capture is working', () {
      final report = _report(
        dirs: [_stockedDir],
        audioFilesSeen: 12,
        foundRecording: true,
      );
      expect(report.verdict, RecordingVerdict.working);
      expect(report.outcome, 'found');
    });

    test('no permission is diagnosed before anything else', () {
      // Without access, MediaStore was never even queried — reporting "no
      // folders" would send the user to their dialer settings over a
      // permission problem.
      final report = _report(
        permission: StoragePermissionResult.denied,
        access: StorageAccessLevel.none,
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

    test(
      'granted access with nothing found anywhere means no recordings exist',
      () {
        final report = _report(dirs: [_emptyDir], audioFilesSeen: 0);
        expect(report.verdict, RecordingVerdict.noFolders);
        expect(report.action, contains('Record calls'));
      },
    );

    test(
      'recordings present but none returned is a matching problem, not a setup one',
      () {
        final report = _report(dirs: [_stockedDir], audioFilesSeen: 12);
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

  group('report payload', () {
    test('carries the counts support needs and no filenames', () {
      const emptyOtherDir = DirectoryProbe(
        path: '/storage/emulated/0/MIUI/sound_recorder',
      );
      final json = _report(
        dirs: [emptyOtherDir, _stockedDir],
        audioFilesSeen: 12,
      ).toJson();

      expect(json['verdict'], 'recordingsNotMatched');
      expect(json['access_level'], 'media_audio');
      expect(json['audio_files_seen'], 12);
      // Folders holding nothing are dropped: 20-odd zero rows from every
      // device would bury the one line that matters.
      expect((json['dirs'] as List), hasLength(1));
      expect(json.toString(), isNot(contains('.m4a')));
    });

    test('a folder probe never carries a file name', () {
      const probe = DirectoryProbe(
        path: '/storage/emulated/0/Recordings/Call',
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
