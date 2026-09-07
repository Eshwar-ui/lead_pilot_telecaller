import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/providers.dart';
import 'session_store.dart';

/// The telecaller's profile as shown on the Profile screen.
///
/// IDENTITY (name/role/company) is NOT editable here and NOT persisted
/// locally — it mirrors the authenticated session, which mirrors the server.
/// It used to be a local SharedPreferences copy the telecaller could edit,
/// which meant a founder correcting their name from the dashboard changed
/// nothing on the device: the stale local value shadowed the server's forever.
/// Only genuine device preferences (language, notifications) are stored here.
class UserProfile {
  const UserProfile({
    this.name = 'Telecaller',
    this.role = 'Telecaller',
    this.company = '',
    this.language = 'తె',
    this.notificationsEnabled = true,
  });

  final String name;
  final String role;
  final String company;
  final String language;
  final bool notificationsEnabled;

  UserProfile copyWith({
    String? name,
    String? role,
    String? company,
    String? language,
    bool? notificationsEnabled,
  }) => UserProfile(
    name: name ?? this.name,
    role: role ?? this.role,
    company: company ?? this.company,
    language: language ?? this.language,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
  );

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name: j['name'] as String? ?? 'Telecaller',
    role: j['role'] as String? ?? 'Telecaller',
    company: j['company'] as String? ?? '',
    language: j['language'] as String? ?? 'తె',
    notificationsEnabled: j['notifications_enabled'] as bool? ?? true,
  );

  /// Only the device-local PREFERENCES are persisted. name/role/company are
  /// deliberately absent: they're re-derived from the session on every load,
  /// so a stale copy can never outlive a change made on the server.
  Map<String, dynamic> toJson() => {
    'language': language,
    'notifications_enabled': notificationsEnabled,
  };
}

class UserProfileStore {
  static const _key = 'user_profile_v1';

  Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const UserProfile();
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserProfile();
    }
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }
}

final userProfileStoreProvider = Provider<UserProfileStore>(
  (_) => UserProfileStore(),
);

final userProfileProvider =
    NotifierProvider<UserProfileController, UserProfile>(
      UserProfileController.new,
    );

class UserProfileController extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    _load();
    // Re-seed whenever the session changes, not just once at boot —
    // `_load()`'s original one-time read raced `SessionController._restore()`
    // (both fire on cold start), so a profile loaded before the session
    // finished restoring would seed from an empty session and never
    // self-correct for the rest of the run. Listening here covers restore
    // completing, login, and logout, all with the same idempotent logic.
    ref.listen(sessionProvider, (previous, next) => _reseedFromSession(next));
    return const UserProfile();
  }

  Future<void> _load() async {
    final stored = await ref.read(userProfileStoreProvider).load();
    state = stored;
    _reseedFromSession(ref.read(sessionProvider));
  }

  /// Take identity from the authenticated session — ALWAYS, not just while the
  /// local value is still a placeholder.
  ///
  /// The previous "only if unset" rule is exactly what made a founder's
  /// correction invisible: once the telecaller had edited their own name, the
  /// local value won permanently and the server's name was never shown again.
  /// The session is refreshed from `GET /api/auth/me` when the Profile screen
  /// opens, so this reflects an edit made on the dashboard.
  ///
  /// A no-op on logout: the session's fields are all empty then, and each
  /// falls back to the current value rather than blanking the card mid-teardown.
  void _reseedFromSession(Session session) {
    final sessionName = session.name?.trim() ?? '';
    final sessionRole = _prettyRole(session.role);
    final sessionCompany = session.orgName?.trim() ?? '';
    state = state.copyWith(
      name: sessionName.isNotEmpty ? sessionName : state.name,
      role: sessionRole.isNotEmpty ? sessionRole : state.role,
      company: sessionCompany.isNotEmpty ? sessionCompany : state.company,
    );
  }

  /// Pull the authoritative user record and fold it into the session, so a
  /// name/email the founder changed on the dashboard appears here without the
  /// telecaller logging out. Fail-soft: on any error the card simply keeps
  /// showing the session's existing (login-time) values.
  Future<void> refreshFromServer() async {
    if (!ref.read(sessionProvider).isLoggedIn) return;
    try {
      final user = await ref.read(orgProfileRepositoryProvider).me();
      await ref.read(sessionProvider.notifier).refreshIdentity(user);
    } catch (_) {
      /* offline or backend down — keep what we have */
    }
  }

  /// "telecaller" -> "Telecaller", "ad_manager" -> "Ad Manager".
  static String _prettyRole(String? role) {
    if (role == null || role.isEmpty) return '';
    return role
        .split(RegExp(r'[_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Persist a PREFERENCE change (language, notifications). Identity fields on
  /// `profile` are ignored on the way to storage — see [UserProfile.toJson] —
  /// and re-derived from the session on the next load.
  Future<void> update(UserProfile profile) async {
    state = profile;
    await ref.read(userProfileStoreProvider).save(profile);
  }
}
