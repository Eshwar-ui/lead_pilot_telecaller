import 'package:url_launcher/url_launcher.dart';

Future<bool> launchPhoneCall(String phoneNumber) async {
  final uri = Uri(scheme: 'tel', path: phoneNumber.replaceAll(' ', ''));
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri);
}

Future<bool> launchSms(String phoneNumber) async {
  final uri = Uri(scheme: 'sms', path: phoneNumber.replaceAll(' ', ''));
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri);
}
