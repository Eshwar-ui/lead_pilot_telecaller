import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/session_store.dart';
import 'package:lead_pilot_telecaller/src/services/user_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression cover for the user_profile_store race fix: UserProfileController
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
    'a session name is not applied once the user has personalised their own name',
    () async {
      // Pre-seed a stored profile with a real (non-placeholder) name.
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
        const Session(token: 'tok-123', name: 'Session Name'),
      );
      await pumpEventQueue();

      expect(
        container.read(userProfileProvider).name,
        'My Own Name',
        reason: "the user's own edited name must win over the session's",
      );
    },
  );

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
