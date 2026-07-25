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

  // `dev` points at the local FastAPI "AI layer" backend (voicesummary-main),
  // which serves /api/inbox, /api/leads, /api/memory, /api/calls/* on port 8000.
  //   * Physical device (the Xiaomi) over USB: use 127.0.0.1 + `adb reverse
  //     tcp:8000 tcp:8000` (re-run after every USB reconnect/adb restart).
  //     This is the current setting — the "Nilay" Wi-Fi the phone and this
  //     Mac both connect to has AP/client isolation enabled (confirmed via
  //     `adb shell ping <mac-ip>` -> "Destination Host Unreachable" both
  //     directions), so the phone can't reach the Mac's LAN IP over Wi-Fi at
  //     all — that's the "network error" the telecaller app was hitting.
  //     If AP isolation ever gets disabled on that router, the LAN-IP form
  //     (http://<mac-en0-ip>:8000, check with `ipconfig getifaddr en0`) works
  //     without needing USB/adb reverse.
  //   * Android emulator instead: use http://10.0.2.2:8000 (host loopback).
  //   * Run the backend with:
  //       uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
  static const dev = ApiEnvironment(
    name: 'dev',
    baseUrl: 'http://127.0.0.1:8000',
  );
  static const staging = ApiEnvironment(
    name: 'staging',
    baseUrl: 'https://staging.api.leadpilot.example/v1',
  );
  // Production backend: FastAPI (voicesummary-main) deployed on Render.
  // Routes live at the root under /api/... (no version prefix), matching
  // ApiEndpoints, so the base URL is the bare host with no trailing path.
  static const prod = ApiEnvironment(
    name: 'prod',
    baseUrl: 'https://leadpilot-backend-perc.onrender.com',
  );
}

class ApiConfig {
  const ApiConfig._();

  /// While `true`, the app sources data from local mocks. Now `false`: the
  /// data providers hydrate from the FastAPI backend via [LeadRepository],
  /// falling back to mock data only if the backend is unreachable.
  static const bool useMockData = false;

  /// The active backend target. Pointed at a laptop-hosted FastAPI instance
  /// for local development — swap to [ApiEnvironment.prod] before shipping,
  /// once the deployed backend has this session's new code.
  static const ApiEnvironment environment = ApiEnvironment.dev;

  static String get baseUrl => environment.baseUrl;

  /// Network timeout applied per request by the concrete client.
  static const Duration timeout = Duration(seconds: 20);

  /// Headers attached to every request. `Authorization` is added separately
  /// by [HttpApiClient] (see its `getToken` param / `session_store.dart`) —
  /// not here, since it's per-session state, not a static default.
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
