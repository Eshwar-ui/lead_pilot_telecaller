import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:permission_handler/permission_handler.dart';

import 'call_actions.dart' as call_actions;
import 'call_recording_service.dart';

/// Everything this app asks the phone for, in one list, each with the reason
/// it is asked for.
///
/// These used to be scattered: two requested silently at startup, the rest
/// sprung on the telecaller mid-task — a storage prompt in the middle of
/// hanging up, an overlay prompt while dialling. Nothing ever said what any
/// of them were for, so a declined permission looked to the telecaller like
/// the app being broken later, with no way back to the question.
///
/// Ordered by how much the app breaks without each one, since that is also
/// the order "Allow all" walks them in.
enum AppPermission {
  notifications(
    title: 'Notifications',
    why:
        'Follow-up reminders and updates from your founder can reach you. '
        'Without this you get no reminder before a scheduled call.',
    icon: Icons.notifications_active_outlined,
  ),
  audioFiles(
    title: 'Music and audio',
    why:
        'The app can read the recording your phone saves after each call — '
        'this is what produces your transcript, score and lead notes.',
    icon: Icons.audio_file_outlined,
  ),
  recordingsFolder(
    title: 'Call recordings folder',
    why:
        'Some phones hide the dialer\'s recordings folder from other apps. '
        'Pointing the app at it once fixes that for good.',
    icon: Icons.folder_open_outlined,
  ),
  phone(
    title: 'Phone and call history',
    why:
        'The app can tell when your call ends and bring you straight back to '
        'log it, and can match calls you make outside the app to the right '
        'lead.',
    icon: Icons.phone_in_talk_outlined,
  ),
  overlay(
    title: 'Display over other apps',
    why:
        'Your lead\'s notes and talking points float on screen while you are '
        'on the call, over the dialer.',
    icon: Icons.picture_in_picture_alt_outlined,
  ),
  batteryExemption(
    title: 'Run in the background',
    why:
        'Android stops shutting the app down mid-call to save battery, which '
        'is the usual reason a recording goes missing.',
    icon: Icons.battery_saver_outlined,
  ),
  contacts(
    title: 'Contacts',
    why:
        'A lead you save shows by name in your dialer when they ring you '
        'back, instead of an unknown number.',
    icon: Icons.contacts_outlined,
  );

  const AppPermission({
    required this.title,
    required this.why,
    required this.icon,
  });

  /// Shown as the row heading — the telecaller's words for it, matching what
  /// the system prompt will say, not the manifest constant.
  final String title;

  /// What the telecaller gets by allowing it, and what breaks if they don't.
  final String why;

  final IconData icon;
}

/// Reads and requests the [AppPermission] list.
///
/// Everything here is fail-soft: a permission API throwing (an OEM with no
/// battery-optimization screen, a plugin missing on this platform) must leave
/// the app usable, so failures read as "not granted" rather than propagating.
class AppPermissions {
  const AppPermissions({CallRecordingService? recordings})
    : _recordings = recordings ?? const CallRecordingService();

  final CallRecordingService _recordings;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isGranted(AppPermission permission) async {
    if (!isSupported) return true;
    try {
      return switch (permission) {
        AppPermission.notifications =>
          await Permission.notification.status.isGranted,
        AppPermission.audioFiles => await _audioGranted(),
        AppPermission.recordingsFolder =>
          await _recordings.hasRecordingsFolderAccess(),
        AppPermission.phone => await Permission.phone.status.isGranted,
        AppPermission.overlay =>
          await Permission.systemAlertWindow.status.isGranted,
        AppPermission.batteryExemption =>
          await Permission.ignoreBatteryOptimizations.status.isGranted,
        AppPermission.contacts => await Permission.contacts.status.isGranted,
      };
    } catch (_) {
      return false;
    }
  }

  /// Runs the grant flow for one permission and reports whether it ended up
  /// granted. Several of these leave the app — a settings page, a folder
  /// picker — so the caller should re-read status afterwards rather than
  /// assuming the returned value is final.
  Future<bool> request(AppPermission permission) async {
    if (!isSupported) return true;
    try {
      switch (permission) {
        case AppPermission.notifications:
          await Permission.notification.request();
        case AppPermission.audioFiles:
          await _recordings.ensureStoragePermission();
        case AppPermission.recordingsFolder:
          await call_actions.pickRecordingsFolder();
        case AppPermission.phone:
          await Permission.phone.request();
        case AppPermission.overlay:
          await Permission.systemAlertWindow.request();
        case AppPermission.batteryExemption:
          // The native path, not permission_handler's: it also opens the MIUI
          // autostart screen, which is a separate Xiaomi-only setting that
          // kills the capture service just as reliably.
          await call_actions.requestBackgroundPermissions();
        case AppPermission.contacts:
          await Permission.contacts.request();
      }
    } catch (_) {
      // Fall through to the status read below — an OEM without the screen
      // this opens is a "still not granted", not a crash.
    }
    return isGranted(permission);
  }

  /// Whether Android will no longer show a prompt for this one, so the only
  /// way to grant it is the app settings page.
  ///
  /// Only the ordinary runtime permissions can reach this state. The others
  /// are settings-page grants already — there is no in-app prompt for them to
  /// stop showing.
  Future<bool> isPermanentlyDenied(AppPermission permission) async {
    if (!isSupported) return false;
    try {
      return switch (permission) {
        AppPermission.notifications =>
          await Permission.notification.status.isPermanentlyDenied,
        AppPermission.phone => await Permission.phone.status.isPermanentlyDenied,
        AppPermission.contacts =>
          await Permission.contacts.status.isPermanentlyDenied,
        AppPermission.audioFiles => await _audioPermanentlyDenied(),
        _ => false,
      };
    } catch (_) {
      return false;
    }
  }

  Future<bool> _audioPermanentlyDenied() async {
    final sdkInt = await _recordings.androidSdkInt();
    final status = sdkInt >= 33
        ? await Permission.audio.status
        : await Permission.storage.status;
    return status.isPermanentlyDenied;
  }

  /// Everything not yet granted, in [AppPermission] order.
  Future<List<AppPermission>> missing() async {
    if (!isSupported) return const [];
    final result = <AppPermission>[];
    for (final permission in AppPermission.values) {
      if (!await isGranted(permission)) result.add(permission);
    }
    return result;
  }

  /// Opens the OS app-settings page, for a permission the telecaller has
  /// permanently denied — the in-app prompt no longer appears for those.
  Future<void> openSettings() => openAppSettings();

  Future<bool> _audioGranted() async {
    final sdkInt = await _recordings.androidSdkInt();
    final useMediaAudio = sdkInt >= 33;
    final outcome = CallRecordingService.decideAccess(
      sdkInt: sdkInt,
      mediaAudio: useMediaAudio
          ? await Permission.audio.status
          : PermissionStatus.denied,
      legacyStorage: useMediaAudio
          ? PermissionStatus.denied
          : await Permission.storage.status,
    );
    return outcome.result == StoragePermissionResult.granted;
  }
}
