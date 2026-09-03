import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/call_recording_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pins the permission decision behind auto-capture — the reason recordings
/// stopped being detected on Samsung and other Android 13+ handsets.
///
/// The old flow REQUESTED `MANAGE_EXTERNAL_STORAGE` first and treated its
/// refusal as fatal. On Android 13+ that permission is withheld from apps
/// installed outside the Play Store (Restricted Settings), and the fallback —
/// `READ_EXTERNAL_STORAGE` — is itself capped at maxSdkVersion 32 in the
/// manifest. So capture dead-ended on every modern phone with a message
/// telling the user to enable a Settings toggle that is greyed out.
///
/// `decideAccess` is the whole decision as a pure function, so these run
/// without a device.
void main() {
  group('CallRecordingService.decideAccess — Android 13+', () {
    test(
      'audio permission alone is enough to scan, even with all-files refused',
      () {
        // The regression that broke Samsung: this case used to be "denied".
        final outcome = CallRecordingService.decideAccess(
          sdkInt: 34,
          allFiles: PermissionStatus.permanentlyDenied,
          mediaAudio: PermissionStatus.granted,
          legacyStorage: PermissionStatus.denied,
        );

        expect(outcome.result, StoragePermissionResult.granted);
        expect(outcome.level, StorageAccessLevel.mediaAudio);
      },
    );

    test('all-files access, when actually held, wins and reports full reach', () {
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 34,
        allFiles: PermissionStatus.granted,
        mediaAudio: PermissionStatus.denied,
        legacyStorage: PermissionStatus.denied,
      );

      expect(outcome.result, StoragePermissionResult.granted);
      expect(outcome.level, StorageAccessLevel.allFiles);
    });

    test('refusing the audio permission is denied, and retryable', () {
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 34,
        allFiles: PermissionStatus.denied,
        mediaAudio: PermissionStatus.denied,
        legacyStorage: PermissionStatus.denied,
      );

      expect(outcome.result, StoragePermissionResult.denied);
      expect(outcome.level, StorageAccessLevel.none);
    });

    test(
      'only the permission we actually asked for can send the user to Settings',
      () {
        // All-files access being unavailable must NOT read as "permanently
        // denied": that routed the user to an ungrantable toggle. Blocked is
        // reserved for the audio permission, which Settings really can fix.
        final allFilesRefused = CallRecordingService.decideAccess(
          sdkInt: 34,
          allFiles: PermissionStatus.permanentlyDenied,
          mediaAudio: PermissionStatus.denied,
          legacyStorage: PermissionStatus.denied,
        );
        expect(allFilesRefused.result, StoragePermissionResult.denied);

        final audioBlocked = CallRecordingService.decideAccess(
          sdkInt: 34,
          allFiles: PermissionStatus.permanentlyDenied,
          mediaAudio: PermissionStatus.permanentlyDenied,
          legacyStorage: PermissionStatus.denied,
        );
        expect(audioBlocked.result, StoragePermissionResult.permanentlyDenied);
      },
    );

    test(
      'does NOT assume all-files access is unavailable just because of the OS',
      () {
        // Measured on real hardware: a sideloaded app on a Xiaomi running
        // Android 16 (API 36) gets a perfectly usable "Allow access to manage
        // all files" toggle. Inferring "blocked" from the API level hid the one
        // button that fixes that phone, whose dialer writes recordings to a
        // .nomedia folder that audio permission alone cannot open.
        final outcome = CallRecordingService.decideAccess(
          sdkInt: 36,
          allFiles: PermissionStatus.denied,
          mediaAudio: PermissionStatus.granted,
          legacyStorage: PermissionStatus.denied,
        );

        expect(outcome.allFilesUnavailable, isFalse);
      },
    );

    test('reports it unavailable only after a request actually came back refused', () {
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 34,
        allFiles: PermissionStatus.denied,
        mediaAudio: PermissionStatus.granted,
        legacyStorage: PermissionStatus.denied,
        allFilesRefused: true,
      );

      expect(outcome.allFilesUnavailable, isTrue);
    });
  });

  group('CallRecordingService.decideAccess — Android 12 and below', () {
    test('the legacy storage permission still grants access', () {
      final outcome = CallRecordingService.decideAccess(
        sdkInt: 30,
        allFiles: PermissionStatus.denied,
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
        allFiles: PermissionStatus.denied,
        mediaAudio: PermissionStatus.granted,
        legacyStorage: PermissionStatus.denied,
      );

      expect(outcome.result, StoragePermissionResult.denied);
    });

    test(
      'all-files access is still worth offering — Settings allows it here',
      () {
        final outcome = CallRecordingService.decideAccess(
          sdkInt: 30,
          allFiles: PermissionStatus.denied,
          mediaAudio: PermissionStatus.denied,
          legacyStorage: PermissionStatus.granted,
        );

        expect(outcome.allFilesUnavailable, isFalse);
      },
    );

    test(
      'an unknown SDK level falls back to the legacy branch, not to nothing',
      () {
        // androidSdkInt() returns 0 if device_info_plus fails. Requesting the
        // legacy permission on a modern phone is a harmless no-op; requesting
        // nothing would make capture impossible.
        final outcome = CallRecordingService.decideAccess(
          sdkInt: 0,
          allFiles: PermissionStatus.denied,
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
      expect(StorageAccessLevel.allFiles.wireName, 'all_files');
      expect(StorageAccessLevel.mediaAudio.wireName, 'media_audio');
      expect(StorageAccessLevel.legacy.wireName, 'legacy');
      expect(StorageAccessLevel.none.wireName, 'none');
    });
  });
}
