import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/notification_service.dart';

// A follow-up used to fire exactly one device reminder, at the appointed
// minute — no warning. It now fires three (an hour ahead, five minutes ahead,
// and on time), which means three notification ids per task instead of one.
// These cover the id arithmetic and the fire-time math, since getting either
// wrong is silent: alarms would collide, or a cancel would leave one behind to
// fire for work already done.
void main() {
  group('reminder ids', () {
    test('the three reminders of one task never collide', () {
      final ids = {
        for (final r in FollowUpReminder.values)
          NotificationService.notifIdFor('task-1', r),
      };
      expect(ids, hasLength(FollowUpReminder.values.length));
    });

    test('dueNow keeps the single-reminder id, so old alarms stay cancellable', () {
      expect(
        NotificationService.notifIdFor('task-1', FollowUpReminder.dueNow),
        NotificationService.notifIdFor('task-1'),
      );
      expect(
        NotificationService.notifIdFor('task-1'),
        'task-1'.hashCode.abs() % 100000,
      );
    });

    test('ids stay inside the 32-bit range Android notification ids require', () {
      // The worst case is the largest base id plus the largest offset.
      final worst =
          99999 +
          FollowUpReminder.values
              .map((r) => r.idOffset)
              .reduce((a, b) => a > b ? a : b);
      expect(worst, lessThan(1 << 31));
    });

    test('different tasks do not share an id for the same reminder', () {
      for (final r in FollowUpReminder.values) {
        expect(
          NotificationService.notifIdFor('task-a', r),
          isNot(NotificationService.notifIdFor('task-b', r)),
        );
      }
    });
  });

  group('fire times', () {
    final due = DateTime(2026, 9, 10, 15, 0);

    test('each reminder fires its stated distance ahead of the follow-up', () {
      expect(
        FollowUpReminder.hourBefore.fireTimeFor(due),
        DateTime(2026, 9, 10, 14, 0),
      );
      expect(
        FollowUpReminder.fiveMinutesBefore.fireTimeFor(due),
        DateTime(2026, 9, 10, 14, 55),
      );
      expect(FollowUpReminder.dueNow.fireTimeFor(due), due);
    });

    test('a follow-up booked 20 minutes out drops only the hour reminder', () {
      final now = DateTime(2026, 9, 10, 14, 40);
      final live = [
        for (final r in FollowUpReminder.values)
          if (r.fireTimeFor(due).isAfter(now)) r,
      ];
      expect(live, [
        FollowUpReminder.fiveMinutesBefore,
        FollowUpReminder.dueNow,
      ]);
    });

    test('a follow-up booked 2 minutes out keeps only the on-time reminder', () {
      final now = DateTime(2026, 9, 10, 14, 58);
      final live = [
        for (final r in FollowUpReminder.values)
          if (r.fireTimeFor(due).isAfter(now)) r,
      ];
      expect(live, [FollowUpReminder.dueNow]);
    });

    test('nothing fires for a follow-up already past', () {
      final now = DateTime(2026, 9, 10, 15, 1);
      final live = [
        for (final r in FollowUpReminder.values)
          if (r.fireTimeFor(due).isAfter(now)) r,
      ];
      expect(live, isEmpty);
    });
  });

  group('bodies', () {
    test('each reminder says how much warning it is giving', () {
      expect(FollowUpReminder.hourBefore.bodyFor('Call Priya'), contains('1 hour'));
      expect(
        FollowUpReminder.fiveMinutesBefore.bodyFor('Call Priya'),
        contains('5 minutes'),
      );
      expect(FollowUpReminder.dueNow.bodyFor('Call Priya'), contains('Due now'));
    });

    test('the task text survives into every body', () {
      for (final r in FollowUpReminder.values) {
        expect(r.bodyFor('Call Priya'), contains('Call Priya'));
      }
    });
  });
}
