import 'dart:async' show TimeoutException;

/// Normalized error surface for all backend calls.
///
/// Concrete [ApiClient] implementations should translate transport-specific
/// failures (socket errors, timeouts, non-2xx responses) into this type so the
/// rest of the app never depends on a particular HTTP library.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.cause, this.detail});

  final String message;

  /// The server's own explanation, verbatim (FastAPI's `detail`), without the
  /// "POST /api/leads failed: " framing [message] carries for logs.
  ///
  /// Some backend errors are written FOR the person holding the phone — the
  /// duplicate-lead 409 names the existing lead and the telecaller who owns
  /// it — and showing those through [message] buried that sentence inside a
  /// stack-trace-shaped string. Null when the failure produced no server
  /// message (a socket error, a timeout).
  final String? detail;

  /// HTTP status code when the failure came from a response, else null.
  final int? statusCode;

  /// The underlying error (e.g. SocketException), when available.
  final Object? cause;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isServerError => (statusCode ?? 0) >= 500;

  /// True when the request never got a response in time (as opposed to a
  /// socket/DNS failure) — lets callers show "the server is slow" instead of
  /// a generic "can't connect" message.
  bool get isTimeout => cause is TimeoutException;

  @override
  String toString() =>
      'ApiException(${statusCode ?? 'network'}): $message';
}
