import 'api_exception.dart';

/// Transport-agnostic contract for talking to the backend.
///
/// The app depends only on this interface — never on a concrete HTTP library —
/// so the transport (package:http, dio, Supabase, etc.) can be chosen later
/// without touching call sites. Each method returns the decoded JSON body
/// (typically a `Map<String, dynamic>` or `List<dynamic>`).
///
/// Implementations must throw [ApiException] on any failure.
abstract interface class ApiClient {
  Future<dynamic> get(String path, {Map<String, dynamic>? query});

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query});

  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query});

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query});

  Future<dynamic> delete(String path, {Object? body, Map<String, dynamic>? query});
}

/// Placeholder used until a real transport is wired.
///
/// Every call throws [ApiException], so accidentally switching
/// `ApiConfig.useMockData` to `false` before implementing a client fails loudly
/// instead of silently returning nothing.
///
/// To go live, add an HTTP package (e.g. `http` or `dio`) and implement
/// [ApiClient] against it — building requests with `ApiConfig.uri(...)` and
/// `ApiConfig.defaultHeaders`, decoding the body, and mapping non-2xx
/// responses and socket errors to [ApiException].
class UnimplementedApiClient implements ApiClient {
  const UnimplementedApiClient();

  Never _notWired(String method, String path) => throw ApiException(
    'No ApiClient transport wired yet. Implement ApiClient before calling '
    '$method $path. (See lib/src/core/api/api_client.dart)',
  );

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _notWired('GET', path);

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _notWired('POST', path);

  @override
  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _notWired('PUT', path);

  @override
  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _notWired('PATCH', path);

  @override
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => _notWired('DELETE', path);
}
