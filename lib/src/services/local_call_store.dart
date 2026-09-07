import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../models/lead.dart';
import 'local_database.dart';

/// Persists calls placed from inside the app, so the call log and a lead's
/// history survive even when the backend hasn't ingested a recording yet.
///
/// One SQLite row per call. This used to be a single JSON array in
/// SharedPreferences, which meant the raw text of every call ever made stayed
/// resident for the life of the process and logging one call rewrote the lot —
/// see [AppDatabase] for the full reasoning and the migration off it.
class LocalCallStore {
  /// One page of the call log, newest first — the order it renders in, so the
  /// sort is an index scan rather than work repeated on every read.
  ///
  /// The whole log is deliberately never loaded at once: a telecaller a year in
  /// has tens of thousands of calls, and the screen shows a dozen.
  Future<List<CallLogEntry>> page({
    int limit = pageSize,
    int offset = 0,
    CallLogFilter filter = const CallLogFilter(),
  }) {
    final (:where, :args) = filter.toSql();
    return _query(
      where: where,
      whereArgs: args,
      orderBy: 'called_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Calls belonging to one lead, for its detail screen. Served by
  /// `idx_calls_lead_id` rather than by scanning everything in memory.
  Future<List<CallLogEntry>> forLead(String leadId) => _query(
    where: 'lead_id = ?',
    whereArgs: [leadId],
    orderBy: 'called_at DESC',
  );

  /// Calls at or after [cutoff] — today's tiles, and the auto-capture
  /// backfill's own window.
  Future<List<CallLogEntry>> since(DateTime cutoff) => _query(
    where: 'called_at >= ?',
    whereArgs: [cutoff.millisecondsSinceEpoch],
    orderBy: 'called_at DESC',
  );

  /// The rows that could be the same call as one of [incoming], so ingest can
  /// de-duplicate against the entire history rather than against whichever
  /// page happens to be loaded. Without this, paging would silently start
  /// duplicating calls older than the window.
  Future<List<CallLogEntry>> matchCandidatesFor(
    List<CallLogEntry> incoming,
  ) async {
    if (incoming.isEmpty) return const [];
    final clauses = <String>[];
    final args = <Object?>[];
    for (final entry in incoming) {
      clauses.add('id = ?');
      args.add(entry.id);
      if (entry.deviceCallId != null) {
        clauses.add('device_call_id = ?');
        args.add(entry.deviceCallId);
      }
      if (entry.callId != null) {
        clauses.add('call_id = ?');
        args.add(entry.callId);
      }
      // The lead+time-window arm of _sameCall: an optimistic "recording found"
      // entry being reconciled with the confirmed backend copy of the same call.
      if (entry.leadId != null) {
        clauses.add('(lead_id = ? AND called_at BETWEEN ? AND ?)');
        args
          ..add(entry.leadId)
          ..add(
            entry.calledAt
                .subtract(const Duration(minutes: 3))
                .millisecondsSinceEpoch,
          )
          ..add(
            entry.calledAt
                .add(const Duration(minutes: 3))
                .millisecondsSinceEpoch,
          );
      }
    }
    return _query(where: clauses.join(' OR '), whereArgs: args);
  }

  /// The summary numbers behind the Calls, Inbox and Profile tiles, computed
  /// by SQLite over every row instead of by filtering a list that is no longer
  /// fully in memory.
  Future<CallLogStats> stats({
    DateTime? now,
    CallLogFilter filter = const CallLogFilter(),
  }) async {
    final db = await AppDatabase.instance.database;
    final at = now ?? DateTime.now();
    // Local midnight / first-of-month, matching the DateTime.year/month/day
    // comparisons these tiles used to do — the stored timestamps are epoch
    // millis of local DateTimes, so the boundaries must be local too.
    final startOfDay = DateTime(at.year, at.month, at.day);
    final startOfMonth = DateTime(at.year, at.month);
    final (:where, :args) = filter.toSql();
    final whereClause = where == null ? '' : 'WHERE $where';

    final row = (await db.rawQuery(
      '''
      SELECT
        COUNT(*)                                       AS total,
        COALESCE(SUM(called_at >= ?), 0)               AS today,
        COALESCE(SUM(called_at >= ? AND sentiment = 'positive'), 0)
                                                       AS positive_today,
        COALESCE(SUM(called_at >= ?), 0)               AS this_month,
        COALESCE(SUM(score > 0), 0)                    AS scored_count,
        COALESCE(SUM(CASE WHEN score > 0 THEN score ELSE 0 END), 0)
                                                       AS scored_total,
        COALESCE(SUM(CASE WHEN lead_id IS NOT NULL AND score > 0
                          THEN score ELSE 0 END), 0)   AS lead_scored_total,
        COALESCE(SUM(lead_id IS NOT NULL AND score > 0), 0)
                                                       AS lead_scored_count,
        COALESCE(SUM(duration_seconds), 0)             AS duration_total,
        COALESCE(SUM(lead_id IS NOT NULL), 0)          AS lead_call_total
      FROM calls
      $whereClause
      ''',
      [
        startOfDay.millisecondsSinceEpoch,
        startOfDay.millisecondsSinceEpoch,
        startOfMonth.millisecondsSinceEpoch,
        ...args,
      ],
    )).first;

    int n(String key) => (row[key] as num?)?.toInt() ?? 0;
    return CallLogStats(
      total: n('total'),
      today: n('today'),
      positiveToday: n('positive_today'),
      thisMonth: n('this_month'),
      scoredCount: n('scored_count'),
      scoredTotal: n('scored_total'),
      leadScoredCount: n('lead_scored_count'),
      leadScoredTotal: n('lead_scored_total'),
      durationSecondsTotal: n('duration_total'),
      leadCallTotal: n('lead_call_total'),
    );
  }

  Future<List<CallLogEntry>> _query({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'calls',
      columns: const ['data'],
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return [
      for (final row in rows)
        if (_decode(row['data']) case final json?) CallLogEntry.fromJson(json),
    ];
  }

  /// How many calls one page holds. Comfortably more than fills a screen, so
  /// scrolling rarely waits, while staying far below "all of them".
  static const pageSize = 60;

  /// Inserts or updates just these calls, leaving every other row alone.
  ///
  /// Callers pass only what actually changed (see [LocalCallsController.ingest]),
  /// so recording one call writes one row — where the old storage re-encoded
  /// and rewrote the entire history for the same event.
  Future<void> upsertAll(List<CallLogEntry> entries) async {
    if (entries.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final batch = db.batch();
    for (final entry in entries) {
      batch.insert(
        'calls',
        AppDatabase.callRow(entry.toJson()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Map<String, dynamic>? _decode(Object? data) {
    if (data is! String) return null;
    try {
      final json = jsonDecode(data);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      // One unreadable row shouldn't cost the telecaller their whole log.
      return null;
    }
  }
}

final localCallStoreProvider = Provider<LocalCallStore>(
  (_) => LocalCallStore(),
);

/// The slice of the call log currently held in memory, newest first.
class CallLogPage {
  const CallLogPage({
    this.entries = const [],
    this.hasMore = false,
    this.loadingMore = false,
  });

  final List<CallLogEntry> entries;

  /// Whether older calls exist beyond what is loaded.
  final bool hasMore;

  final bool loadingMore;

  CallLogPage copyWith({
    List<CallLogEntry>? entries,
    bool? hasMore,
    bool? loadingMore,
  }) => CallLogPage(
    entries: entries ?? this.entries,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Bumped whenever rows are written. Aggregate queries key off this rather
/// than off the loaded page, so paging in more calls — which changes the page
/// but not the underlying data — does not re-run a full-table scan.
final callLogRevisionProvider = NotifierProvider<CallLogRevision, int>(
  CallLogRevision.new,
);

class CallLogRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

/// A window onto the locally-recorded calls, newest first.
///
/// Holds a page rather than the entire log: a telecaller a year in has tens of
/// thousands of calls, all of which used to be materialised as objects and
/// kept for the life of the process to render a screen showing a dozen.
final localCallsProvider =
    NotifierProvider<LocalCallsController, CallLogPage>(
      LocalCallsController.new,
    );

class LocalCallsController extends Notifier<CallLogPage> {
  @override
  CallLogPage build() {
    _load();
    return const CallLogPage();
  }

  CallLogFilter _filter = const CallLogFilter();

  CallLogFilter get filter => _filter;

  /// Narrows the window. Reloads from the first page rather than filtering
  /// what is already loaded — a search has to be able to reach a call that
  /// scrolled out of memory long ago.
  Future<void> setFilter(CallLogFilter filter) async {
    if (filter == _filter) return;
    _filter = filter;
    await _load();
  }

  Future<void> _load({int? limit}) async {
    final take = limit ?? LocalCallStore.pageSize;
    final store = ref.read(localCallStoreProvider);
    // One extra row is the cheapest way to know whether more exist without a
    // second COUNT query.
    final rows = await store.page(limit: take + 1, filter: _filter);
    state = CallLogPage(
      entries: rows.length > take ? rows.sublist(0, take) : rows,
      hasMore: rows.length > take,
    );
  }

  /// Re-reads however much is currently on screen, so a refresh after a write
  /// doesn't collapse a scrolled-down list back to the first page.
  Future<void> refresh() => _load(
    limit: state.entries.length < LocalCallStore.pageSize
        ? LocalCallStore.pageSize
        : state.entries.length,
  );

  /// Extends the window by one page. Reached from the Calls screen as the
  /// telecaller nears the end of the list.
  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore) return;
    state = state.copyWith(loadingMore: true);
    final store = ref.read(localCallStoreProvider);
    final take = LocalCallStore.pageSize;
    final rows = await store.page(
      limit: take + 1,
      offset: state.entries.length,
      filter: _filter,
    );
    state = CallLogPage(
      entries: [
        ...state.entries,
        ...rows.length > take ? rows.sublist(0, take) : rows,
      ],
      hasMore: rows.length > take,
    );
  }

  /// Records a single call actually observed on this device (e.g. a recording
  /// was found for a call that just ended). Upserts so the same call isn't
  /// logged twice.
  Future<void> record(CallLogEntry entry) => ingest([entry]);

  /// Merges backend call history (from an enriched lead) into the persisted
  /// log so those calls survive an app restart and no longer depend on the
  /// lead staying open in memory. Upserts by call identity, and the backend
  /// copy (which carries the real call_id, score and duration) wins.
  Future<void> ingest(List<CallLogEntry> incoming) async {
    if (incoming.isEmpty) return;
    final store = ref.read(localCallStoreProvider);
    // Dedupe against the DATABASE, not the loaded page. Matching only what
    // happens to be in the window would quietly start logging a second copy of
    // any call older than it — the exact bug paging invites.
    final existing = await store.matchCandidatesFor(incoming);
    final merged = mergeCallEntries(existing, incoming);
    // Only touch storage when something actually changed.
    if (identical(merged, existing)) return;
    // mergeCallEntries copies the list and only substitutes an element when it
    // genuinely changed, so anything still identical to its old instance is
    // untouched and does not need writing. Everything past the old length is
    // new. That turns "log one call" into one row written rather than all of
    // them.
    await store.upsertAll([
      for (var i = 0; i < merged.length; i++)
        if (i >= existing.length || !identical(merged[i], existing[i]))
          merged[i],
    ]);
    ref.read(callLogRevisionProvider.notifier).bump();
    await refresh();
  }
}

/// Upserts [incoming] call entries into [current], de-duplicated by call
/// identity. Returns [current] unchanged (same instance) when nothing new was
/// added or upgraded, so callers can skip a redundant persist. Pure — unit
/// tested in test/merge_call_entries_test.dart.
List<CallLogEntry> mergeCallEntries(
  List<CallLogEntry> current,
  List<CallLogEntry> incoming,
) {
  final list = [...current];
  var changed = false;
  for (final e in incoming) {
    final idx = list.indexWhere((x) => _sameCall(x, e));
    if (idx >= 0) {
      final upgraded = _preferConfirmed(list[idx], e);
      if (!identical(upgraded, list[idx])) {
        list[idx] = upgraded;
        changed = true;
      }
    } else {
      list.add(e);
      changed = true;
    }
  }
  return changed ? list : current;
}

/// Two entries are the same call when they share a device call-log id or a
/// backend call_id. When only one side has a call_id yet, fuse by lead+time
/// window — that's the optimistic "recording found" entry being reconciled
/// with the now-confirmed backend-history entry for the same call. When
/// NEITHER side has a call_id, don't fuzzy-match by lead+time: two genuinely
/// distinct calls to the same lead placed within the window (e.g. a quick
/// no-answer redial) would otherwise silently fuse into one before either
/// gets its own call_id back from the backend. Fall back to exact id
/// equality instead — safe because the id embeds the recording's own
/// timestamp, so two different recordings never collide, while re-ingesting
/// the same one (e.g. a retried scan) is idempotent.
bool _sameCall(CallLogEntry a, CallLogEntry b) {
  if (a.deviceCallId != null && b.deviceCallId != null) {
    return a.deviceCallId == b.deviceCallId;
  }
  if (a.callId != null && b.callId != null) return a.callId == b.callId;
  if ((a.callId != null) != (b.callId != null)) {
    return a.leadId != null &&
        a.leadId == b.leadId &&
        a.calledAt.difference(b.calledAt).inMinutes.abs() <= 2;
  }
  return a.id == b.id;
}

/// When merging, keep the richer data: a real call_id, a positive score and
/// a non-zero duration all come from the confirmed backend copy.
CallLogEntry _preferConfirmed(CallLogEntry existing, CallLogEntry incoming) {
  final callId = existing.callId ?? incoming.callId;
  final deviceCallId = existing.deviceCallId ?? incoming.deviceCallId;
  final score = incoming.score > existing.score
      ? incoming.score
      : existing.score;
  final duration = incoming.duration > existing.duration
      ? incoming.duration
      : existing.duration;
  // Sentiment only ever comes from a backend-analyzed call — a device-log or
  // optimistic entry never has one, so whichever side has it wins.
  final sentiment = existing.sentiment ?? incoming.sentiment;
  // Prefer the confirmed timestamp once a call_id is known.
  final calledAt = (existing.callId == null && incoming.callId != null)
      ? incoming.calledAt
      : existing.calledAt;
  if (callId == existing.callId &&
      deviceCallId == existing.deviceCallId &&
      score == existing.score &&
      duration == existing.duration &&
      sentiment == existing.sentiment &&
      calledAt == existing.calledAt) {
    return existing; // nothing new
  }
  return existing.copyWith(
    callId: callId,
    deviceCallId: deviceCallId,
    score: score,
    duration: duration,
    sentiment: sentiment,
    calledAt: calledAt,
    leadName: incoming.leadName.isNotEmpty
        ? incoming.leadName
        : existing.leadName,
    phone: incoming.phone.isNotEmpty ? incoming.phone : existing.phone,
  );
}


/// Summary counts over the whole call log, computed in SQL.
///
/// These used to be `.where(...)` passes over an in-memory list of every call
/// ever made. Paging that list away means the tiles have to be answered by the
/// database instead — and it is a far better tool for the job, since it reads
/// indexed columns rather than materialising objects nobody displays.
class CallLogStats {
  const CallLogStats({
    this.total = 0,
    this.today = 0,
    this.positiveToday = 0,
    this.thisMonth = 0,
    this.scoredCount = 0,
    this.scoredTotal = 0,
    this.leadScoredCount = 0,
    this.leadScoredTotal = 0,
    this.durationSecondsTotal = 0,
    this.leadCallTotal = 0,
  });

  final int total;
  final int today;
  final int positiveToday;
  final int thisMonth;
  final int scoredCount;
  final int scoredTotal;
  final int leadScoredCount;
  final int leadScoredTotal;
  final int durationSecondsTotal;

  /// Calls linked to a lead. The rest are entries read from the phone's own
  /// call log that never matched one.
  final int leadCallTotal;

  int get phoneLogTotal => total - leadCallTotal;

  /// Mean score over calls that have one, or null when none do — matching the
  /// old `scored.isEmpty ? null : ...`, and integer division as before.
  int? get averageScore =>
      scoredCount == 0 ? null : scoredTotal ~/ scoredCount;

  /// Mean score over lead calls only, counting unscored ones as zero — which
  /// is what the Calls screen's Lead Score tile has always shown (it divided
  /// by every lead call, not just the scored ones). Deliberately different
  /// from [averageScore], which Profile uses and which ignores unscored calls.
  int? get averageLeadScore =>
      leadCallTotal == 0 ? null : leadScoredTotal ~/ leadCallTotal;

  /// Mean call length, or null when there are no calls at all.
  Duration? get averageDuration => total == 0
      ? null
      : Duration(seconds: durationSecondsTotal ~/ total);
}


/// What subset of the call log a query is about.
///
/// Shared by the list page and the summary tiles so the two can never describe
/// different sets of calls — they were both derived from one filtered list
/// before paging split them apart.
class CallLogFilter {
  const CallLogFilter({this.isInbound, this.query = ''});

  /// null means either direction.
  final bool? isInbound;

  /// Matched against the lead's name and phone number. Empty means no search.
  final String query;

  ({String? where, List<Object?> args}) toSql() {
    final clauses = <String>[];
    final args = <Object?>[];
    if (isInbound != null) {
      clauses.add('is_inbound = ?');
      args.add(isInbound! ? 1 : 0);
    }
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isNotEmpty) {
      clauses.add('(LOWER(lead_name) LIKE ? OR LOWER(phone) LIKE ?)');
      args
        ..add('%$trimmed%')
        ..add('%$trimmed%');
    }
    return (
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      args: args,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CallLogFilter &&
      other.isInbound == isInbound &&
      other.query == query;

  @override
  int get hashCode => Object.hash(isInbound, query);
}
