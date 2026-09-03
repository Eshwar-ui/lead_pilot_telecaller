import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// Concrete [ApiClient] backed by `package:http`.
///
/// Builds URLs with [ApiConfig.uri], attaches [ApiConfig.defaultHeaders],
/// decodes JSON bodies, and maps every transport failure (socket errors,
/// timeouts, non-2xx responses) to [ApiException] so callers never depend on
/// the HTTP library.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    http.Client? client,
    this.getToken,
    this.onConnectivityOk,
    this.onConnectivityIssue,
    this.onUnauthorized,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// The only endpoints this backend accepts with no bearer token. Every
  /// other route requires `Depends(get_current_user)` — so any other request
  /// fired while logged out would just round-trip to a 401 "missing token"
  /// anyway. This is why: right after logout, [SessionController.logout]
  /// clears the token, then its caller invalidates ~10 providers whose
  /// `build()`/`_load()` unconditionally re-fetch from the backend — those
  /// fetches used to fire with no token and surface as a scary raw 401. Now
  /// they fail fast, locally, with no network round-trip, and are caught by
  /// the same fail-soft try/catch every controller already has.
  static const _publicPaths = {'/api/auth/login', '/api/auth/register'};

  /// Returns the current session's JWT, or null when logged out. Read fresh
  /// on every request (not captured once) so login/logout during the app's
  /// lifetime takes effect immediately — see `session_store.dart`.
  final String? Function()? getToken;

  /// Called whenever a request proves the server is reachable — any HTTP
  /// response below 500, even a 4xx application error, means the backend is
  /// up. Drives the global "server unreachable" banner (see
  /// `serverReachableProvider`).
  final void Function()? onConnectivityOk;

  /// Called whenever a request fails to reach the server at all (timeout,
  /// socket error, DNS/transport failure) or the server itself is erroring
  /// (5xx) — as opposed to a normal 4xx application error, which still
  /// proves connectivity.
  final void Function()? onConnectivityIssue;

  /// Called when a request that *carried a bearer token* comes back 401 —
  /// i.e. a previously-valid session's token has been rejected (expired,
  /// signing-secret rotated on the backend, etc.), as opposed to a login
  /// attempt with no token yet or a wrong-password 401 from `/api/auth/login`
  /// (neither of those carries a token, so neither fires this). Lets the app
  /// force a clean logout instead of leaving a dead token in place forever —
  /// individual screens otherwise either surface a raw "expired" error
  /// (Attendance) or silently fall back to stale/mock data (Leads) with no
  /// way to recover short of the user manually logging out.
  final void Function()? onUnauthorized;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  @override
  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send('POST', path, body: body, query: query);

  @override
  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send('PUT', path, body: body, query: query);

  @override
  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send('PATCH', path, body: body, query: query);

  @override
  Future<dynamic> delete(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send('DELETE', path, body: body, query: query);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final token = getToken?.call();
    if (token == null && !_publicPaths.contains(path)) {
      // Fail fast, no network call — this path needs auth and there's no
      // token right now (logged out, or a stale fetch racing a fresh
      // logout). Same ApiException type every caller's fail-soft catch
      // already handles, just without the pointless round-trip to a 401.
      throw const ApiException('Not signed in', statusCode: 401);
    }
    final uri = ApiConfig.uri(path, query: query);
    final request = http.Request(method, uri)
      ..headers.addAll(ApiConfig.defaultHeaders);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed = await _client.send(request).timeout(ApiConfig.timeout);
      final response =
          await http.Response.fromStream(streamed).timeout(ApiConfig.timeout);
      // Any response at all — even a 4xx application error — proves the
      // server is reachable; only 5xx counts as a server-side connectivity
      // issue (see _decode).
      if (response.statusCode < 500) {
        onConnectivityOk?.call();
      } else {
        onConnectivityIssue?.call();
      }
      if (response.statusCode == 401 && token != null) {
        onUnauthorized?.call();
      }
      return _decode(response, method, path);
    } on TimeoutException catch (e) {
      onConnectivityIssue?.call();
      throw ApiException('Request timed out: $method $path', cause: e);
    } on SocketException catch (e) {
      onConnectivityIssue?.call();
      throw ApiException(
        'Network error reaching ${ApiConfig.baseUrl}. Is the backend running '
        'and on the same network? ($method $path)',
        cause: e,
      );
    } on http.ClientException catch (e) {
      onConnectivityIssue?.call();
      throw ApiException('Transport error: ${e.message}', cause: e);
    }
  }

  dynamic _decode(http.Response response, String method, String path) {
    final code = response.statusCode;
    final isJson =
        (response.headers['content-type'] ?? '').contains('application/json');
    dynamic decoded;
    if (response.body.isNotEmpty && isJson) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
    }

    if (code >= 200 && code < 300) {
      return decoded ?? (response.body.isEmpty ? null : response.body);
    }

    // FastAPI errors come back as {"detail": "..."}.
    final detail = decoded is Map && decoded['detail'] != null
        ? decoded['detail'].toString()
        : response.body.isNotEmpty
            ? response.body
            : 'HTTP $code';
    throw ApiException(
      '$method $path failed: $detail',
      statusCode: code,
      detail: detail,
    );
  }
}
