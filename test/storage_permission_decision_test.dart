import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/call_recording_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pins the permission decision behind auto-capture — the reason recordings
/// stopped being detected on Samsung and other Android 13+ handsets, and now
/// the whole basis for the MediaStore-based scan (no more
/// `MANAGE_EXTERNAL_STORAGE` — Google Play rejected that declaration).
///
/// `decideAccess` is the whole decision as a pure function, so these run
/// without a device.
void main() {
  group('CallRecordingService.decideAccess — Android 13+', () {
    test('the audio permission grants media-audio access', () {
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 34,
        mediaAudio: PermissionStatus.granted,
        legacyStorage: PermissionStatus.denied,
      );

      expect(outcome.result, StoragePermissionResult.granted);
      expect(outcome.level, StorageAccessLevel.mediaAudio);
    });

    test('refusing the audio permission is denied, and retryable', () {
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 34,
        mediaAudio: PermissionStatus.denied,
        legacyStorage: PermissionStatus.denied,
      );

      expect(outcome.result, StoragePermissionResult.denied);
      expect(outcome.level, StorageAccessLevel.none);
    });

    test(
      'a permanently-denied audio permission sends the user to Settings',
      () {
        final outcome = CallRecordingService.decideAccess(
          sdkInt: 34,
          mediaAudio: PermissionStatus.permanentlyDenied,
          legacyStorage: PermissionStatus.denied,
        );

        expect(outcome.result, StoragePermissionResult.permanentlyDenied);
      },
    );
  });

  group('CallRecordingService.decideAccess — Android 12 and below', () {
    test('the legacy storage permission still grants access', () {
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 30,
        mediaAudio: PermissionStatus.denied,
        legacyStorage: PermissionStatus.granted,
      );

      expect(outcome.result, StoragePermissionResult.granted);
      expect(outcome.level, StorageAccessLevel.legacy);
    });

    test('a granted audio permission is ignored below 33', () {
      // READ_MEDIA_AUDIO does not exist before Android 13; trusting it there
      // would report access the app does not have.
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 30,
        mediaAudio: PermissionStatus.granted,
        legacyStorage: PermissionStatus.denied,
      );

      expect(outcome.result, StoragePermissionResult.denied);
    });

    test(
      'an unknown SDK level falls back to the legacy branch, not to nothing',
      () {
        // androidSdkInt() returns 0 if device_info_plus fails. Requesting the
        // legacy permission on a modern phone is a harmless no-op; requesting
        // nothing would make capture impossible.
        final outcome = CallRecordingService.decideAccess(
          sdkInt: 0,
          mediaAudio: PermissionStatus.denied,
          legacyStorage: PermissionStatus.granted,
        );

        expect(outcome.result, StoragePermissionResult.granted);
        expect(outcome.level, StorageAccessLevel.legacy);
      },
    );
  });

  group('StorageAccessLevel.wireName', () {
    test('matches the backend CaptureAccessLevel vocabulary', () {
      // Drift here silently 422s every telemetry report, and telemetry is
      // fire-and-forget — nothing would surface the break.
      expect(StorageAccessLevel.mediaAudio.wireName, 'media_audio');
      expect(StorageAccessLevel.legacy.wireName, 'legacy');
      expect(StorageAccessLevel.none.wireName, 'none');
    });
  });

  group('CallRecordingService.relativePathHints', () {
    test('strips the storage-volume prefix and adds a trailing slash', () {
      final hints = CallRecordingService.relativePathHints;

      expect(hints, isNotEmpty);
      expect(
        hints,
        contains('MIUI/sound_recorder/call_rec/'),
        reason:
            '/storage/emulated/0/MIUI/sound_recorder/call_rec must map to '
            'this MediaStore RELATIVE_PATH fragment',
      );
      for (final hint in hints) {
        expect(hint, isNot(startsWith('/')));
        expect(hint, endsWith('/'));
      }
    });

    test('every candidate folder produces exactly one hint', () {
      expect(
        CallRecordingService.relativePathHints.length,
        CallRecordingService.candidateDirs.length,
      );
    });
  });

  group('CallRecordingService.selectBestMatch', () {
    Map<String, dynamic> row({
      required String contentUri,
      required String displayName,
      required int dateModifiedMs,
      int sizeBytes = 100000,
    }) => {
      'contentUri': contentUri,
      'displayName': displayName,
      'dateModifiedMs': dateModifiedMs,
      'sizeBytes': sizeBytes,
    };

    final now = DateTime(2026, 1, 1, 12);

    test('a phone-matched row wins over a merely-newer unmatched row', () {
      final rows = [
        row(
          contentUri: 'content://a',
          displayName: 'Amit_9123456780.m4a',
          dateModifiedMs: now.millisecondsSinceEpoch,
        ),
        row(
          contentUri: 'content://b',
          displayName: 'Priya_9876543210.m4a',
          dateModifiedMs: now
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        ),
      ];

      final chosen = CallRecordingService.selectBestMatch(
        rows,
        phoneHint: '+91 98765 43210',
        within: const Duration(minutes: 30),
        now: now,
      );

      expect(chosen?['contentUri'], 'content://b');
    });

    test('falls back to newest-in-window with no filename match', () {
      final rows = [
        row(
          contentUri: 'content://old',
          displayName: 'recording.m4a',
          dateModifiedMs: now
              .subtract(const Duration(minutes: 20))
              .millisecondsSinceEpoch,
        ),
        row(
          contentUri: 'content://new',
          displayName: 'recording2.m4a',
          dateModifiedMs: now
              .subtract(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
        ),
      ];

      final chosen = CallRecordingService.selectBestMatch(
        rows,
        phoneHint: '9876543210',
        within: const Duration(minutes: 30),
        now: now,
      );

      expect(chosen?['contentUri'], 'content://new');
    });

    test('a row outside the recency window is excluded', () {
      final rows = [
        row(
          contentUri: 'content://too-old',
          displayName: 'recording.m4a',
          dateModifiedMs: now
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        ),
      ];

      final chosen = CallRecordingService.selectBestMatch(
        rows,
        phoneHint: null,
        within: const Duration(minutes: 30),
        now: now,
      );

      expect(chosen, isNull);
    });

    test('a placeholder file under the size floor is excluded', () {
      final rows = [
        row(
          contentUri: 'content://placeholder',
          displayName: 'recording.m4a',
          dateModifiedMs: now.millisecondsSinceEpoch,
          sizeBytes: 100,
        ),
      ];

      final chosen = CallRecordingService.selectBestMatch(
        rows,
        phoneHint: null,
        within: const Duration(minutes: 30),
        now: now,
      );

      expect(chosen, isNull);
    });

    test('within: null ignores recency entirely', () {
      final rows = [
        row(
          contentUri: 'content://ancient',
          displayName: 'recording.m4a',
          dateModifiedMs: now
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
        ),
      ];

      final chosen = CallRecordingService.selectBestMatch(
        rows,
        phoneHint: null,
        within: null,
        now: now,
      );

      expect(chosen?['contentUri'], 'content://ancient');
    });

    test('an empty row list has no match', () {
      expect(
        CallRecordingService.selectBestMatch(
          const [],
          phoneHint: '9876543210',
          within: const Duration(minutes: 30),
          now: now,
        ),
        isNull,
      );
    });
  });
}
