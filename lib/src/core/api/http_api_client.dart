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
  HttpApiClient({http.Client? client, this.getToken}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Returns the current session's JWT, or null when logged out. Read fresh
  /// on every request (not captured once) so login/logout during the app's
  /// lifetime takes effect immediately — see `session_store.dart`.
  final String? Function()? getToken;

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
    final uri = ApiConfig.uri(path, query: query);
    final request = http.Request(method, uri)
      ..headers.addAll(ApiConfig.defaultHeaders);
    final token = getToken?.call();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed = await _client.send(request).timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response, method, path);
    } on TimeoutException catch (e) {
      throw ApiException('Request timed out: $method $path', cause: e);
    } on SocketException catch (e) {
      throw ApiException(
        'Network error reaching ${ApiConfig.baseUrl}. Is the backend running '
        'and on the same network? ($method $path)',
        cause: e,
      );
    } on http.ClientException catch (e) {
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
    );
  }
}
