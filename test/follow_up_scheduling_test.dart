import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/widgets/schedule_call_sheet.dart';

// buildFollowUpTask is the date/time math behind ScheduleCallSheet — pulled
// out of _ScheduleCallSheetState._save so the overdue/due-today
// classification (which decides whether a device notification is even
// scheduled) can be tested deterministically instead of racing the real
// DateTime.now().
void main() {
  final lead = Lead(
    id: 'lead1',
    name: 'Priya Verma',
    phone: '+919876543210',
    score: 70,
    temperature: LeadTemperature.warm,
    source: LeadSource.organic,
    intent: 'High Intent',
    lastContact: DateTime(2026, 1, 1),
    totalCalls: 0,
    averageScore: 0,
    memory: [],
    script: AiScript(
      generatedAgo: '',
      openingLine: '',
      keyPoints: [],
      steps: [],
    ),
    objections: [],
    checklist: [],
    history: [],
  );

  final now = DateTime(2026, 8, 20, 12, 0);

  test(
    'a future date/time is pending, not overdue, and due-today is false',
    () {
      final built = buildFollowUpTask(
        date: DateTime(2026, 8, 21),
        time: const TimeOfDay(hour: 10, minute: 0),
        noteText: '',
        lead: lead,
        id: 'id1',
        now: now,
      );
      expect(built.isOverdue, isFalse);
      expect(built.task.status, FollowUpStatus.pending);
      expect(built.task.dueToday, isFalse);
    },
  );

  test('a past time earlier today is overdue and due-today', () {
    final built = buildFollowUpTask(
      date: DateTime(2026, 8, 20),
      time: const TimeOfDay(hour: 9, minute: 0), // before `now`'s 12:00
      noteText: '',
      lead: lead,
      id: 'id2',
      now: now,
    );
    expect(built.isOverdue, isTrue);
    expect(built.task.status, FollowUpStatus.overdue);
    expect(built.task.dueToday, isTrue);
  });

  test('a later time today is pending and due-today, not overdue', () {
    final built = buildFollowUpTask(
      date: DateTime(2026, 8, 20),
      time: const TimeOfDay(hour: 15, minute: 0), // after `now`'s 12:00
      noteText: '',
      lead: lead,
      id: 'id3',
      now: now,
    );
    expect(built.isOverdue, isFalse);
    expect(built.task.status, FollowUpStatus.pending);
    expect(built.task.dueToday, isTrue);
  });

  test('an empty note falls back to a default task text', () {
    final built = buildFollowUpTask(
      date: DateTime(2026, 8, 21),
      time: const TimeOfDay(hour: 10, minute: 0),
      noteText: '   ',
      lead: lead,
      id: 'id4',
      now: now,
    );
    expect(built.task.taskText, 'Follow-up call with Priya Verma');
    expect(built.task.note, isNull);
  });

  test('a real note is trimmed and used as both taskText and note', () {
    final built = buildFollowUpTask(
      date: DateTime(2026, 8, 21),
      time: const TimeOfDay(hour: 10, minute: 0),
      noteText: '  Discuss pricing  ',
      lead: lead,
      id: 'id5',
      now: now,
    );
    expect(built.task.taskText, 'Discuss pricing');
    expect(built.task.note, 'Discuss pricing');
  });

  test('scheduledAt carries the lead id/name/phone through onto the task', () {
    final built = buildFollowUpTask(
      date: DateTime(2026, 8, 21),
      time: const TimeOfDay(hour: 10, minute: 30),
      noteText: '',
      lead: lead,
      id: 'id6',
      now: now,
    );
    expect(built.task.leadId, 'lead1');
    expect(built.task.leadName, 'Priya Verma');
    expect(built.task.phone, '+919876543210');
    expect(built.scheduledAt, DateTime(2026, 8, 21, 10, 30));
  });
}
