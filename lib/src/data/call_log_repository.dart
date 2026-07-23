import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';
import '../models/lead.dart';

/// Talks to the backend's device-call-log endpoints (`app/api/call_log.py`).
/// Callers should treat failures as fail-soft — the local call log (device
/// call_log package + on-device SharedPreferences) is the source of truth for
/// the on-device UI regardless of whether the sync round-trip succeeds.
class CallLogRepository {
  const CallLogRepository(this._client);

  final ApiClient _client;

  /// `POST /api/call-log/sync`. Upserts device call-log entries by their
  /// native device id, so re-syncing after every app launch never duplicates
  /// a call the backend already has.
  Future<void> sync(List<CallLogEntry> entries) async {
    final withDeviceId = entries.where((e) => e.deviceCallId != null).toList();
    if (withDeviceId.isEmpty) return;
    await _client.post(
      ApiEndpoints.callLogSync,
      body: {
        'entries': [
          for (final e in withDeviceId)
            {
              'device_call_id': e.deviceCallId,
              'phone': e.phone,
              'direction': e.isInbound
                  ? (e.duration == Duration.zero ? 'missed' : 'inbound')
                  : 'outbound',
              'duration_seconds': e.duration.inSeconds,
              'called_at': e.calledAt.toUtc().toIso8601String(),
              'lead_id': e.leadId,
            },
        ],
      },
    );
  }
}
