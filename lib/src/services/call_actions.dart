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
}) async {
  final normalizedPhoneNumber = _normalizedPhoneNumber(phoneNumber);

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final result = await _callActionsChannel.invokeMapMethod<String, Object?>(
        'startCallWithNotesBubble',
        {
          'leadId': leadId,
          'leadName': leadName,
          'phoneNumber': normalizedPhoneNumber,
        },
      );

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

Future<bool> launchSms(String phoneNumber) async {
  final uri = Uri(scheme: 'sms', path: _normalizedPhoneNumber(phoneNumber));
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri);
}
