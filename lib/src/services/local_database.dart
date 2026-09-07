import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// The device-local SQLite database, and the one-time move onto it.
///
/// The call log and per-lead transcripts used to live in SharedPreferences —
/// the call log as one JSON array under a single key, each transcript under
/// its own `transcript_v1_<leadId>` key. SharedPreferences reads its entire
/// backing file into memory on first access and holds it there for the life of
/// the process, so *every* transcript a telecaller had ever captured stayed
/// resident to serve the one being looked at, and `loadAll()` then allocated a
/// second, decoded copy of the whole call log on top. Appending a single call
/// re-encoded and rewrote the entire array, a cost that grew with every call
/// ever made.
///
/// Rows are stored as a few indexed columns plus the model's own JSON. That is
/// deliberate: the columns are exactly what identity, ordering and paging need,
/// and keeping the rest as JSON means the models stay the source of truth and
/// adding a field to [CallLogEntry] does not require a schema migration.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'leadpilot.db';
  static const _version = 2;

  /// Set by tests to point at an in-memory FFI database. Left null in the app.
  static DatabaseFactory? factoryOverride;

  /// Set by tests that need a database file surviving a close and reopen —
  /// the schema-upgrade path, which an in-memory database cannot exercise.
  static String? pathOverride;

  Database? _db;
  Future<Database>? _opening;

  /// Opens (once) and returns the database. Concurrent callers share the same
  /// in-flight open rather than racing to create two connections.
  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final dbFactory = factoryOverride ?? databaseFactory;
    final path =
        pathOverride ??
        (factoryOverride != null
            ? inMemoryDatabasePath
            : p.join(await dbFactory.getDatabasesPath(), _fileName));

    try {
      final db = await dbFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _version,
          onCreate: (db, _) async => _createSchema(db),
          onUpgrade: _upgrade,
        ),
      );
      await _migrateFromPreferences(db);
      // Published only once the migration has finished. Setting it earlier
      // would let a concurrent caller take the `_db != null` fast path and
      // query a database whose rows have not been carried over yet — and at
      // startup there ARE concurrent callers, since the call list and the
      // summary tiles both reach for it at once.
      _db = db;
      return db;
    } catch (_) {
      // Otherwise the failed future is cached and every later attempt — after
      // whatever was wrong has cleared — replays the same error forever.
      _opening = null;
      rethrow;
    }
  }

  static Future<void> _createSchema(Database db) async {
    await _createCallsTable(db);
    await _createTranscriptsTable(db);
  }

  static Future<void> _createCallsTable(Database db) async {
    // `data` carries the full CallLogEntry JSON; the columns beside it are the
    // ones merge identity, ordering, search and the summary tiles query on.
    await db.execute('''
      CREATE TABLE calls (
        id TEXT PRIMARY KEY,
        called_at INTEGER NOT NULL,
        lead_id TEXT,
        call_id TEXT,
        device_call_id TEXT,
        lead_name TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        score INTEGER NOT NULL DEFAULT 0,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        is_inbound INTEGER NOT NULL DEFAULT 0,
        sentiment TEXT,
        data TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_calls_called_at ON calls(called_at)');
    await db.execute('CREATE INDEX idx_calls_lead_id ON calls(lead_id)');
  }

  static Future<void> _createTranscriptsTable(Database db) async {
    // One row per lead. Transcripts are large and only ever read one at a
    // time, which is precisely what the old all-keys-resident storage was
    // worst at.
    await db.execute('''
      CREATE TABLE transcripts (
        lead_id TEXT PRIMARY KEY,
        data TEXT NOT NULL
      )
    ''');
  }

  /// Moves anything still in SharedPreferences into SQLite, once.
  ///
  /// Ordered so a crash cannot lose data: rows are committed first, and only
  /// then are the preference keys cleared. A migration interrupted midway
  /// re-runs on the next launch and overwrites the same rows — every write
  /// here is an upsert keyed by the row's own identity, so replaying it is
  /// harmless.
  static Future<void> _migrateFromPreferences(Database db) async {
    final prefs = await SharedPreferences.getInstance();

    final rawCalls = prefs.getString(legacyCallsKey);
    if (rawCalls != null) {
      try {
        final list = jsonDecode(rawCalls) as List;
        final batch = db.batch();
        for (final entry in list) {
          if (entry is! Map<String, dynamic>) continue;
          batch.insert(
            'calls',
            callRow(entry),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
        await prefs.remove(legacyCallsKey);
      } catch (_) {
        // A blob we cannot parse is a blob the old code could not read either
        // (its loadAll caught and returned empty). Drop it rather than
        // re-attempting the same failure on every launch forever.
        await prefs.remove(legacyCallsKey);
      }
    }

    final transcriptKeys = prefs
        .getKeys()
        .where((k) => k.startsWith(legacyTranscriptPrefix))
        .toList();
    for (final key in transcriptKeys) {
      final raw = prefs.getString(key);
      if (raw != null) {
        await db.insert('transcripts', {
          'lead_id': key.substring(legacyTranscriptPrefix.length),
          'data': raw,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await prefs.remove(key);
    }
  }

  /// v1 kept only identity/ordering columns and left everything else inside
  /// `data`. Paging the call list moved the summary tiles (totals, averages,
  /// "this month") and search onto SQL, and those cannot read a JSON blob — so
  /// v2 promotes the fields they need. Rebuilt from `data`, which already
  /// holds every value, so nothing is lost and no network round-trip is needed.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from >= 2) return;
    final existing = await db.query('calls', columns: const ['data']);
    await db.execute('DROP TABLE calls');
    await _createCallsTable(db);
    final batch = db.batch();
    for (final row in existing) {
      final raw = row['data'];
      if (raw is! String) continue;
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          batch.insert(
            'calls',
            callRow(json),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } catch (_) {
        // One unreadable row should not abort the upgrade for the rest.
      }
    }
    await batch.commit(noResult: true);
  }

  static const legacyCallsKey = 'local_calls_v1';
  static const legacyTranscriptPrefix = 'transcript_v1_';

  /// A `calls` row built from a [CallLogEntry]'s JSON. Shared by the migration
  /// and by ordinary writes so the two can never disagree about the shape.
  ///
  /// `called_at` is stored as epoch milliseconds rather than the ISO string the
  /// model uses, so ordering is a numeric index scan instead of a string sort.
  static Map<String, Object?> callRow(Map<String, dynamic> json) {
    // Keys are CallLogEntry.toJson's own, which are snake_case.
    final calledAt = DateTime.tryParse((json['called_at'] ?? '').toString());
    return {
      'id': (json['id'] ?? '').toString(),
      'called_at': (calledAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .millisecondsSinceEpoch,
      'lead_id': json['lead_id'] as String?,
      'call_id': json['call_id'] as String?,
      'device_call_id': json['device_call_id'] as String?,
      'lead_name': (json['lead_name'] ?? '').toString(),
      'phone': (json['phone'] ?? '').toString(),
      'score': (json['score'] as num?)?.toInt() ?? 0,
      'duration_seconds': (json['duration_seconds'] as num?)?.toInt() ?? 0,
      // SQLite has no boolean; the aggregates compare against 1/0.
      'is_inbound': json['is_inbound'] == true ? 1 : 0,
      'sentiment': json['sentiment'] as String?,
      'data': jsonEncode(json),
    };
  }

  /// Empties every table, for logout.
  ///
  /// Both of these tables used to live in SharedPreferences, which
  /// [SessionController.logout] wipes wholesale — so signing out took the call
  /// log and the transcripts with it. Moving them into SQLite put them outside
  /// that wipe, which would leave one telecaller's calls, and the actual words
  /// spoken on them, on the device for whoever signs in next. Deletes the rows
  /// rather than the file so the open connection stays valid.
  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('calls');
      await txn.delete('transcripts');
    });
  }

  /// Closes and forgets the connection. For tests; the app holds one open for
  /// its lifetime.
  Future<void> close() async {
    // An open still in flight has to finish before it can be closed, or it
    // would publish itself into `_db` moments after this returned.
    try {
      await _opening;
    } catch (_) {
      // Already failed; nothing to close.
    }
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
