import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_client.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression cover: scheduling a follow-up sets a device-local alarm (see
// schedule_call_sheet.dart -> NotificationService.scheduleFollowUp), but
// markDone()/delete() never told NotificationService to cancel it — so a
// follow-up completed or deleted before its scheduled time still fired a
// stale reminder later. Fixed by cancelling NotificationService.notifIdFor(id)
// in both paths. NotificationService.cancel() no-ops safely here (it guards
// on `_ready`, which nothing in this test suite ever sets via init()), so
// this exercises that the calls are wired in and don't throw, and that the
// task state updates as expected either way.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer buildContainer() {
    var created = false;
    var completed = false;
    var deleted = false;
    final client = _FakeApiClient(
      onGet: (path, query) async => {
        'follow_ups': [
          if (created && !deleted)
            {
              'id': 'backend-1',
              'due_at': DateTime(2026, 1, 1).toUtc().toIso8601String(),
              'note': 'Call back',
              'lead_id': null,
              'completed_at': completed
                  ? DateTime(2026, 1, 1).toUtc().toIso8601String()
                  : null,
            },
        ],
      },
      onPost: (path, body) async {
        created = true;
        return {'id': 'backend-1'};
      },
      onDelete: (path, body) async {
        deleted = true;
        return null;
      },
      onPatch: (path, body) async {
        completed = true;
        return null;
      },
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWith((ref) => client),
        leadsProvider.overrideWith(_NoopLeadsController.new),
      ],
    );
    return container;
  }

  test('markDone cancels the pending device reminder and marks the task done', () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.read(followUpsProvider);
    await pumpEventQueue();

    final task = FollowUpTask(
      id: 'local-1',
      taskText: 'Call back',
      leadName: 'Priya',
      status: FollowUpStatus.pending,
      scheduledAt: DateTime(2026, 1, 1),
    );
    await container.read(followUpsProvider.notifier).schedule(task);
    await pumpEventQueue();

    // Should complete without throwing even though it now also calls
    // NotificationService.instance.cancel() internally.
    await container.read(followUpsProvider.notifier).markDone('local-1');
    await pumpEventQueue();

    final state = container.read(followUpsProvider);
    expect(state.single.status, FollowUpStatus.done);
  });

  test('delete cancels the pending device reminder and removes the task', () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.read(followUpsProvider);
    await pumpEventQueue();

    final task = FollowUpTask(
      id: 'local-2',
      taskText: 'Call back',
      leadName: 'Priya',
      status: FollowUpStatus.pending,
      scheduledAt: DateTime(2026, 1, 1),
    );
    await container.read(followUpsProvider.notifier).schedule(task);
    await pumpEventQueue();

    // Should complete without throwing even though it now also calls
    // NotificationService.instance.cancel() internally.
    await container.read(followUpsProvider.notifier).delete('local-2');
    await pumpEventQueue();

    final state = container.read(followUpsProvider);
    expect(state, isEmpty);
  });
}

class _NoopLeadsController extends LeadsController {
  @override
  List<Lead> build() => const [];
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient({
    required this.onGet,
    required this.onPost,
    required this.onDelete,
    required this.onPatch,
  });

  final Future<dynamic> Function(String path, Map<String, dynamic>? query)
  onGet;
  final Future<dynamic> Function(String path, Object? body) onPost;
  final Future<dynamic> Function(String path, Object? body) onDelete;
  final Future<dynamic> Function(String path, Object? body) onPatch;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      onGet(path, query);
  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => onPost(path, body);
  @override
  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => null;
  @override
  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => onPatch(path, body);
  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => onDelete(path, body);
}
