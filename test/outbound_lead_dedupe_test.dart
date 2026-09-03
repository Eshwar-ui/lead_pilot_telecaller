import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_client.dart';
import 'package:lead_pilot_telecaller/src/core/api/api_endpoints.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';

// OutboundLeadDraftController.updatePhone's debounced dedupe() check was
// previously dead code — LeadRepository.dedupe() existed but nothing ever
// called it, so the "already in your leads" banner on the outbound-lead form
// could never render. This covers the debounce/cancel/clear behavior added
// to wire it up.
//
// This probe is now only the EARLY warning: saving a duplicate is rejected by
// the backend with a 409 regardless, so a telecaller who types fast, is
// offline while typing, or loses a race with a teammate still cannot create a
// second lead for one number. The last two tests here cover the pieces that
// serve that path — naming the existing lead's owner, and re-running the probe
// on demand after a rejected save so the banner and its tap-through appear for
// a check that never got to run.
void main() {
  ProviderContainer buildContainer(_FakeApiClient client) {
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => client)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a full 10-digit number triggers a debounced dedupe check that '
      'flags a match', () async {
    var callCount = 0;
    final client = _FakeApiClient((query) async {
      callCount++;
      return {
        'duplicate': true,
        'contact_key': 'existing-1',
        'name': 'Existing Lead',
      };
    });
    final container = buildContainer(client);

    container
        .read(outboundLeadDraftProvider.notifier)
        .updatePhone('+919876543210');

    // Debounced — must not have fired yet immediately after typing.
    expect(callCount, 0);
    expect(container.read(outboundLeadDraftProvider).hasDuplicate, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(callCount, 1);
    final draft = container.read(outboundLeadDraftProvider);
    expect(draft.hasDuplicate, isTrue);
    expect(draft.dedupeContactKey, 'existing-1');
  });

  test('the existing lead\'s owner is carried into the draft', () async {
    // Without the owner, the banner tells a telecaller the number is "already
    // in your leads" when, under per-telecaller scoping, they may not be able
    // to open it at all — a dead end instead of "call Priya".
    final client = _FakeApiClient(
      (query) async => {
        'duplicate': true,
        'contact_key': 'existing-1',
        'name': 'Existing Lead',
        'assigned_to_name': 'Priya Nair',
      },
    );
    final container = buildContainer(client);

    container
        .read(outboundLeadDraftProvider.notifier)
        .updatePhone('+919876543210');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(
      container.read(outboundLeadDraftProvider).dedupeOwnerName,
      'Priya Nair',
    );
  });

  test('refreshDedupe checks immediately, skipping the debounce', () async {
    // Called after the backend rejects a save as a duplicate: the banner has
    // to appear now, not 500ms later, and without waiting for another
    // keystroke that may never come.
    var callCount = 0;
    final client = _FakeApiClient((query) async {
      callCount++;
      return {'duplicate': true, 'contact_key': 'existing-1'};
    });
    final container = buildContainer(client);
    final notifier = container.read(outboundLeadDraftProvider.notifier);

    notifier.updatePhone('+919876543210');
    expect(callCount, 0, reason: 'the debounce has not fired yet');

    await notifier.refreshDedupe();

    expect(callCount, 1);
    final draft = container.read(outboundLeadDraftProvider);
    expect(draft.hasDuplicate, isTrue);
    expect(draft.dedupeContactKey, 'existing-1');
  });

  test('fewer than 10 digits never triggers a dedupe check', () async {
    var callCount = 0;
    final client = _FakeApiClient((query) async {
      callCount++;
      return {'duplicate': false};
    });
    final container = buildContainer(client);

    container.read(outboundLeadDraftProvider.notifier).updatePhone('98765');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(callCount, 0);
    expect(container.read(outboundLeadDraftProvider).hasDuplicate, isFalse);
  });

  test('a no-match response leaves hasDuplicate false', () async {
    final client = _FakeApiClient((query) async => {'duplicate': false});
    final container = buildContainer(client);

    container
        .read(outboundLeadDraftProvider.notifier)
        .updatePhone('+919876543210');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final draft = container.read(outboundLeadDraftProvider);
    expect(draft.hasDuplicate, isFalse);
    expect(draft.dedupeContactKey, isNull);
  });

  test(
    'rapid re-typing cancels the earlier debounce — only the final number is checked',
    () async {
      final queriedNumbers = <String?>[];
      final client = _FakeApiClient((query) async {
        queriedNumbers.add(query?['phone']);
        return {'duplicate': false};
      });
      final container = buildContainer(client);
      final notifier = container.read(outboundLeadDraftProvider.notifier);

      notifier.updatePhone('+919876543210');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      notifier.updatePhone(
        '+919876543211',
      ); // still typing — supersedes the first
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(
        queriedNumbers,
        hasLength(1),
        reason: 'the superseded debounce must have been cancelled',
      );
      expect(queriedNumbers.single, '+919876543211');
    },
  );

  test(
    'editing the phone again immediately clears a stale duplicate flag',
    () async {
      final client = _FakeApiClient(
        (query) async => {'duplicate': true, 'contact_key': 'existing-1'},
      );
      final container = buildContainer(client);
      final notifier = container.read(outboundLeadDraftProvider.notifier);

      notifier.updatePhone('+919876543210');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(outboundLeadDraftProvider).hasDuplicate, isTrue);

      // Edit again — must clear synchronously, not wait for the next debounce.
      notifier.updatePhone('+919876543210x');
      expect(container.read(outboundLeadDraftProvider).hasDuplicate, isFalse);
      expect(
        container.read(outboundLeadDraftProvider).dedupeContactKey,
        isNull,
      );
    },
  );
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this._onGet);
  final Future<dynamic> Function(Map<String, dynamic>? query) _onGet;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    if (path != ApiEndpoints.dedupeLead) {
      throw StateError('Unexpected GET to $path');
    }
    return _onGet(query);
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => null;
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
