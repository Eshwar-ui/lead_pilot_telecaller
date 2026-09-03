import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Telecaller consent for picking up calls they did NOT place through the app.
///
/// Default off, and never turned on implicitly. Capturing a call the telecaller
/// started from the app's own Call button is something they visibly asked for;
/// watching the phone's whole call history for lead numbers is a materially
/// bigger ask, so it stays off until they enable it in Profile.
final autoCaptureEnabledProvider =
    NotifierProvider<AutoCaptureSettingsController, bool>(
      AutoCaptureSettingsController.new,
    );

class AutoCaptureSettingsController extends Notifier<bool> {
  static const _key = 'auto_capture_lead_calls_v1';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
