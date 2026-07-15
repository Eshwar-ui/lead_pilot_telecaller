import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';

/// Builds a local FollowUpTask (the shape LocalFollowUpStore holds).
FollowUpTask local(
  String id, {
  String? backendId,
  FollowUpStatus status = FollowUpStatus.pending,
  String leadName = 'Priya',
}) =>
    FollowUpTask(
      id: id,
      backendId: backendId,
      taskText: 'Call back',
      leadName: leadName,
      status: status,
      scheduledAt: DateTime(2026, 1, 1),
    );

/// Builds a backend FollowUpTask (the shape FollowUpRepository.list returns:
/// distinct `srv_` id, leadName defaulting to the lead_id slug).
FollowUpTask remote(
  String backendId, {
  FollowUpStatus status = FollowUpStatus.pending,
  String? leadId,
}) =>
    FollowUpTask(
      id: 'srv_$backendId',
      backendId: backendId,
      taskText: 'Call back',
      leadName: leadId ?? '',
      leadId: leadId,
      status: status,
      scheduledAt: DateTime(2026, 1, 1),
    );

void main() {
  group('reconcileFollowUps', () {
    test('propagates a done marked on another device', () {
      final result = reconcileFollowUps(
        [local('a', backendId: 'b1', status: FollowUpStatus.pending)],
        [remote('b1', status: FollowUpStatus.done)],
        const {},
      );
      expect(result, hasLength(1));
      expect(result.single.status, FollowUpStatus.done);
    });

    test('drops a task deleted on another device', () {
      final result = reconcileFollowUps(
        [local('a', backendId: 'b1')],
        const [], // backend no longer has it
        const {},
      );
      expect(result, isEmpty);
    });

    test('keeps a never-synced local-only task (no backendId)', () {
      final result = reconcileFollowUps(
        [local('a')], // backendId == null
        const [],
        const {},
      );
      expect(result, hasLength(1));
      expect(result.single.id, 'a');
    });

    test('adds a backend-only task created elsewhere', () {
      final result = reconcileFollowUps(
        const [],
        [remote('b1')],
        const {},
      );
      expect(result, hasLength(1));
      expect(result.single.backendId, 'b1');
    });

    test('done is sticky — a local done is not reverted by a stale remote', () {
      // Local marked done but the backend fetch still shows pending (sync not
      // yet landed). Must stay done, not flip back.
      final result = reconcileFollowUps(
        [local('a', backendId: 'b1', status: FollowUpStatus.done)],
        [remote('b1', status: FollowUpStatus.pending)],
        const {},
      );
      expect(result.single.status, FollowUpStatus.done);
    });

    test('resolves the real lead name for a backend-only task', () {
      final result = reconcileFollowUps(
        const [],
        [remote('b1', leadId: 'priya_sharma')],
        {
          'priya_sharma': Lead.empty().copyWithName('Priya Sharma'),
        },
      );
      expect(result.single.leadName, 'Priya Sharma');
    });

    test('no duplication when the same task is on both sides', () {
      final result = reconcileFollowUps(
        [local('a', backendId: 'b1')],
        [remote('b1')],
        const {},
      );
      expect(result, hasLength(1));
    });
  });
}

/// Tiny helper so the lead-name test doesn't depend on the full Lead ctor.
extension on Lead {
  Lead copyWithName(String name) => Lead(
        id: id,
        name: name,
        phone: phone,
        score: score,
        temperature: temperature,
        source: source,
        intent: intent,
        lastContact: lastContact,
        totalCalls: totalCalls,
        averageScore: averageScore,
        memory: memory,
        script: script,
        objections: objections,
        checklist: checklist,
        history: history,
      );
}
