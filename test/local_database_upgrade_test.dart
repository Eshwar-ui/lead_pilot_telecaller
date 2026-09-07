import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/services/local_call_store.dart';
import 'package:lead_pilot_telecaller/src/services/local_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_database.dart';

// Schema v1 stored only identity and ordering columns and kept everything else
// inside the `data` JSON. Paging moved the summary tiles and search onto SQL,
// which cannot read a blob, so v2 promotes the fields they need and rebuilds
// every row from `data`.
//
// A rebuild that drops rows loses a telecaller's call history outright — the
// local-only entries have no server copy — so the upgrade is exercised against
// a real v1 database file rather than assumed to work.
void main() {
  useInMemoryDatabase();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('leadpilot_upgrade_test');
    AppDatabase.pathOverride = '${dir.path}/leadpilot.db';
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Writes a database in exactly the shape v1 left behind.
  Future<void> seedV1(List<CallLogEntry> calls) async {
    final db = await databaseFactoryFfi.openDatabase(
      AppDatabase.pathOverride!,
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('''
      CREATE TABLE calls (
        id TEXT PRIMARY KEY,
        called_at INTEGER NOT NULL,
        lead_id TEXT,
        call_id TEXT,
        device_call_id TEXT,
        data TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_calls_called_at ON calls(called_at)');
    await db.execute('CREATE INDEX idx_calls_lead_id ON calls(lead_id)');
    await db.execute('''
      CREATE TABLE transcripts (
        lead_id TEXT PRIMARY KEY,
        data TEXT NOT NULL
      )
    ''');
    for (final call in calls) {
      final json = call.toJson();
      await db.insert('calls', {
        'id': call.id,
        'called_at': call.calledAt.millisecondsSinceEpoch,
        'lead_id': call.leadId,
        'call_id': call.callId,
        'device_call_id': call.deviceCallId,
        'data': jsonEncode(json),
      });
    }
    await db.insert('transcripts', {
      'lead_id': 'lead-1',
      'data': jsonEncode({'transcript': 'kept', 'entries': <Object>[]}),
    });
    await db.close();
  }

  CallLogEntry call(
    String id, {
    required DateTime at,
    String? leadId,
    int score = 0,
    int seconds = 60,
    bool inbound = false,
    String? sentiment,
  }) => CallLogEntry(
    id: id,
    leadName: 'Priya',
    phone: '+919876543210',
    intent: 'High Intent',
    source: LeadSource.organic,
    duration: Duration(seconds: seconds),
    score: score,
    calledAt: at,
    isInbound: inbound,
    leadId: leadId,
    sentiment: sentiment,
  );

  test('every v1 row survives the rebuild, in order', () async {
    await seedV1([
      call('a', at: DateTime(2026, 9, 1), leadId: 'l1', score: 80),
      call('b', at: DateTime(2026, 9, 5)),
      call('c', at: DateTime(2026, 9, 3), leadId: 'l2', score: 40),
    ]);

    final restored = await LocalCallStore().page(limit: 100);

    expect(restored.map((e) => e.id), ['b', 'c', 'a']);
    expect(restored.firstWhere((e) => e.id == 'a').score, 80);
    expect(restored.firstWhere((e) => e.id == 'a').leadId, 'l1');
  });

  test('the promoted columns are populated, so the tiles work after upgrade', () async {
    // The whole reason for v2: these numbers come from columns that did not
    // exist in v1 and have to be rebuilt out of `data`.
    await seedV1([
      call('t1', at: DateTime(2026, 9, 7, 9), leadId: 'l1', score: 80, sentiment: 'positive', seconds: 120),
      call('t2', at: DateTime(2026, 9, 7, 10), score: 0, seconds: 60, inbound: true),
      call('old', at: DateTime(2026, 7, 1), leadId: 'l2', score: 40, seconds: 30),
    ]);

    final stats = await LocalCallStore().stats(now: DateTime(2026, 9, 7, 14));

    expect(stats.total, 3);
    expect(stats.today, 2);
    expect(stats.positiveToday, 1);
    expect(stats.thisMonth, 2);
    expect(stats.leadCallTotal, 2);
    expect(stats.averageScore, 60); // (80 + 40) / 2 scored
    expect(stats.averageDuration?.inSeconds, (120 + 60 + 30) ~/ 3);
  });

  test('search works after upgrade, on a column v1 never had', () async {
    await seedV1([call('a', at: DateTime(2026, 9, 1))]);

    final found = await LocalCallStore().page(
      filter: const CallLogFilter(query: 'priya'),
    );

    expect(found.map((e) => e.id), ['a']);
  });

  test('transcripts are left alone — only the calls table is rebuilt', () async {
    await seedV1([call('a', at: DateTime(2026, 9, 1))]);

    // Opening through AppDatabase runs the upgrade; the transcript seeded into
    // the v1 file must still be there afterwards.
    await LocalCallStore().page();
    final db = await AppDatabase.instance.database;
    final rows = await db.query('transcripts');

    expect(rows, hasLength(1));
    expect(rows.first['lead_id'], 'lead-1');
  });

  test('upgrading an empty v1 database is not an error', () async {
    await seedV1(const []);

    expect(await LocalCallStore().page(), isEmpty);
  });
}
