import 'package:call_log/call_log.dart' as device_call_log;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/lead.dart';

/// Reads the device's real call log (every call, any app — not just calls
/// placed through this app's own dialer flow), so the Calls screen can show a
/// real dialer-style history instead of only app-initiated calls.
///
/// Requires READ_CALL_LOG, a Google Play "restricted permission" — declared
/// deliberately narrow: read-only. WRITE_CALL_LOG is NOT declared in the
/// manifest since this app never writes to the call log; the `call_log`
/// plugin's own permission gate only actually checks its first requested
/// permission's grant result before proceeding (a bug in its current
/// release), so leaving WRITE_CALL_LOG undeclared works in practice without
/// extra prompts — if a future plugin version fixes that, this would need
/// WRITE_CALL_LOG declared too.
class NativeCallLogService {
  const NativeCallLogService();

  Future<bool> hasPermission() async => (await Permission.phone.status).isGranted;

  Future<bool> requestPermission() async =>
      (await Permission.phone.request()).isGranted;

  /// Reads call log entries from [since] to now, newest first. Never throws —
  /// returns an empty list if permission is missing or the platform call
  /// fails, since callers already have a working local list to fall back to.
  Future<List<CallLogEntry>> fetchSince(DateTime since) async {
    if (!await hasPermission()) return const [];
    try {
      final entries = await device_call_log.CallLog.query(dateTimeFrom: since);
      return [for (final e in entries) ?_toAppEntry(e)];
    } catch (_) {
      return const [];
    }
  }

  CallLogEntry? _toAppEntry(device_call_log.CallLogEntry e) {
    final number = e.number;
    final ts = e.timestamp;
    if (number == null || number.isEmpty || ts == null) return null;
    return CallLogEntry(
      id: 'device_${e.id}_$ts',
      leadName: (e.name != null && e.name!.isNotEmpty) ? e.name! : number,
      phone: number,
      intent: '',
      // No real lead-source concept applies to a raw device call log entry;
      // `organic` is this codebase's own established "unknown" fallback (see
      // LeadSourceX.fromValue's orElse). _CallTile only shows the source pill
      // when the call is actually matched to a lead, so this value is inert
      // for the common case — it just avoids a null/required-field problem.
      source: LeadSource.organic,
      duration: Duration(seconds: e.duration ?? 0),
      score: 0,
      calledAt: DateTime.fromMillisecondsSinceEpoch(ts),
      isInbound: _isInbound(e.callType),
      deviceCallId: e.id,
    );
  }

  bool _isInbound(device_call_log.CallType? type) => switch (type) {
    device_call_log.CallType.outgoing ||
    device_call_log.CallType.wifiOutgoing => false,
    // incoming, missed, rejected, blocked, voicemail, answeredExternally,
    // unknown, wifiIncoming — everything else reads as "not one I placed".
    _ => true,
  };
}

final nativeCallLogServiceProvider =
    Provider<NativeCallLogService>((_) => const NativeCallLogService());
