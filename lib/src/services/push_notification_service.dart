import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/api/api_endpoints.dart';
import '../core/api/http_api_client.dart';
import 'notification_service.dart';

/// Top-level (not a class member) because FirebaseMessaging.onBackgroundMessage
/// requires a top-level or static function — it can run in a separate isolate
/// with no access to app state. Left as a no-op: the payload's "notification"
/// block is already shown by the OS automatically while backgrounded/terminated
/// (that's what firebase_admin's `messaging.Notification` on the backend
/// produces); this hook only exists for extra background *logic*, which
/// nothing here needs yet.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Server-initiated push notifications, via Firebase Cloud Messaging —
/// distinct from [NotificationService], which only ever fires a reminder the
/// telecaller scheduled for themselves. This is the other direction: a new
/// lead assigned to them, a founder moving a lead they own, a password
/// reset — things that happen on the backend and the telecaller would
/// otherwise only learn about by opening the app.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  // NOT initialized eagerly as a field — merely touching FirebaseMessaging.
  // instance before Firebase.initializeApp() has run (e.g. a plain
  // `flutter test` with no Firebase test setup, see session_store_test.dart)
  // throws, and this class is reached indirectly from SessionController on
  // every app start, restored session or not. init() is the only place that
  // may construct it; every other method goes through this getter so a
  // never-initialized/failed-to-initialize Firebase degrades to "no push
  // this session" instead of crashing login/session restore.
  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _refreshSub;
  String? _jwt;
  bool _ready = false;

  Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // A push that arrives while the app is open in the foreground doesn't
      // get shown by the OS automatically (unlike background/terminated) —
      // the app has to render it itself.
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        NotificationService.instance.showNow(
          notifId:
              message.messageId?.hashCode.abs() ??
              DateTime.now().millisecondsSinceEpoch.hashCode.abs(),
          title: notification.title ?? 'Asan Telecaller',
          body: notification.body ?? '',
        );
      });

      // The token can rotate at any time (app reinstall, token expiry,
      // etc.) — re-register whenever it does, but only while logged in.
      _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((newToken) {
        final jwt = _jwt;
        if (jwt != null) unawaited(_register(jwt, newToken));
      });

      _messaging = messaging;
      _ready = true;
    } catch (_) {
      // No push this session (missing/misconfigured Firebase, no Play
      // Services on this device, etc.) — the rest of the app is unaffected.
    }
  }

  /// Call after a successful login and on app start for an already-restored
  /// session (see SessionController.setSession/_restore) — gets the current
  /// device token and registers it against this JWT. Fail-soft throughout:
  /// Firebase never having initialized, no FCM token available (permission
  /// denied, emulator without Play services, etc.), or the backend call
  /// failing must never block login or session restore.
  Future<void> registerTokenIfNeeded(String jwt) async {
    _jwt = jwt;
    final messaging = _messaging;
    if (!_ready || messaging == null) return;
    try {
      final token = await messaging.getToken();
      if (token != null) await _register(jwt, token);
    } catch (_) {
      // No push this session — the rest of the app works the same either way.
    }
  }

  Future<void> _register(String jwt, String token) async {
    try {
      final client = HttpApiClient(getToken: () => jwt);
      await client.post(ApiEndpoints.fcmToken, body: {'token': token});
    } catch (_) {
      // Fail soft — see class doc.
    }
  }
}
