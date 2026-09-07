import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/local_call_store.dart';
import 'package:lead_pilot_telecaller/src/services/local_database.dart';
import 'package:lead_pilot_telecaller/src/services/local_transcript_store.dart';
import 'package:lead_pilot_telecaller/src/services/transcription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

// The call log and transcripts moved from SharedPreferences to SQLite. Every
// existing install has real history sitting in the old storage, and it is
// carried over exactly once, on first open. Getting this wrong loses a
// telecaller's entire call history silently — there is no server copy of the
// local-only entries — so the migration is covered from both directions:
// that everything arrives, and that nothing is left behind to be re-imported
// or to keep occupying memory.
void main() {
  useInMemoryDatabase();

  CallLogEntry entry(String id, DateTime at, {String? leadId, int score = 0}) =>
      CallLogEntry(
        id: id,
        leadName: 'Priya',
        phone: '+919876543210',
        intent: 'High Intent',
        source: LeadSource.organic,
        duration: const Duration(minutes: 3),
        score: score,
        calledAt: at,
        leadId: leadId,
      );

  group('call log', () {
    test('every legacy call is carried across, newest first', () async {
      final calls = [
        entry('a', DateTime(2026, 9, 1), leadId: 'lead-1'),
        entry('b', DateTime(2026, 9, 5), leadId: 'lead-2'),
        entry('c', DateTime(2026, 9, 3)),
      ];
      SharedPreferences.setMockInitialValues({
        AppDatabase.legacyCallsKey: jsonEncode([
          for (final c in calls) c.toJson(),
        ]),
      });

      final restored = await LocalCallStore().page(limit: 1000);

      expect(restored.map((e) => e.id), ['b', 'c', 'a']);
      expect(restored.first.leadId, 'lead-2');
      expect(restored.first.calledAt, DateTime(2026, 9, 5));
    });

    test('the legacy key is cleared, so it stops occupying memory', () async {
      SharedPreferences.setMockInitialValues({
        AppDatabase.legacyCallsKey: jsonEncode([
          entry('a', DateTime(2026, 9, 1)).toJson(),
        ]),
      });

      await LocalCallStore().page(limit: 1000);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppDatabase.legacyCallsKey), isNull);
    });

    test('a corrupt legacy blob is dropped, not retried forever', () async {
      // The old loadAll caught its own decode errors and returned empty, so
      // this data was already unreadable; what matters is that it does not
      // wedge every future launch.
      SharedPreferences.setMockInitialValues({
        AppDatabase.legacyCallsKey: 'not json at all',
      });

      expect(await LocalCallStore().page(limit: 1000), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppDatabase.legacyCallsKey), isNull);
    });

    test('concurrent first readers all see migrated rows', () async {
      // At startup the call list and the summary tiles both reach for the
      // database at once. If the connection is published before the migration
      // finishes, whichever arrives second takes the already-open fast path
      // and reads an empty table — the call log silently appearing as zero.
      SharedPreferences.setMockInitialValues({
        AppDatabase.legacyCallsKey: jsonEncode([
          entry('a', DateTime(2026, 9, 1)).toJson(),
          entry('b', DateTime(2026, 9, 2)).toJson(),
        ]),
      });
      final store = LocalCallStore();

      final results = await Future.wait([
        store.page(limit: 1000),
        store.page(limit: 1000),
        store.stats(),
      ]);

      expect((results[0] as List).length, 2);
      expect((results[1] as List).length, 2);
      expect((results[2] as CallLogStats).total, 2);
    });

    test('no legacy data is not an error', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await LocalCallStore().page(limit: 1000), isEmpty);
    });
  });

  group('transcripts', () {
    test('each per-lead key becomes a row, readable by lead', () async {
      SharedPreferences.setMockInitialValues({
        '${AppDatabase.legacyTranscriptPrefix}lead-1': jsonEncode({
          'callId': 'call-1',
          'transcript': 'Namaskaram',
          'entries': <Object>[],
        }),
        '${AppDatabase.legacyTranscriptPrefix}lead-2': jsonEncode({
          'callId': 'call-2',
          'transcript': 'Second call',
          'entries': <Object>[],
        }),
        'unrelated_setting': 'left alone',
      });

      final store = LocalTranscriptStore();
      expect((await store.load('lead-1'))?.callId, 'call-1');
      expect((await store.load('lead-2'))?.transcript, 'Second call');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('transcript_v1_')), isEmpty);
      expect(
        prefs.getString('unrelated_setting'),
        'left alone',
        reason: 'the migration must only touch the keys it owns',
      );
    });

    test('a lead with no transcript reads null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await LocalTranscriptStore().load('nobody'), isNull);
    });
  });

  group('logout', () {
    test('clears calls and transcripts, as prefs.clear() used to', () async {
      // These lived in SharedPreferences, which logout wipes wholesale.
      // Moving them to SQLite put them outside that wipe — leaving one
      // telecaller's call history, and the words spoken on those calls, for
      // whoever signs in next on the same phone.
      SharedPreferences.setMockInitialValues({});
      final calls = LocalCallStore();
      final transcripts = LocalTranscriptStore();
      await calls.upsertAll([entry('a', DateTime(2026, 9, 1))]);
      await transcripts.save(
        'lead-1',
        const CallTranscription(transcript: 'private', entries: []),
      );

      await AppDatabase.instance.clearAll();

      expect(await calls.page(limit: 1000), isEmpty);
      expect(await transcripts.load('lead-1'), isNull);
    });
  });

  group('ordinary writes', () {
    test('upsert replaces a call rather than duplicating it', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalCallStore();

      await store.upsertAll([entry('a', DateTime(2026, 9, 1))]);
      await store.upsertAll([entry('a', DateTime(2026, 9, 1), score: 82)]);

      final restored = await store.page(limit: 1000);
      expect(restored, hasLength(1));
      expect(restored.single.score, 82);
    });

    test('writing one call leaves the others untouched', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalCallStore();
      await store.upsertAll([
        entry('a', DateTime(2026, 9, 1)),
        entry('b', DateTime(2026, 9, 2)),
      ]);

      await store.upsertAll([entry('b', DateTime(2026, 9, 2), score: 70)]);

      final restored = await store.page(limit: 1000);
      expect(restored.map((e) => e.id), ['b', 'a']);
      expect(restored.firstWhere((e) => e.id == 'a').score, 0);
    });

    test('an empty write is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalCallStore();
      await store.upsertAll([entry('a', DateTime(2026, 9, 1))]);
      await store.upsertAll(const []);
      expect(await store.page(limit: 1000), hasLength(1));
    });

    test('a transcript save overwrites the previous one for that lead', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalTranscriptStore();

      await store.save(
        'lead-1',
        const CallTranscription(transcript: 'first', entries: []),
      );
      await store.save(
        'lead-1',
        const CallTranscription(transcript: 'second', entries: []),
      );

      expect((await store.load('lead-1'))?.transcript, 'second');
    });
  });
}
