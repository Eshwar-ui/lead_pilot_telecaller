/// Normalized error surface for all backend calls.
///
/// Concrete [ApiClient] implementations should translate transport-specific
/// failures (socket errors, timeouts, non-2xx responses) into this type so the
/// rest of the app never depends on a particular HTTP library.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.cause});

  final String message;

  /// HTTP status code when the failure came from a response, else null.
  final int? statusCode;

  /// The underlying error (e.g. SocketException), when available.
  final Object? cause;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => (statusCode ?? 0) >= 500;

  @override
  String toString() =>
      'ApiException(${statusCode ?? 'network'}): $message';
}
