import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/local_call_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

// The call log is a paged window now, not the whole history in memory. That
// moved every summary tile onto SQL — and those tiles are what a founder
// manages telecallers by, so a Dart-vs-SQL discrepancy would silently
// misreport someone's month. Each aggregate below is therefore checked against
// the exact expression it replaced, over the same rows.
//
// The other hazard paging introduces is de-duplication: ingest used to match
// against every call in memory, and matching only the loaded page would start
// logging a second copy of anything older than the window.
void main() {
  useInMemoryDatabase();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime(2026, 9, 7, 14, 30);

  CallLogEntry call(
    String id, {
    required DateTime at,
    String? leadId,
    int score = 0,
    int seconds = 60,
    bool inbound = false,
    String? sentiment,
    String leadName = 'Priya',
    String phone = '+919876543210',
  }) => CallLogEntry(
    id: id,
    leadName: leadName,
    phone: phone,
    intent: 'High Intent',
    source: LeadSource.organic,
    duration: Duration(seconds: seconds),
    score: score,
    calledAt: at,
    isInbound: inbound,
    leadId: leadId,
    sentiment: sentiment,
  );

  // A spread deliberately covering every branch the tiles care about: today
  // and not, this month and not, scored and not, lead-linked and not,
  // positive-sentiment and not, inbound and out.
  final corpus = <CallLogEntry>[
    call('t1', at: DateTime(2026, 9, 7, 9), leadId: 'l1', score: 80, sentiment: 'positive', seconds: 120),
    call('t2', at: DateTime(2026, 9, 7, 11), leadId: 'l1', score: 40, sentiment: 'neutral', seconds: 30),
    call('t3', at: DateTime(2026, 9, 7, 12), inbound: true, seconds: 10),
    call('m1', at: DateTime(2026, 9, 2), leadId: 'l2', score: 60, seconds: 240),
    call('m2', at: DateTime(2026, 9, 3), seconds: 15, inbound: true),
    call('old1', at: DateTime(2026, 8, 20), leadId: 'l2', score: 90, seconds: 300),
    call('old2', at: DateTime(2026, 7, 1), seconds: 45),
  ];

  Future<LocalCallStore> seeded([List<CallLogEntry>? entries]) async {
    final store = LocalCallStore();
    await store.upsertAll(entries ?? corpus);
    return store;
  }

  group('SQL aggregates match the Dart they replaced', () {
    test('today, and positive calls today', () async {
      final stats = await (await seeded()).stats(now: now);

      final expectedToday = corpus.where(
        (e) =>
            e.calledAt.year == now.year &&
            e.calledAt.month == now.month &&
            e.calledAt.day == now.day,
      );
      expect(stats.today, expectedToday.length);
      expect(
        stats.positiveToday,
        expectedToday.where((e) => e.sentiment == 'positive').length,
      );
    });

    test('this month', () async {
      final stats = await (await seeded()).stats(now: now);

      expect(
        stats.thisMonth,
        corpus
            .where(
              (e) =>
                  e.calledAt.year == now.year && e.calledAt.month == now.month,
            )
            .length,
      );
    });

    test("Profile's average score ignores unscored calls", () async {
      final stats = await (await seeded()).stats(now: now);

      final scored = corpus.where((e) => e.score > 0).toList();
      expect(
        stats.averageScore,
        scored.map((e) => e.score).reduce((a, b) => a + b) ~/ scored.length,
      );
    });

    test("the Calls screen's lead score counts unscored lead calls as zero", () async {
      // Deliberately a different average from Profile's: this one divides by
      // every lead call, which is what that tile has always done.
      final stats = await (await seeded()).stats(now: now);

      final leadCalls = corpus.where((e) => e.leadId != null).toList();
      expect(
        stats.averageLeadScore,
        leadCalls.map((e) => e.score).fold(0, (a, b) => a + b) ~/
            leadCalls.length,
      );
    });

    test('average duration', () async {
      final stats = await (await seeded()).stats(now: now);

      final total = corpus.fold(0, (a, e) => a + e.duration.inSeconds);
      expect(stats.averageDuration?.inSeconds, total ~/ corpus.length);
    });

    test('lead calls versus phone-log calls', () async {
      final stats = await (await seeded()).stats(now: now);

      final leadCalls = corpus.where((e) => e.leadId != null).length;
      expect(stats.leadCallTotal, leadCalls);
      expect(stats.phoneLogTotal, corpus.length - leadCalls);
    });

    test('an empty log reports null averages, not zero or a crash', () async {
      final stats = await LocalCallStore().stats(now: now);

      expect(stats.total, 0);
      expect(stats.averageScore, isNull);
      expect(stats.averageLeadScore, isNull);
      expect(stats.averageDuration, isNull);
    });
  });

  group('the filter narrows the tiles the same way it narrows the list', () {
    test('direction', () async {
      final store = await seeded();
      const filter = CallLogFilter(isInbound: true);

      final stats = await store.stats(now: now, filter: filter);
      final page = await store.page(limit: 100, filter: filter);

      expect(stats.total, corpus.where((e) => e.isInbound).length);
      expect(page.every((e) => e.isInbound), isTrue);
      expect(page, hasLength(stats.total));
    });

    test('search matches name or phone, case-insensitively', () async {
      final store = await seeded([
        ...corpus,
        call('x1', at: DateTime(2026, 9, 6), leadName: 'Rakesh', phone: '+919000000001'),
      ]);

      final byName = await store.page(
        limit: 100,
        filter: const CallLogFilter(query: 'rAkEsH'),
      );
      final byPhone = await store.page(
        limit: 100,
        filter: const CallLogFilter(query: '9000000001'),
      );

      expect(byName.map((e) => e.id), ['x1']);
      expect(byPhone.map((e) => e.id), ['x1']);
    });

    test('search reaches a call far outside the first page', () async {
      // The whole point of searching: the target scrolled out of memory long
      // ago, so filtering the loaded page would never find it.
      final many = [
        for (var i = 0; i < 200; i++)
          call('bulk$i', at: DateTime(2026, 9, 7).subtract(Duration(hours: i))),
        call('needle', at: DateTime(2024, 1, 1), leadName: 'Findme'),
      ];
      final store = await seeded(many);

      final firstPage = await store.page();
      final found = await store.page(
        filter: const CallLogFilter(query: 'findme'),
      );

      expect(firstPage.map((e) => e.id), isNot(contains('needle')));
      expect(found.map((e) => e.id), ['needle']);
    });
  });

  group('paging', () {
    test('walks the whole log in order, without gaps or repeats', () async {
      final many = [
        for (var i = 0; i < 130; i++)
          call('c$i', at: DateTime(2026, 9, 7).subtract(Duration(minutes: i))),
      ];
      final store = await seeded(many);

      final seen = <String>[];
      for (var offset = 0; ; offset += LocalCallStore.pageSize) {
        final page = await store.page(offset: offset);
        if (page.isEmpty) break;
        seen.addAll(page.map((e) => e.id));
      }

      expect(seen, hasLength(many.length));
      expect(seen.toSet(), hasLength(many.length), reason: 'no repeats');
      expect(seen.first, 'c0', reason: 'newest first');
      expect(seen.last, 'c129', reason: 'oldest last');
    });

    test('one lead\'s calls come back whole, however deep they sit', () async {
      final many = [
        for (var i = 0; i < 200; i++)
          call('c$i', at: DateTime(2026, 9, 7).subtract(Duration(minutes: i))),
        call('old-a', at: DateTime(2023, 5, 1), leadId: 'buried'),
        call('old-b', at: DateTime(2023, 5, 2), leadId: 'buried'),
      ];
      final store = await seeded(many);

      final forLead = await store.forLead('buried');

      expect(forLead.map((e) => e.id), ['old-b', 'old-a']);
    });

    test('since() bounds by time, not by page', () async {
      final store = await seeded();

      final recent = await store.since(DateTime(2026, 9, 1));

      expect(
        recent.map((e) => e.id).toSet(),
        corpus
            .where((e) => !e.calledAt.isBefore(DateTime(2026, 9, 1)))
            .map((e) => e.id)
            .toSet(),
      );
    });
  });

  group('de-duplication survives paging', () {
    test('a call far outside the window is matched, not duplicated', () async {
      // The regression paging invites: matching only the loaded page would
      // treat this as new and write a second row for the same call.
      final many = [
        for (var i = 0; i < 200; i++)
          call('c$i', at: DateTime(2026, 9, 7).subtract(Duration(minutes: i))),
        call('buried', at: DateTime(2023, 5, 1), leadId: 'l9'),
      ];
      final store = await seeded(many);

      final candidates = await store.matchCandidatesFor([
        call('buried', at: DateTime(2023, 5, 1), leadId: 'l9', score: 75),
      ]);

      expect(candidates.map((e) => e.id), contains('buried'));
    });

    test('matches by backend call id', () async {
      final store = await seeded([
        call('local-1', at: DateTime(2026, 9, 1)).copyWith(callId: 'srv-9'),
      ]);

      final candidates = await store.matchCandidatesFor([
        call('different-id', at: DateTime(2026, 9, 1)).copyWith(callId: 'srv-9'),
      ]);

      expect(candidates.map((e) => e.id), contains('local-1'));
    });

    test('matches by device call id', () async {
      final store = await seeded([
        call('local-1', at: DateTime(2026, 9, 1)).copyWith(deviceCallId: 'dev-3'),
      ]);

      final candidates = await store.matchCandidatesFor([
        call('other', at: DateTime(2026, 9, 1)).copyWith(deviceCallId: 'dev-3'),
      ]);

      expect(candidates.map((e) => e.id), contains('local-1'));
    });

    test('matches the same lead within the reconciliation window', () async {
      final store = await seeded([
        call('optimistic', at: DateTime(2026, 9, 7, 10, 0), leadId: 'l1'),
      ]);

      final candidates = await store.matchCandidatesFor([
        call('confirmed', at: DateTime(2026, 9, 7, 10, 1), leadId: 'l1'),
      ]);

      expect(candidates.map((e) => e.id), contains('optimistic'));
    });

    test('a different lead at the same moment is not a candidate', () async {
      final store = await seeded([
        call('other-lead', at: DateTime(2026, 9, 7, 10, 0), leadId: 'l1'),
      ]);

      final candidates = await store.matchCandidatesFor([
        call('mine', at: DateTime(2026, 9, 7, 10, 0), leadId: 'l2'),
      ]);

      expect(candidates, isEmpty);
    });

    test('no candidates for a genuinely new call', () async {
      final store = await seeded();

      final candidates = await store.matchCandidatesFor([
        call('brand-new', at: DateTime(2026, 9, 7, 13), leadId: 'nobody'),
      ]);

      expect(candidates, isEmpty);
    });
  });
}
