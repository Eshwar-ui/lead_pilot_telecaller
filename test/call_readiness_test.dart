import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/call_readiness.dart';
import 'package:lead_pilot_telecaller/src/services/call_recording_service.dart';

// A call is now hard-blocked when this phone could not record it. That makes
// this decision the difference between a telecaller working and a telecaller
// stuck, so both directions matter: letting a silent call through wastes the
// call, and blocking a capable phone stops the day.
//
// The deadlock these tests exist to pin down: "has a recording ever been
// found" would be unsatisfiable on a freshly issued phone — no recording can
// exist until a call is made, and no call could be made until one existed.
// Hence a granted folder always wins outright, whatever MediaStore says.
void main() {
  final hint = CallRecordingService.relativePathHints.first;

  Map<String, dynamic> row(String? relativePath) => {
    'relativePath': relativePath,
    'displayName': 'whatever.m4a',
    'dateModifiedMs': 0,
    'sizeBytes': 900000,
  };

  group('an explicit folder grant settles it', () {
    test('allows the call even with no audio visible anywhere', () {
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: false,
          hasFolderGrant: true,
          rows: const [],
        ),
        isNull,
      );
    });

    test('this is what breaks the fresh-phone deadlock', () {
      // Same phone, before and after the telecaller picks the folder.
      const before = <Map<String, dynamic>>[];
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: true,
          hasFolderGrant: false,
          rows: before,
        ),
        CallBlockReason.noRecordingsVisible,
      );
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: true,
          hasFolderGrant: true,
          rows: before,
        ),
        isNull,
      );
    });
  });

  group('permission', () {
    test('missing permission blocks before anything else is considered', () {
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: false,
          hasFolderGrant: false,
          rows: [row(hint)],
        ),
        CallBlockReason.permissionMissing,
      );
    });
  });

  group('what MediaStore can see', () {
    test('audio inside a known recording folder allows the call', () {
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: true,
          hasFolderGrant: false,
          rows: [row(hint)],
        ),
        isNull,
      );
    });

    test('audio only outside recording folders does not count', () {
      // Music and podcasts are audio too — they must not pass for a phone
      // whose dialer records nothing.
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: true,
          hasFolderGrant: false,
          rows: [row('Music/'), row('Download/')],
        ),
        CallBlockReason.noRecordingsVisible,
      );
    });

    test('one recording among unrelated audio is enough', () {
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: true,
          hasFolderGrant: false,
          rows: [row('Music/'), row(hint), row('Download/')],
        ),
        isNull,
      );
    });

    test('no audio at all blocks', () {
      expect(
        CallReadiness.decide(
          sdkInt: 34,
          permissionGranted: true,
          hasFolderGrant: false,
          rows: const [],
        ),
        CallBlockReason.noRecordingsVisible,
      );
    });
  });

  group('Android 9 and below', () {
    test('any audio passes, since MediaStore reports no folder to judge by', () {
      expect(
        CallReadiness.decide(
          sdkInt: 28,
          permissionGranted: true,
          hasFolderGrant: false,
          rows: [row(null)],
        ),
        isNull,
      );
    });

    test('but an empty phone still blocks', () {
      expect(
        CallReadiness.decide(
          sdkInt: 28,
          permissionGranted: true,
          hasFolderGrant: false,
          rows: const [],
        ),
        CallBlockReason.noRecordingsVisible,
      );
    });
  });
}
