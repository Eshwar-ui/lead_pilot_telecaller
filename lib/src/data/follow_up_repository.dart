import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';
import '../models/lead.dart';

/// Talks to the FastAPI follow-up endpoints (`voicesummary-main`).
///
/// Previously follow-ups lived only in on-device SharedPreferences
/// (`LocalFollowUpStore`) — this is what actually syncs them to the backend
/// so the founder dashboard's missed-follow-up leakage metric has real data.
/// Callers should treat failures as fail-soft (the local store is still the
/// source of truth for the on-device UI) rather than surfacing them.
class FollowUpRepository {
  const FollowUpRepository(this._client);

  final ApiClient _client;

  /// `POST /api/follow-ups`. Returns the backend-assigned id.
  Future<String> create({
    required String? leadId,
    required String? note,
    required DateTime dueAt,
  }) async {
    final body = await _client.post(
      ApiEndpoints.followUps,
      body: {
        'lead_id': leadId,
        'note': note,
        'due_at': dueAt.toUtc().toIso8601String(),
      },
    );
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    return (map['id'] ?? '').toString();
  }

  /// `GET /api/follow-ups` — the caller's follow-ups from the backend, so
  /// follow-ups created on another device / the web dashboard show up here too
  /// (read-back). Each carries its backend id so the merge in FollowUpController
  /// can key on it and never duplicate a task it already has locally.
  ///
  /// [includeCompleted] must be true for the controller's reconcile pass —
  /// the backend hides completed follow-ups by default, so without it a task
  /// marked done on another device would look deleted, and its "done" status
  /// could never propagate here.
  Future<List<FollowUpTask>> list({bool includeCompleted = false}) async {
    final body = await _client.get(
      ApiEndpoints.followUps,
      query: includeCompleted ? {'include_completed': 'true'} : null,
    );
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final rows = (map['follow_ups'] as List?) ?? const [];
    final now = DateTime.now();
    return [
      for (final r in rows.whereType<Map<String, dynamic>>())
        _fromBackend(r, now),
    ];
  }

  static FollowUpTask _fromBackend(Map<String, dynamic> r, DateTime now) {
    final id = (r['id'] ?? '').toString();
    final completedAt = r['completed_at'];
    final dueAt = DateTime.tryParse((r['due_at'] ?? '').toString())?.toLocal();
    final status = completedAt != null
        ? FollowUpStatus.done
        : (dueAt != null && dueAt.isBefore(now)
            ? FollowUpStatus.overdue
            : FollowUpStatus.pending);
    return FollowUpTask(
      id: 'srv_$id', // distinct local id; backendId is the real join key
      backendId: id,
      taskText: (r['note'] ?? 'Follow up').toString(),
      leadName: (r['lead_id'] ?? '').toString(),
      leadId: r['lead_id']?.toString(),
      status: status,
      scheduledAt: dueAt,
      note: r['note']?.toString(),
    );
  }

  /// `PATCH /api/follow-ups/{id}` with completed=true/false.
  Future<void> setCompleted(String backendId, bool completed) async {
    await _client.patch(
      ApiEndpoints.followUp(backendId),
      body: {'completed': completed},
    );
  }

  /// `DELETE /api/follow-ups/{id}`.
  Future<void> delete(String backendId) async {
    await _client.delete(ApiEndpoints.followUp(backendId));
  }
}
