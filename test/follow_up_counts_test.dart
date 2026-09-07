import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/screens/follow_ups_screen.dart';

// Regression cover: the "Due Today" tile counted every task that was merely
// not-overdue — `status == pending` — so a telecaller with two calls booked
// for today and ten for next week read "12 due today", while the Today tab
// directly beneath it listed two. The Inbox's own Follow-ups Due tile
// disagreed with it as well. These pin the tile to what its label says, and
// to what the Today tab lists.
void main() {
  FollowUpTask task({
    required FollowUpStatus status,
    bool dueToday = false,
    String id = 't',
  }) => FollowUpTask(
    id: id,
    taskText: 'Call back',
    leadName: 'Priya',
    status: status,
    dueToday: dueToday,
  );

  test('later-dated pending tasks are not counted as due today', () {
    final counts = followUpCounts([
      task(status: FollowUpStatus.pending, dueToday: true, id: 'a'),
      task(status: FollowUpStatus.pending, dueToday: true, id: 'b'),
      for (var i = 0; i < 10; i++)
        task(status: FollowUpStatus.pending, id: 'later$i'),
    ]);

    expect(counts.dueToday, 2, reason: 'the ten next-week tasks are not today');
    expect(counts.overdue, 0);
    expect(counts.done, 0);
  });

  test('due today matches exactly what the Today tab lists', () {
    // The Today tab filters on `t.dueToday`, and marking a task done clears
    // that flag (see local_follow_up_store / reconcileFollowUps).
    final tasks = [
      task(status: FollowUpStatus.pending, dueToday: true, id: 'a'),
      task(status: FollowUpStatus.overdue, dueToday: true, id: 'b'),
      task(status: FollowUpStatus.pending, id: 'c'),
      task(status: FollowUpStatus.done, id: 'd'),
    ];

    expect(followUpCounts(tasks).dueToday, tasks.where((t) => t.dueToday).length);
  });

  test('a task due earlier today counts as both overdue and due today', () {
    final counts = followUpCounts([
      task(status: FollowUpStatus.overdue, dueToday: true),
    ]);

    expect(counts.overdue, 1);
    expect(counts.dueToday, 1);
  });

  test('an overdue task from a previous day is not due today', () {
    final counts = followUpCounts([task(status: FollowUpStatus.overdue)]);

    expect(counts.overdue, 1);
    expect(counts.dueToday, 0);
  });

  test('done tasks count only as done, never as overdue or due today', () {
    // dueToday is cleared on completion, but the guard is explicit so a
    // stale flag arriving from a sync cannot inflate today's workload.
    final counts = followUpCounts([
      task(status: FollowUpStatus.done, dueToday: true, id: 'a'),
      task(status: FollowUpStatus.done, id: 'b'),
    ]);

    expect(counts.done, 2);
    expect(counts.dueToday, 0);
    expect(counts.overdue, 0);
  });

  test('an empty list is all zeroes', () {
    final counts = followUpCounts(const []);

    expect(counts.overdue, 0);
    expect(counts.dueToday, 0);
    expect(counts.done, 0);
  });
}
