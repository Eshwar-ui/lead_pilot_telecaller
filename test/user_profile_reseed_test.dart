import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/session_store.dart';
import 'package:lead_pilot_telecaller/src/services/user_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Cover for UserProfileController's two contracts:
//
//  1. The cold-start RACE fix (the original reason this file exists) — the
//     controller listens to sessionProvider instead of reading it once.
//  2. Identity is owned by the SERVER. name/role/company always follow the
//     session and are never persisted locally, because the old "a local edit
//     wins" rule meant a founder correcting a telecaller's name from the
//     dashboard changed nothing on the device.
//
// Original race note: UserProfileController
// used to seed identity from sessionProvider with a single one-time read
// inside _load(), racing SessionController._restore() (both fire on cold
// start) — if the session hadn't finished restoring yet, the profile seeded
// from an empty session and never self-corrected for the rest of the run.
// Fixed by listening to sessionProvider and re-seeding on every change.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWith(_MutableFakeSession.new)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'profile stays at the placeholder while the session is still empty',
    () async {
      final container = buildContainer();
      container.read(userProfileProvider);
      await pumpEventQueue();

      final profile = container.read(userProfileProvider);
      expect(profile.name, 'Telecaller');
      expect(profile.company, '');
    },
  );

  test('re-seeds from the session once it becomes available after the profile '
      'already loaded — the exact race this fix addresses', () async {
    final container = buildContainer();

    // Profile loads first, while the session is still empty (the race).
    container.read(userProfileProvider);
    await pumpEventQueue();
    expect(container.read(userProfileProvider).name, 'Telecaller');

    // The session "finishes restoring" afterward.
    final sessionNotifier =
        container.read(sessionProvider.notifier) as _MutableFakeSession;
    sessionNotifier.setLoggedIn(
      const Session(
        token: 'tok-123',
        name: 'Priya Verma',
        role: 'telecaller',
        orgName: 'Acme Realty',
      ),
    );
    await pumpEventQueue();

    final profile = container.read(userProfileProvider);
    expect(profile.name, 'Priya Verma');
    expect(profile.role, 'Telecaller');
    expect(profile.company, 'Acme Realty');
  });

  test(
    'the server\'s name overrides a locally stored one — a founder\'s '
    'correction must not be shadowed by an old local edit',
    () async {
      // An install from before identity became server-owned still has a
      // locally edited name in SharedPreferences. It is read, then overridden.
      SharedPreferences.setMockInitialValues({
        'user_profile_v1':
            '{"name":"My Own Name","role":"Telecaller","company":"","language":"తె","notifications_enabled":true}',
      });
      final container = buildContainer();

      container.read(userProfileProvider);
      await pumpEventQueue();

      final sessionNotifier =
          container.read(sessionProvider.notifier) as _MutableFakeSession;
      sessionNotifier.setLoggedIn(
        const Session(token: 'tok-123', name: 'Corrected By Founder'),
      );
      await pumpEventQueue();

      expect(
        container.read(userProfileProvider).name,
        'Corrected By Founder',
        reason:
            'identity is owned by the server; the old "local edit wins" rule '
            'is exactly what made a founder\'s correction invisible here',
      );
    },
  );

  test('preferences are still persisted locally, identity is not', () async {
    final container = buildContainer();
    container.read(userProfileProvider);
    await pumpEventQueue();

    await container
        .read(userProfileProvider.notifier)
        .update(
          const UserProfile(
            name: 'Should Not Persist',
            language: 'हि',
            notificationsEnabled: false,
          ),
        );

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('user_profile_v1')!;
    expect(stored, contains('हि'));
    expect(stored, contains('notifications_enabled'));
    // The whole point: a name can no longer be written to the device and
    // outlive a change made on the server.
    expect(stored, isNot(contains('Should Not Persist')));
  });

  test(
    'logging out (session goes empty again) does not clobber the seeded name',
    () async {
      final container = buildContainer();
      container.read(userProfileProvider);
      await pumpEventQueue();

      final sessionNotifier =
          container.read(sessionProvider.notifier) as _MutableFakeSession;
      sessionNotifier.setLoggedIn(
        const Session(token: 'tok-123', name: 'Priya Verma'),
      );
      await pumpEventQueue();
      expect(container.read(userProfileProvider).name, 'Priya Verma');

      sessionNotifier.setLoggedIn(Session.empty);
      await pumpEventQueue();

      expect(
        container.read(userProfileProvider).name,
        'Priya Verma',
        reason:
            're-seeding on logout must be a no-op, not blank the name back out',
      );
    },
  );
}

class _MutableFakeSession extends SessionController {
  @override
  Session build() => Session.empty;

  void setLoggedIn(Session session) {
    state = session;
  }
}
