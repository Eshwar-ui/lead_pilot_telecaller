import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/services/notification_service.dart';
import 'src/services/push_notification_service.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter's default ceiling is 100 MB / 1000 decoded images, sized for a
  // flagship. This app draws a handful of small images — a brand mark, an org
  // logo — so that headroom buys nothing and, on the 4 GB phones telecallers
  // are issued, lets the process grow into the footprint that gets it killed
  // when they switch to WhatsApp mid-call.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 30 << 20
    ..maximumSize = 100;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await NotificationService.instance.init();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushNotificationService.instance.init();
  runApp(const ProviderScope(child: LeadPilotApp()));
}
