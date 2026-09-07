import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/call_recording_service.dart';
import 'package:lead_pilot_telecaller/src/services/device_contact_service.dart';

/// Contact-write outcomes and the recording-availability flag.
///
/// The contacts plugin itself needs a real device (it talks to the platform
/// contacts provider), so what's covered here is the logic that decides
/// WHETHER to write and what the telecaller gets told — plus the number
/// normalisation the dedupe depends on, which is the part that would silently
/// create duplicate contact cards if it drifted.
void main() {
  group('contact-save outcomes', () {
    test('only permission-denied and failure are surfaced to the user', () {
      // Success is silent: the telecaller asked to save a LEAD, not to be
      // told about their address book.
      expect(ContactSaveOutcome.created.isNoteworthy, isFalse);
      expect(ContactSaveOutcome.updated.isNoteworthy, isFalse);
      expect(ContactSaveOutcome.unchanged.isNoteworthy, isFalse);
      expect(ContactSaveOutcome.invalidNumber.isNoteworthy, isFalse);

      expect(ContactSaveOutcome.permissionDenied.isNoteworthy, isTrue);
      expect(ContactSaveOutcome.failed.isNoteworthy, isTrue);
    });

    test('every noteworthy outcome has a message to show', () {
      for (final o in ContactSaveOutcome.values.where((o) => o.isNoteworthy)) {
        expect(o.message, isNotNull, reason: '$o is shown but has no message');
        expect(o.message, isNotEmpty);
      }
    });

    test('the messages make clear the LEAD was still saved', () {
      // The failure mode this guards: a contacts error reading as "your lead
      // did not save", when the lead is already persisted server-side.
      for (final o in ContactSaveOutcome.values.where((o) => o.isNoteworthy)) {
        expect(o.message!.toLowerCase(), contains('lead saved'));
      }
    });

    test('silent outcomes carry no message', () {
      for (final o in ContactSaveOutcome.values.where((o) => !o.isNoteworthy)) {
        expect(o.message, isNull);
      }
    });
  });

  group('dedupe number normalisation', () {
    // The contact write dedupes on this, so these three must collapse to one
    // key or re-saving a lead spawns a second contact card.
    test('country code and spacing forms collapse to one key', () {
      const key = '9876543210';
      expect(CallRecordingService.phoneDigits('+91 98765 43210'), key);
      expect(CallRecordingService.phoneDigits('098765 43210'), key);
      expect(CallRecordingService.phoneDigits('9876543210'), key);
      expect(CallRecordingService.phoneDigits('+919876543210'), key);
    });

    test('different numbers do not collapse', () {
      expect(
        CallRecordingService.phoneDigits('9876543210'),
        isNot(CallRecordingService.phoneDigits('9876543211')),
      );
    });

    test('short numbers stay short so the 10-digit floor rejects them', () {
      // Below 10 digits is a short code or a typo — no contact card should be
      // created for one.
      expect(CallRecordingService.phoneDigits('12345').length, lessThan(10));
      expect(CallRecordingService.phoneDigits('').length, lessThan(10));
    });
  });

  group('recording availability', () {
    test('CallLogEntry defaults hasAudio to false', () {
      // A locally-logged call that has not been uploaded has nothing to play;
      // defaulting true would render a dead play button.
      final entry = CallLogEntry.fromJson({
        'id': 'c1',
        'phone': '9876543210',
        'called_at': '2026-09-05T10:00:00Z',
      });

      expect(entry.hasAudio, isFalse);
    });

    test('CallLogEntry parses has_audio and survives a round trip', () {
      final entry = CallLogEntry.fromJson({
        'id': 'c1',
        'phone': '9876543210',
        'called_at': '2026-09-05T10:00:00Z',
        'has_audio': true,
      });

      expect(entry.hasAudio, isTrue);
      expect(CallLogEntry.fromJson(entry.toJson()).hasAudio, isTrue);
    });

    test('CallLogEntry.copyWith preserves hasAudio when not overridden', () {
      final entry = CallLogEntry.fromJson({
        'id': 'c1',
        'phone': '9876543210',
        'called_at': '2026-09-05T10:00:00Z',
        'has_audio': true,
      });

      expect(entry.copyWith(score: 90).hasAudio, isTrue);
      expect(entry.copyWith(hasAudio: false).hasAudio, isFalse);
    });

    test('CallRecord parses has_audio, defaulting to false', () {
      expect(
        CallRecord.fromJson({'title': 'x', 'has_audio': true}).hasAudio,
        isTrue,
      );
      expect(CallRecord.fromJson({'title': 'x'}).hasAudio, isFalse);
    });

    test('hasAudio is independent of callId', () {
      // The distinction the flag exists for: a call CAN be analysed (so it has
      // a call_id) while carrying no reachable recording.
      final analysedNoAudio = CallRecord.fromJson({
        'title': 'x',
        'call_id': 'call_1',
      });

      expect(analysedNoAudio.callId, isNotNull);
      expect(analysedNoAudio.hasAudio, isFalse);
    });
  });
}
