import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/call_recording_service.dart';

// CallRecordingService.phoneDigits/fileNameDigits are what let
// findLatestRecording prefer the recording whose filename actually matches
// the lead's phone number, instead of just grabbing the newest file in the
// dialer's folder — per the service's own doc comment, "the single biggest
// cause of a call attaching to the wrong lead". This pure matching logic had
// zero test coverage; findLatestRecording itself can't be unit tested since
// it scans real hardcoded device paths and is a no-op off Android.
void main() {
  group('CallRecordingService.phoneDigits', () {
    test('strips a +91 country code down to the local 10 digits', () {
      expect(CallRecordingService.phoneDigits('+919876543210'), '9876543210');
    });

    test('strips a bare 91 prefix down to the local 10 digits', () {
      expect(CallRecordingService.phoneDigits('919876543210'), '9876543210');
    });

    test('strips spaces, dashes, and parens', () {
      expect(CallRecordingService.phoneDigits('+91 98765-43210'), '9876543210');
      expect(CallRecordingService.phoneDigits('(98765) 43210'), '9876543210');
    });

    test('a bare 10-digit number passes through unchanged', () {
      expect(CallRecordingService.phoneDigits('9876543210'), '9876543210');
    });

    test('null and empty phone both produce an empty match string', () {
      expect(CallRecordingService.phoneDigits(null), '');
      expect(CallRecordingService.phoneDigits(''), '');
    });
  });

  group('CallRecordingService.fileNameDigits', () {
    test('extracts digits from a typical OEM recording filename, in order', () {
      // .wav deliberately — an .m4a/.mp3 extension itself contains a digit
      // ('4'/'3'), which would leak into the expected value below and muddy
      // what this test is actually checking.
      expect(
        CallRecordingService.fileNameDigits(
          '/storage/CallRecordings/Priya_9876543210_260820_1030.wav',
        ),
        '98765432102608201030',
      );
    });

    test(
      'extracts only the digits, in order, ignoring the rest of the name',
      () {
        expect(
          CallRecordingService.fileNameDigits('/a/b/Call_9876543210.wav'),
          '9876543210',
        );
      },
    );

    test('a filename with no digits produces an empty string', () {
      expect(CallRecordingService.fileNameDigits('/a/b/recording.wav'), '');
    });

    test('only the basename is considered, not the full path', () {
      // A digit-bearing parent folder must not leak into the match.
      expect(
        CallRecordingService.fileNameDigits(
          '/storage/9999999999/recording.wav',
        ),
        '',
      );
    });
  });

  group('phone-to-filename matching (the actual selection logic)', () {
    test('a filename embedding the lead\'s number matches via contains()', () {
      final digits = CallRecordingService.phoneDigits('+91 98765 43210');
      final fileDigits = CallRecordingService.fileNameDigits(
        '/x/Priya_9876543210_1030.m4a',
      );
      expect(fileDigits.contains(digits), isTrue);
    });

    test('a filename for a different number does not match', () {
      final digits = CallRecordingService.phoneDigits('+91 98765 43210');
      final fileDigits = CallRecordingService.fileNameDigits(
        '/x/Amit_9123456780_1030.m4a',
      );
      expect(fileDigits.contains(digits), isFalse);
    });
  });
}
