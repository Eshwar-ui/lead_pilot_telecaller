import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_client.dart';
import 'package:lead_pilot_telecaller/src/models/lead.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression cover for FollowUpController's double-load race fix.
// schedule() fires _load() twice: immediately after the local add, then
// again once the backend id comes back. If the first, slower call's remote
// round-trip finished AFTER the second, its `state = reconciled` — computed
// from a local snapshot taken BEFORE the backendId was ever assigned — used
// to silently overwrite the correct, backendId-bearing state. Fixed with a
// generation counter: a superseded _load() call detects it's stale and
// drops its result instead of writing it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'a slow first _load() does not overwrite the state a later one already set',
    () async {
      var blockNextGet = false;
      final gate = Completer<void>();
      var created = false;

      final client = _FakeApiClient(
        onGet: (path, query) async {
          if (blockNextGet) {
            blockNextGet = false;
            await gate.future;
          }
          // Mirrors a real backend: the follow-up shows up in list() once
          // create() has actually been called.
          return {
            'follow_ups': [
              if (created)
                {
                  'id': 'backend-1',
                  'due_at': DateTime(2026, 1, 1).toUtc().toIso8601String(),
                  'note': 'Call back',
                  'lead_id': null,
                },
            ],
          };
        },
        onPost: (path, body) async {
          created = true;
          return {'id': 'backend-1'};
        },
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWith((ref) => client),
          leadsProvider.overrideWith(_NoopLeadsController.new),
        ],
      );
      addTearDown(container.dispose);

      // Settle build()'s own initial _load() first, unblocked, so it doesn't
      // interfere with the gated call below.
      container.read(followUpsProvider);
      await pumpEventQueue();

      final task = FollowUpTask(
        id: 'local-1',
        taskText: 'Call back',
        leadName: 'Priya',
        status: FollowUpStatus.pending,
        scheduledAt: DateTime(2026, 1, 1),
      );

      // schedule() fires _load() #1 (gated — blocks on `gate` reading the
      // remote list from a LOCAL SNAPSHOT TAKEN BEFORE THE BACKEND ID EXISTS),
      // then the create() POST resolves, backendId is persisted locally, and
      // _load() #2 fires (unblocked — completes fully before we release #1).
      blockNextGet = true;
      await container.read(followUpsProvider.notifier).schedule(task);
      await pumpEventQueue();

      final afterSecondLoad = container.read(followUpsProvider);
      expect(afterSecondLoad, hasLength(1));
      expect(
        afterSecondLoad.single.backendId,
        'backend-1',
        reason: '_load() #2 should have set the backendId-bearing state',
      );

      // Now release the stale _load() #1 — its reconcile runs against the
      // pre-backendId local snapshot it captured earlier.
      gate.complete();
      await pumpEventQueue();

      final afterStaleLoad = container.read(followUpsProvider);
      expect(afterStaleLoad, hasLength(1));
      expect(
        afterStaleLoad.single.backendId,
        'backend-1',
        reason:
            'the superseded _load() #1 must not revert the backendId once it finally resolves',
      );
    },
  );
}

class _NoopLeadsController extends LeadsController {
  @override
  List<Lead> build() => const [];
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient({required this.onGet, required this.onPost});

  final Future<dynamic> Function(String path, Map<String, dynamic>? query)
  onGet;
  final Future<dynamic> Function(String path, Object? body) onPost;

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
  }) async => null;
  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => null;
}
