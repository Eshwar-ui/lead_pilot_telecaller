/// Central backend configuration.
///
/// MVP note: the app currently runs on static mock data (see `state/providers.dart`),
/// so nothing here is hit at runtime yet. When the backend is ready:
///   1. Flip [ApiConfig.useMockData] to `false`.
///   2. Point [ApiEnvironment] entries at the real hosts.
///   3. Provide a concrete [ApiClient] implementation (see `api_client.dart`).
library;

/// A named backend target (dev / staging / prod).
class ApiEnvironment {
  const ApiEnvironment({required this.name, required this.baseUrl});

  final String name;
  final String baseUrl;

  // TODO(backend): replace placeholder hosts with the real ones.
  //
  // `dev` points at the local NestJS backend in /server (transcription).
  //   * Physical device (the Xiaomi): dev machine LAN IP, phone on same Wi-Fi.
  //     Currently set to this Mac's en0 IP (192.168.31.132). Re-check with
  //     `ipconfig getifaddr en0` if your network changes.
  //   * Android emulator instead: use http://10.0.2.2:3000 (host loopback).
  static const dev = ApiEnvironment(
    name: 'dev',
    baseUrl: 'http://192.168.31.132:3000',
  );
  static const staging = ApiEnvironment(
    name: 'staging',
    baseUrl: 'https://staging.api.leadpilot.example/v1',
  );
  static const prod = ApiEnvironment(
    name: 'prod',
    baseUrl: 'https://api.leadpilot.example/v1',
  );
}

class ApiConfig {
  const ApiConfig._();

  /// While `true`, the app sources data from local mocks. Flip to `false`
  /// once a real [ApiClient] and repositories are wired.
  static const bool useMockData = true;

  /// The active backend target. Swap to [ApiEnvironment.staging] / `.prod`
  /// per build flavor when those exist.
  static const ApiEnvironment environment = ApiEnvironment.dev;

  static String get baseUrl => environment.baseUrl;

  /// Network timeout applied per request by the concrete client.
  static const Duration timeout = Duration(seconds: 20);

  /// Headers attached to every request. Inject auth here once available, e.g.
  /// `'Authorization': 'Bearer $token'`.
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Builds a full URL from a relative endpoint path (e.g. `/leads`).
  static Uri uri(String path, {Map<String, dynamic>? query}) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
  }
}
