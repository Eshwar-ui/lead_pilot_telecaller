import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One call that just ended on this phone, as reported by the native
/// CallDetectionService. Says nothing about leads — matching happens in Dart.
@immutable
class DetectedCall {
  const DetectedCall({
    required this.number,
    required this.isInbound,
    required this.durationSeconds,
    required this.endedAt,
  });

  final String number;
  final bool isInbound;

  /// 0 when the OS call log couldn't be read and only the ringing number was
  /// available — treat as unknown, not as "missed".
  final int durationSeconds;

  final DateTime endedAt;

  static DetectedCall? fromEvent(Object? event) {
    if (event is! Map) return null;
    final number = (event['number'] ?? '').toString();
    if (number.isEmpty) return null;
    final millis = (event['timestampMs'] as num?)?.toInt();
    return DetectedCall(
      number: number,
      isInbound: event['isInbound'] == true,
      durationSeconds: (event['durationSeconds'] as num?)?.toInt() ?? 0,
      endedAt: millis != null
          ? DateTime.fromMillisecondsSinceEpoch(millis)
          : DateTime.now(),
    );
  }
}

const _callEventsChannel = EventChannel('lead_pilot/call_events');

/// Calls ending on this phone, from whichever app placed them. Empty on any
/// platform but Android — no other OS exposes this to a third-party app.
final callDetectionEventsProvider = StreamProvider<DetectedCall>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const Stream<DetectedCall>.empty();
  }
  return _callEventsChannel
      .receiveBroadcastStream()
      .map(DetectedCall.fromEvent)
      .where((call) => call != null)
      .cast<DetectedCall>();
});
