import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/local_call_store.dart';

CallLogEntry entry({
  required String id,
  String leadId = 'lead1',
  String? callId,
  String? deviceCallId,
  int score = 0,
  Duration duration = Duration.zero,
  DateTime? at,
}) =>
    CallLogEntry(
      id: id,
      leadName: 'Priya',
      phone: '9990001111',
      intent: 'High Intent',
      source: LeadSource.meta,
      duration: duration,
      score: score,
      calledAt: at ?? DateTime(2026, 7, 15, 10, 30),
      leadId: leadId,
      callId: callId,
      deviceCallId: deviceCallId,
    );

void main() {
  group('mergeCallEntries', () {
    test('adds a brand-new call', () {
      final out = mergeCallEntries(const [], [entry(id: 'a')]);
      expect(out, hasLength(1));
    });

    test('fuses the optimistic (no call_id) entry with the confirmed backend '
        'entry for the same call — no duplicate', () {
      final optimistic = entry(id: 'a', at: DateTime(2026, 7, 15, 10, 30));
      final confirmed = entry(
        id: 'b',
        callId: 'C1',
        score: 82,
        duration: const Duration(minutes: 3),
        at: DateTime(2026, 7, 15, 10, 31), // ~same time, within window
      );
      final out = mergeCallEntries([optimistic], [confirmed]);
      expect(out, hasLength(1), reason: 'must not duplicate the same call');
      expect(out.single.callId, 'C1');
      expect(out.single.score, 82);
      expect(out.single.duration, const Duration(minutes: 3));
    });

    test('does NOT fuse two different calls to the same lead far apart in time', () {
      final morning = entry(id: 'a', at: DateTime(2026, 7, 15, 9, 0));
      final evening = entry(id: 'b', callId: 'C2', at: DateTime(2026, 7, 15, 18, 0));
      final out = mergeCallEntries([morning], [evening]);
      expect(out, hasLength(2));
    });

    test('de-dupes by call_id regardless of timestamp skew', () {
      final a = entry(id: 'a', callId: 'C3', at: DateTime(2026, 7, 15, 10, 30));
      // same call_id, wildly different time (e.g. a tz-skewed copy)
      final b = entry(id: 'b', callId: 'C3', score: 90, at: DateTime(2026, 7, 15, 16, 0));
      final out = mergeCallEntries([a], [b]);
      expect(out, hasLength(1));
      expect(out.single.score, 90);
    });

    test('returns the same instance when nothing changed (skip persist)', () {
      final existing = [entry(id: 'a', callId: 'C1', score: 82)];
      // Re-ingesting an equal-or-poorer copy should be a no-op.
      final out = mergeCallEntries(existing, [entry(id: 'b', callId: 'C1', score: 50)]);
      expect(identical(out, existing), isTrue);
    });

    test('different leads never fuse', () {
      final a = entry(id: 'a', leadId: 'lead1');
      final b = entry(id: 'b', leadId: 'lead2');
      final out = mergeCallEntries([a], [b]);
      expect(out, hasLength(2));
    });

    test('re-syncing the same device call log entry upserts, not duplicates', () {
      final first = entry(id: 'a', deviceCallId: 'dev1', duration: const Duration(seconds: 10));
      final resynced = entry(id: 'b', deviceCallId: 'dev1', duration: const Duration(seconds: 45));
      final out = mergeCallEntries([first], [resynced]);
      expect(out, hasLength(1));
      expect(out.single.duration, const Duration(seconds: 45));
    });

    test('two different device calls to the same lead within the merge window '
        'stay distinct when both carry a device id', () {
      final a = entry(id: 'a', deviceCallId: 'dev1', at: DateTime(2026, 7, 15, 10, 30));
      final b = entry(id: 'b', deviceCallId: 'dev2', at: DateTime(2026, 7, 15, 10, 31));
      final out = mergeCallEntries([a], [b]);
      expect(out, hasLength(2), reason: 'distinct device ids must never fuse');
    });
  });
}
