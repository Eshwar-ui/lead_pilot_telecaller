import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';

/// Parsing for the two fields Phase 2 added to lead detail: the customer flag
/// (`client_since`) and the newest analysed call (`latest_call`).
///
/// Both are OPTIONAL on the wire — an older backend, a lead with no calls, or
/// a contact with no Lead row all omit them — so the defaults matter as much
/// as the happy path.
void main() {
  Map<String, dynamic> baseJson() => {
    'id': '9000000001',
    'name': 'Anjali Rao',
    'phone': '9000000001',
    'score': 82,
  };

  group('customer flag', () {
    test('is false and undated when the backend omits it', () {
      final lead = Lead.fromJson(baseJson());

      expect(lead.isClient, isFalse);
      expect(lead.clientSince, isNull);
    });

    test('parses is_client and client_since', () {
      final lead = Lead.fromJson({
        ...baseJson(),
        'is_client': true,
        'client_since': '2026-08-30T10:15:00Z',
      });

      expect(lead.isClient, isTrue);
      expect(lead.clientSince, DateTime.utc(2026, 8, 30, 10, 15));
    });

    test('a missing client_since does NOT fall back to the epoch', () {
      // The generic date parser returns 1970 for absent values; that would
      // render as "Client since 1 Jan 1970" on screen.
      final lead = Lead.fromJson({...baseJson(), 'is_client': true});

      expect(lead.isClient, isTrue);
      expect(lead.clientSince, isNull);
    });

    test('copyWithClient clears the date when unmarking', () {
      final lead = Lead.fromJson({
        ...baseJson(),
        'is_client': true,
        'client_since': '2026-08-30T10:15:00Z',
      });

      final cleared = lead.copyWithClient(isClient: false);

      expect(cleared.isClient, isFalse);
      expect(cleared.clientSince, isNull);
      // Everything else survives the narrow copy.
      expect(cleared.name, 'Anjali Rao');
      expect(cleared.score, 82);
    });

    test('copyWithClient keeps unrelated fields including latestCall', () {
      final lead = Lead.fromJson({
        ...baseJson(),
        'latest_call': {'call_id': 'call_1', 'has_audio': true},
      });

      final marked = lead.copyWithClient(
        isClient: true,
        clientSince: DateTime.utc(2026, 9, 1),
      );

      expect(marked.isClient, isTrue);
      expect(marked.latestCall?.callId, 'call_1');
    });
  });

  group('latest call', () {
    test('is null when the lead has no analysed call', () {
      expect(Lead.fromJson(baseJson()).latestCall, isNull);
    });

    test('parses the full block', () {
      final lead = Lead.fromJson({
        ...baseJson(),
        'latest_call': {
          'call_id': 'call_9000000001_ab12cd34',
          'timestamp': '2026-09-04T14:30:00Z',
          'has_audio': true,
          'duration_label': '06:12',
          'capture_source': 'auto_detected_realtime',
          'score': 82.6,
          'lead_verdict': 'Warm',
          'sentiment_label': 'positive',
          'headline': 'Asked for pricing',
          'key_points': ['Wants EMI', 'Comparing clinics'],
          'call_summary': {
            'objections_raised': ['Price too high'],
            'commitments_made': ['Will confirm Friday'],
          },
          'next_steps': [
            {'step': 1, 'text': 'Send the quote'},
            {'step': 2, 'action_label': 'Follow up Friday'},
          ],
        },
      });

      final call = lead.latestCall!;
      expect(call.callId, 'call_9000000001_ab12cd34');
      expect(call.hasAudio, isTrue);
      expect(call.durationLabel, '06:12');
      // A fractional BANT score rounds rather than truncating.
      expect(call.score, 83);
      expect(call.leadVerdict, 'Warm');
      expect(call.keyPoints, ['Wants EMI', 'Comparing clinics']);
      expect(call.objectionsRaised, ['Price too high']);
      expect(call.commitmentsMade, ['Will confirm Friday']);
      // next_steps are objects; the screen only needs their text, and an entry
      // carrying only action_label must not be dropped.
      expect(call.nextSteps, ['Send the quote', 'Follow up Friday']);
      expect(call.autoCaptured, isTrue);
    });

    test('defaults every list and flag when the block is sparse', () {
      final lead = Lead.fromJson({
        ...baseJson(),
        'latest_call': {'call_id': 'call_1'},
      });

      final call = lead.latestCall!;
      expect(call.hasAudio, isFalse);
      expect(call.keyPoints, isEmpty);
      expect(call.objectionsRaised, isEmpty);
      expect(call.commitmentsMade, isEmpty);
      expect(call.nextSteps, isEmpty);
      expect(call.durationLabel, isNull);
      expect(call.timestamp, isNull);
      expect(call.autoCaptured, isFalse);
    });

    test('autoCaptured is false for an app-placed call', () {
      final lead = Lead.fromJson({
        ...baseJson(),
        'latest_call': {'call_id': 'call_1', 'capture_source': 'app_call'},
      });

      expect(lead.latestCall!.autoCaptured, isFalse);
    });

    test('survives a round trip through toJson', () {
      final original = Lead.fromJson({
        ...baseJson(),
        'is_client': true,
        'client_since': '2026-08-30T10:15:00Z',
        'latest_call': {
          'call_id': 'call_1',
          'has_audio': true,
          'key_points': ['a'],
          'call_summary': {
            'objections_raised': ['o'],
            'commitments_made': ['c'],
          },
          'next_steps': [
            {'text': 'n'},
          ],
        },
      });

      final restored = Lead.fromJson(original.toJson());

      expect(restored.isClient, isTrue);
      expect(restored.clientSince, original.clientSince);
      expect(restored.latestCall?.callId, 'call_1');
      expect(restored.latestCall?.hasAudio, isTrue);
      expect(restored.latestCall?.keyPoints, ['a']);
      expect(restored.latestCall?.objectionsRaised, ['o']);
      expect(restored.latestCall?.commitmentsMade, ['c']);
      expect(restored.latestCall?.nextSteps, ['n']);
    });
  });
}
