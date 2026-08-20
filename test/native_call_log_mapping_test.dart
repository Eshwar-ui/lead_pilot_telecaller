import 'package:call_log/call_log.dart' as device_call_log;
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/native_call_log_service.dart';

// NativeCallLogService.toAppEntry/isInboundCallType map the device's real
// call log into this app's domain model. fetchSince() itself can't be unit
// tested (real permission_handler/call_log platform channels), so this
// covers the pure mapping logic directly.
void main() {
  group('NativeCallLogService.isInboundCallType', () {
    test('outgoing and wifiOutgoing are not inbound', () {
      expect(
        NativeCallLogService.isInboundCallType(
          device_call_log.CallType.outgoing,
        ),
        isFalse,
      );
      expect(
        NativeCallLogService.isInboundCallType(
          device_call_log.CallType.wifiOutgoing,
        ),
        isFalse,
      );
    });

    test('incoming, missed, rejected, and null all read as inbound', () {
      expect(
        NativeCallLogService.isInboundCallType(
          device_call_log.CallType.incoming,
        ),
        isTrue,
      );
      expect(
        NativeCallLogService.isInboundCallType(device_call_log.CallType.missed),
        isTrue,
      );
      expect(
        NativeCallLogService.isInboundCallType(
          device_call_log.CallType.rejected,
        ),
        isTrue,
      );
      expect(NativeCallLogService.isInboundCallType(null), isTrue);
    });
  });

  group('NativeCallLogService.toAppEntry', () {
    test('maps a normal outgoing entry', () {
      final entry = NativeCallLogService.toAppEntry(
        device_call_log.CallLogEntry(
          id: 'dev-1',
          name: 'Priya Verma',
          number: '+919876543210',
          callType: device_call_log.CallType.outgoing,
          duration: 125,
          timestamp: 1755600000000,
        ),
      );

      expect(entry, isNotNull);
      expect(entry!.leadName, 'Priya Verma');
      expect(entry.phone, '+919876543210');
      expect(entry.duration, const Duration(seconds: 125));
      expect(entry.isInbound, isFalse);
      expect(entry.deviceCallId, 'dev-1');
      expect(
        entry.calledAt,
        DateTime.fromMillisecondsSinceEpoch(1755600000000),
      );
    });

    test('falls back to the phone number as the display name when the '
        'device has no contact name for it', () {
      final entry = NativeCallLogService.toAppEntry(
        device_call_log.CallLogEntry(
          number: '+919876543210',
          callType: device_call_log.CallType.incoming,
          timestamp: 1755600000000,
        ),
      );

      expect(entry!.leadName, '+919876543210');
    });

    test('an empty-string name also falls back to the phone number', () {
      final entry = NativeCallLogService.toAppEntry(
        device_call_log.CallLogEntry(
          name: '',
          number: '+919876543210',
          timestamp: 1755600000000,
        ),
      );

      expect(entry!.leadName, '+919876543210');
    });

    test('a missing duration defaults to zero, not a crash', () {
      final entry = NativeCallLogService.toAppEntry(
        device_call_log.CallLogEntry(
          number: '+919876543210',
          timestamp: 1755600000000,
        ),
      );

      expect(entry!.duration, Duration.zero);
    });

    test('a null number is dropped (unmappable entry)', () {
      final entry = NativeCallLogService.toAppEntry(
        device_call_log.CallLogEntry(timestamp: 1755600000000),
      );
      expect(entry, isNull);
    });

    test('an empty number is dropped (unmappable entry)', () {
      final entry = NativeCallLogService.toAppEntry(
        device_call_log.CallLogEntry(number: '', timestamp: 1755600000000),
      );
      expect(entry, isNull);
    });

    test('a null timestamp is dropped (unmappable entry)', () {
      final entry = NativeCallLogService.toAppEntry(
        device_call_log.CallLogEntry(number: '+919876543210'),
      );
      expect(entry, isNull);
    });
  });
}
