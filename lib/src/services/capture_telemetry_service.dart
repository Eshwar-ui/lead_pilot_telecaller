import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';
import '../core/api/http_api_client.dart';

/// Reports the outcome of one on-device call-recording capture attempt
/// (found / not-found / permission-denied / …) to the backend, tagged with
/// the reporting device's manufacturer/model/OS version.
///
/// Why: [CallRecordingService] scans the phone's own dialer folder for a
/// recording — there is no cloud-telephony fallback today, and the team has
/// no production data on how often that scan fails or on which OEMs. This
/// service is the missing signal, fed from [CallCaptureController] after
/// every capture attempt resolves (see call_capture.dart).
///
/// Deliberately fire-and-forget: a failed report is never surfaced to the
/// telecaller and never blocks/delays the capture → transcribe flow. Callers
/// should invoke [report] with `unawaited(...)`.
class CaptureTelemetryService {
  CaptureTelemetryService({
    String? Function()? getToken,
    ApiClient? client,
    DeviceInfoPlugin? deviceInfo,
  }) : _getToken = getToken,
       _client = client ?? HttpApiClient(getToken: getToken),
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final String? Function()? _getToken;
  final ApiClient _client;
  final DeviceInfoPlugin _deviceInfo;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Sends one capture-attempt report. `outcome` must be one of
  /// `found` / `not_found` / `permission_denied` / `permission_blocked` /
  /// `unsupported` / `error`, matching the backend's `CaptureOutcome` enum
  /// (and [CaptureStatus] in call_capture.dart).
  ///
  /// Never throws. Not logged in → skipped outright (nothing to attribute
  /// the report to). Otherwise makes one attempt, then one retry on
  /// failure, then gives up silently — the backend endpoint is a cheap
  /// single insert, so a genuine outage is the only thing that would fail
  /// twice, and this must never loop or block the caller.
  Future<void> report(String outcome) async {
    if (_getToken?.call() == null) return;

    final device = await _deviceDetails();
    final body = {
      'outcome': outcome,
      if (device.manufacturer != null)
        'device_manufacturer': device.manufacturer,
      if (device.model != null) 'device_model': device.model,
      if (device.osVersion != null) 'os_version': device.osVersion,
    };

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _client.post(ApiEndpoints.captureAttempt, body: body);
        return;
      } catch (_) {
        // Fail-soft — see class doc. Fall through to the single retry, then
        // give up silently on the second failure.
      }
    }
  }

  Future<_DeviceDetails> _deviceDetails() async {
    if (!_isAndroid) return const _DeviceDetails();
    try {
      final info = await _deviceInfo.androidInfo;
      return _DeviceDetails(
        manufacturer: info.manufacturer,
        model: info.model,
        osVersion: 'Android ${info.version.release}',
      );
    } catch (_) {
      // device_info_plus itself failing must not block the report — an
      // outcome with no device breakdown is still useful for the aggregate
      // denominator.
      return const _DeviceDetails();
    }
  }
}

class _DeviceDetails {
  const _DeviceDetails({this.manufacturer, this.model, this.osVersion});

  final String? manufacturer;
  final String? model;
  final String? osVersion;
}
