/// Central backend configuration.
///
/// MVP note: the app currently runs on static mock data (see `state/providers.dart`),
/// so nothing here is hit at runtime yet. When the backend is ready:
///   1. Flip [ApiConfig.useMockData] to `false`.
///   2. Point [ApiEnvironment] entries at the real hosts.
///   3. Provide a concrete [ApiClient] implementation (see `api_client.dart`).
library;

import 'package:flutter/foundation.dart' show kReleaseMode;

/// A named backend target (dev / staging / prod).
class ApiEnvironment {
  const ApiEnvironment({required this.name, required this.baseUrl});

  /// Whether `--dart-define=API_BASE_URL=...` was passed. `bool.hasEnvironment`
  /// is const-evaluable where `String.isNotEmpty` is not, so this is what lets
  /// the dev URL stay a compile-time constant while remaining overridable.
  static const bool _hasBaseUrlOverride = bool.hasEnvironment('API_BASE_URL');

  final String name;
  final String baseUrl;

  // `dev` points at the local FastAPI backend (leadpilot-backend), which serves
  // /api/inbox, /api/leads, /api/memory, /api/calls/* on port 8000.
  //
  // Pass the address per-machine instead of editing this file:
  //     flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
  // The default below is a LAN address and is therefore DHCP-dependent — check
  // yours with `ipconfig getifaddr en0` and use the override when it differs.
  //
  //   * Physical device over Wi-Fi: use the Mac's LAN IP. Verified working on
  //     2026-08-31 (phone 192.168.31.54 -> Mac 192.168.31.154: ping 0% loss,
  //     and a raw `nc` GET /health from the device returned 200). Requires the
  //     backend bound to all interfaces, not just loopback:
  //       uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
  //   * `adb reverse tcp:8000 tcp:8000` + 127.0.0.1 was the previous setting,
  //     from a period when the "Nilay" Wi-Fi had AP/client isolation. Do NOT
  //     rely on it while adb is connected over Wi-Fi (`adb connect`): the
  //     reverse registers and shows in `adb reverse --list`, but does not
  //     actually forward — measured on 2026-08-31, loopback GETs from the
  //     device returned nothing while the LAN IP returned 200. Over a USB
  //     cable it does work, and must be re-run after every reconnect.
  //   * Android emulator instead: use http://10.0.2.2:8000 (host loopback).
  static const dev = ApiEnvironment(
    name: 'dev',
    baseUrl: _hasBaseUrlOverride
        ? String.fromEnvironment('API_BASE_URL')
        : 'http://192.168.31.154:8000',
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

  /// The active backend target. Release builds (what Play Store ships) always
  /// point at the deployed Render backend; debug/profile builds default to
  /// the local dev server (see [ApiEnvironment.dev] for setup notes).
  static const ApiEnvironment environment = kReleaseMode
      ? ApiEnvironment.prod
      : ApiEnvironment.dev;

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
