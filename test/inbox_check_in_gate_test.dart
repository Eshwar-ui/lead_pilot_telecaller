import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/attendance_record.dart';
import 'package:lead_pilot_telecaller/src/screens/home_screen.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';

// The Inbox now hides the lead list behind a check-in prompt. The dangerous
// direction is a false positive: blocking a telecaller out of their own leads
// because attendance couldn't be read (offline, backend down, still loading)
// would cost them a working day, which is far worse than a missed check-in.
// So the gate must close only on a record that positively says "not checked
// in", and stay open for every kind of not-knowing.
void main() {
  AttendanceRecord record({DateTime? checkInAt, String status = 'on_shift'}) =>
      AttendanceRecord(
        id: 'a1',
        date: '2026-09-06',
        checkInAt: checkInAt,
        status: status,
      );

  group('gate stays open when attendance is unknown', () {
    test('initial load, before the first fetch resolves', () {
      expect(
        inboxNeedsCheckIn(const AttendanceState(loading: true)),
        isFalse,
      );
    });

    test('the fetch failed — offline or backend down', () {
      expect(
        inboxNeedsCheckIn(const AttendanceState(error: 'Network unreachable')),
        isFalse,
      );
    });

    test('no record and nothing in flight', () {
      expect(inboxNeedsCheckIn(const AttendanceState()), isFalse);
    });
  });

  group('gate closes only on a record that says not checked in', () {
    test('today exists with no check-in yet', () {
      expect(
        inboxNeedsCheckIn(AttendanceState(record: record())),
        isTrue,
      );
    });

    test('an empty record from the backend still gates', () {
      expect(
        inboxNeedsCheckIn(AttendanceState(record: AttendanceRecord.empty())),
        isTrue,
      );
    });
  });

  group('gate opens once the day has started', () {
    test('checked in and on shift', () {
      expect(
        inboxNeedsCheckIn(
          AttendanceState(record: record(checkInAt: DateTime(2026, 9, 6, 9))),
        ),
        isFalse,
      );
    });

    test('checked out again — the list does not re-lock for the rest of the day', () {
      expect(
        inboxNeedsCheckIn(
          AttendanceState(
            record: record(
              checkInAt: DateTime(2026, 9, 6, 9),
              status: 'completed',
            ),
          ),
        ),
        isFalse,
      );
    });

    test('a forgotten checkout auto-closed by the backend also stays open', () {
      expect(
        inboxNeedsCheckIn(
          AttendanceState(
            record: record(
              checkInAt: DateTime(2026, 9, 6, 9),
              status: 'auto_closed',
            ),
          ),
        ),
        isFalse,
      );
    });
  });
}
