import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lead.dart';

/// Persists calls placed from inside the app to SharedPreferences, so the call
/// log and a lead's history survive even when the backend hasn't ingested a
/// recording yet. Keyed by `local_calls_v1` as a JSON array of [CallLogEntry].
class LocalCallStore {
  static const _key = 'local_calls_v1';

  Future<List<CallLogEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) CallLogEntry.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> replaceAll(List<CallLogEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }
}

final localCallStoreProvider = Provider<LocalCallStore>(
  (_) => LocalCallStore(),
);

/// Reactive list of locally-recorded calls (newest first).
final localCallsProvider =
    NotifierProvider<LocalCallsController, List<CallLogEntry>>(
      LocalCallsController.new,
    );

class LocalCallsController extends Notifier<List<CallLogEntry>> {
  @override
  List<CallLogEntry> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    state = await ref.read(localCallStoreProvider).loadAll();
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
    final merged = mergeCallEntries(state, incoming);
    // Only touch storage when something actually changed.
    if (identical(merged, state)) return;
    await ref.read(localCallStoreProvider).replaceAll(merged);
    state = merged;
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
