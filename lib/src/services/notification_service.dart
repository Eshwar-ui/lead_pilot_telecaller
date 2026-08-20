import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Wraps flutter_local_notifications for scheduling follow-up call reminders.
///
/// Call [NotificationService.instance.init()] once from main() before the app
/// runs. On Android 12+ the system will ask the user for exact-alarm permission
/// on first schedule — handled automatically by the plugin.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Derives the local-notification id for a follow-up task id. Shared by the
  /// scheduling call site and every cancellation call site so they can never
  /// drift apart and leave a stale alarm uncancellable.
  static int notifIdFor(String taskId) => taskId.hashCode.abs() % 100000;

  Future<void> init() async {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Request notification permission (Android 13+ / iOS).
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  /// Schedules a single follow-up reminder at [scheduledAt].
  /// [notifId] must be unique per task (use `id.hashCode.abs() % 100000`).
  Future<void> scheduleFollowUp({
    required int notifId,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    if (!_ready || scheduledAt.isBefore(DateTime.now())) return;

    final zonedTime = tz.TZDateTime.from(scheduledAt, tz.local);
    await _plugin.zonedSchedule(
      notifId,
      title,
      body,
      zonedTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'follow_up_channel',
          'Follow-up Calls',
          channelDescription: 'Reminders to call back leads',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancels a previously scheduled notification.
  Future<void> cancel(int notifId) async {
    if (!_ready) return;
    await _plugin.cancel(notifId);
  }

  /// Shows a notification immediately — used by [PushNotificationService] for
  /// a push (FCM) message that arrives while the app is in the foreground.
  /// FCM only auto-displays a "notification" payload via the OS tray while
  /// backgrounded/terminated; a foregrounded app has to render it itself,
  /// same as any other in-app toast/banner would. Reuses this plugin
  /// instance rather than a second one so both notification types share one
  /// initialization and one Android notification-permission prompt.
  Future<void> showNow({
    required int notifId,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      notifId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'push_channel',
          'Updates',
          channelDescription: 'Updates from your founder — lead assignments, stage changes, account changes',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
