import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _callActionsChannel = MethodChannel('lead_pilot/call_actions');

class CallWithNotesLaunch {
  const CallWithNotesLaunch({
    required this.launched,
    required this.overlayPermissionGranted,
  });

  final bool launched;
  final bool overlayPermissionGranted;

  static const failed = CallWithNotesLaunch(
    launched: false,
    overlayPermissionGranted: true,
  );
}

String _normalizedPhoneNumber(String phoneNumber) =>
    phoneNumber.replaceAll(RegExp(r'\s+'), '');

Future<bool> launchPhoneCall(String phoneNumber) async {
  final uri = Uri(scheme: 'tel', path: _normalizedPhoneNumber(phoneNumber));
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri);
}

Future<bool> showCallAppChooser(String phoneNumber) async {
  final normalizedPhoneNumber = _normalizedPhoneNumber(phoneNumber);

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<bool>(
            'showCallAppChooser',
            {'phoneNumber': normalizedPhoneNumber},
          ) ??
          false;
    } on MissingPluginException {
      return launchPhoneCall(normalizedPhoneNumber);
    } on PlatformException {
      return launchPhoneCall(normalizedPhoneNumber);
    }
  }

  return launchPhoneCall(normalizedPhoneNumber);
}

Future<CallWithNotesLaunch> startCallWithNotesBubble({
  required String leadId,
  required String leadName,
  required String phoneNumber,
  int leadScore = 0,
  String temperature = '',
  String intent = '',
  String scriptOpeningLine = '',
  List<String> memoryFacts = const [],
  String lastCallTs = '',
  int lastCallScore = 0,
  String lastCallSummary = '',
}) async {
  final normalizedPhoneNumber = _normalizedPhoneNumber(phoneNumber);

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final result = await _callActionsChannel
          .invokeMapMethod<String, Object?>('startCallWithNotesBubble', {
            'leadId': leadId,
            'leadName': leadName,
            'phoneNumber': normalizedPhoneNumber,
            'leadScore': leadScore,
            'temperature': temperature,
            'intent': intent,
            'scriptOpeningLine': scriptOpeningLine,
            'memoryFacts': memoryFacts,
            'lastCallTs': lastCallTs,
            'lastCallScore': lastCallScore,
            'lastCallSummary': lastCallSummary,
          });

      return CallWithNotesLaunch(
        launched: result?['launched'] == true,
        overlayPermissionGranted: result?['overlayPermissionGranted'] == true,
      );
    } on MissingPluginException {
      final launched = await launchPhoneCall(normalizedPhoneNumber);
      return CallWithNotesLaunch(
        launched: launched,
        overlayPermissionGranted: true,
      );
    } on PlatformException {
      return CallWithNotesLaunch.failed;
    }
  }

  final launched = await launchPhoneCall(normalizedPhoneNumber);
  return CallWithNotesLaunch(
    launched: launched,
    overlayPermissionGranted: true,
  );
}

Future<String> getNativeCallNotes(String leadId) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<String>('getCallNotes', {
            'leadId': leadId,
          }) ??
          '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  return '';
}

Future<bool> stopCallNotesBubble() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<bool>(
            'stopCallNotesBubble',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  return false;
}

/// Starts the always-on detector for calls placed or received outside the app
/// (see CallDetectionService). Only called once the telecaller has opted in.
Future<bool> startCallDetection() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<bool>(
            'startCallDetection',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  return false;
}

Future<bool> stopCallDetection() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<bool>(
            'stopCallDetection',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  return false;
}

/// Explicitly re-asks for the battery-optimization exemption and (on
/// Xiaomi/Redmi/POCO) the MIUI autostart screen — the automatic in-call ask
/// only ever fires once, ever, with no way back in if the user dismissed it.
/// Reached from the Recording Check screen, where the telecaller has
/// deliberately gone looking for why calls stop getting captured mid-call.
Future<bool> requestBackgroundPermissions() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<bool>(
            'requestBackgroundPermissions',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  return false;
}

/// Recent audio files visible to MediaStore, newest first — the
/// Play-policy-compliant replacement for scanning OEM recording folders
/// directly (which needed `MANAGE_EXTERNAL_STORAGE`). [relativePathHints]
/// are folder-name fragments (e.g. `"MIUI/sound_recorder/"`) to bias results
/// toward known call-recording locations; ignored below Android 10, where
/// MediaStore has no RELATIVE_PATH column. Each result map has
/// `contentUri`/`displayName`/`dateModifiedMs`/`sizeBytes` — see
/// [materializeMediaStoreRecording] to turn one into a readable local file.
Future<List<Map<String, dynamic>>> findRecentAudioRecordings({
  required List<String> relativePathHints,
  int limit = 200,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final result = await _callActionsChannel.invokeListMethod<Object?>(
        'findRecentAudioRecordings',
        {'relativePathHints': relativePathHints, 'limit': limit},
      );
      return (result ?? const [])
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  return const [];
}

/// Copies a MediaStore [contentUri] into the app's own cache directory and
/// returns the local path, or `null` on failure. MediaStore never hands back
/// a raw filesystem path we can rely on, so this is the only way to get a
/// real, readable file for uploading — call it once, only for the specific
/// recording actually being uploaded (not for every candidate in a list).
Future<String?> materializeMediaStoreRecording(String contentUri) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<String>(
        'materializeMediaStoreRecording',
        {'contentUri': contentUri},
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  return null;
}

/// Opens the system folder picker so the telecaller can grant durable access
/// to their call-recordings folder, for OEMs (MIUI in particular) whose
/// dialer writes into a folder MediaStore never indexes (a `.nomedia`
/// marker opts a tree out of the media scanner, but not out of the Storage
/// Access Framework, which this reads instead — see
/// `RecordingsFolderAccess.kt`). Returns the granted tree URI, or `null` if
/// the telecaller cancelled or the grant couldn't be made to persist across
/// app restarts (a non-persisted grant would need re-asking on every launch,
/// so that's treated as a full failure rather than a degraded success).
Future<String?> pickRecordingsFolder() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<String>(
        'pickRecordingsFolder',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  return null;
}

/// Whether a [pickRecordingsFolder] grant is currently held and still valid.
Future<bool> hasRecordingsFolderAccess() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await _callActionsChannel.invokeMethod<bool>(
            'hasRecordingsFolderAccess',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  return false;
}

/// Recordings under the [pickRecordingsFolder]-granted folder, in the same
/// row shape as [findRecentAudioRecordings] (`contentUri`/`displayName`/
/// `dateModifiedMs`/`sizeBytes`) so callers can concatenate both sources and
/// process them identically. Empty if no folder has been granted, or the
/// grant has since been revoked.
Future<List<Map<String, dynamic>>> listRecordingsInGrantedFolder({
  int limit = 200,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final result = await _callActionsChannel.invokeListMethod<Object?>(
        'listRecordingsInGrantedFolder',
        {'limit': limit},
      );
      return (result ?? const [])
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  return const [];
}

Future<bool> launchSms(String phoneNumber) async {
  final uri = Uri(scheme: 'sms', path: _normalizedPhoneNumber(phoneNumber));
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri);
}
