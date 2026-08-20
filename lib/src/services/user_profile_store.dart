import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_store.dart';

/// The telecaller's own profile, edited in-app and persisted locally.
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

  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'company': company,
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

  /// Seed identity from the authenticated session when the user hasn't
  /// personalised their profile yet (still the "Telecaller" placeholder), so
  /// the card shows who they actually logged in as — not a default. Once the
  /// user edits their profile, their chosen values win. A no-op on logout
  /// (session fields all empty, so every `isNotEmpty` check is false).
  void _reseedFromSession(Session session) {
    final sessionName = session.name?.trim() ?? '';
    final sessionRole = _prettyRole(session.role);
    final sessionCompany = session.orgName?.trim() ?? '';
    state = state.copyWith(
      name:
          (state.name.isEmpty || state.name == 'Telecaller') &&
              sessionName.isNotEmpty
          ? sessionName
          : state.name,
      role:
          (state.role.isEmpty || state.role == 'Telecaller') &&
              sessionRole.isNotEmpty
          ? sessionRole
          : state.role,
      company: state.company.isEmpty && sessionCompany.isNotEmpty
          ? sessionCompany
          : state.company,
    );
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

  Future<void> update(UserProfile profile) async {
    state = profile;
    await ref.read(userProfileStoreProvider).save(profile);
  }
}
