import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_notification_service.dart';

/// The logged-in telecaller's identity + JWT. Models server identity (who is
/// this, what org, what role) — deliberately separate from
/// `user_profile_store.dart`, which only models local display preferences.
class Session {
  const Session({
    this.token,
    this.userId,
    this.name,
    this.email,
    this.role,
    this.orgName,
    this.mustResetPassword = false,
  });

  final String? token;
  final String? userId;
  final String? name;
  final String? email;
  final String? role;
  final String? orgName;
  final bool mustResetPassword;

  bool get isLoggedIn => token != null;

  static const empty = Session();
}

/// Persists the session in the platform keychain/keystore (not
/// SharedPreferences — a JWT is a real secret) and exposes it reactively so
/// the router and [HttpApiClient] can read the current token.
class SessionController extends Notifier<Session> {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'leadpilot_token';
  static const _userKey = 'leadpilot_user';

  @override
  Session build() {
    // Fire-and-forget: state starts empty (logged-out) and updates once the
    // stored session (if any) has been read back from secure storage.
    unawaited(_restore());
    return Session.empty;
  }

  Future<void> _restore() async {
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    if (token == null || userJson == null) return;
    final user = jsonDecode(userJson) as Map<String, dynamic>;
    state = _sessionFrom(token, user);
    // Also covers a cold app start with an already-logged-in session (not
    // just a fresh login below) — the backend's stored FCM token could be
    // stale from a reinstall, or never set if this device registered before
    // push notifications existed.
    unawaited(PushNotificationService.instance.registerTokenIfNeeded(token));
  }

  /// Called after a successful `POST /api/auth/login` with the raw response.
  Future<void> setSession({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
    state = _sessionFrom(token, user);
    unawaited(PushNotificationService.instance.registerTokenIfNeeded(token));
  }

  /// Clears the JWT/user secret from secure storage *and* every locally
  /// persisted account-scoped cache (profile, leads, follow-ups, calls,
  /// pipeline stages, …) — none of those SharedPreferences keys are
  /// namespaced by user id, so a stale value would otherwise leak into the
  /// next account that logs in on this device. Call sites must also
  /// `ref.invalidate` the corresponding Riverpod providers so their
  /// in-memory state (already read from the now-cleared prefs) drops too.
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    state = Session.empty;
  }

  /// Called after a successful `POST /api/auth/change-password` so the
  /// session's `mustResetPassword` clears without a full logout/re-login.
  Future<void> clearMustResetPassword() async {
    // Read the token fresh from storage rather than trusting `state.token!` —
    // a concurrent force-logout (401 elsewhere) can clear storage between
    // this call starting and finishing, and force-unwrapping a cleared token
    // would throw instead of just no-op'ing like the rest of this method.
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    if (token == null || userJson == null) return;
    final user = jsonDecode(userJson) as Map<String, dynamic>;
    user['must_reset_password'] = false;
    await _storage.write(key: _userKey, value: jsonEncode(user));
    state = _sessionFrom(token, user);
  }

  static Session _sessionFrom(String token, Map<String, dynamic> user) =>
      Session(
        token: token,
        userId: user['id'] as String?,
        name: user['name'] as String?,
        email: user['email'] as String?,
        role: user['role'] as String?,
        orgName: user['org_name'] as String?,
        mustResetPassword: user['must_reset_password'] as bool? ?? false,
      );
}

final sessionProvider = NotifierProvider<SessionController, Session>(
  SessionController.new,
);
