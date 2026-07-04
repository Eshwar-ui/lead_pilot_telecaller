import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The logged-in telecaller's identity + JWT. Models server identity (who is
/// this, what org, what role) — deliberately separate from
/// `user_profile_store.dart`, which only models local display preferences.
class Session {
  const Session({this.token, this.userId, this.name, this.email, this.role, this.orgName});

  final String? token;
  final String? userId;
  final String? name;
  final String? email;
  final String? role;
  final String? orgName;

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
  }

  /// Called after a successful `POST /api/auth/login` with the raw response.
  Future<void> setSession({required String token, required Map<String, dynamic> user}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
    state = _sessionFrom(token, user);
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    state = Session.empty;
  }

  static Session _sessionFrom(String token, Map<String, dynamic> user) => Session(
    token: token,
    userId: user['id'] as String?,
    name: user['name'] as String?,
    email: user['email'] as String?,
    role: user['role'] as String?,
    orgName: user['org_name'] as String?,
  );
}

final sessionProvider = NotifierProvider<SessionController, Session>(SessionController.new);
