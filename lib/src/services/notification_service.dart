import 'package:flutter/material.dart' show Color;
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

  /// Asan amber, tinting the white status-bar silhouette. Kept in sync with
  /// `@color/notification_accent`, which does the same for FCM's own
  /// default notifications.
  static const _accent = Color(0xFFFAAC0C);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Derives the local-notification id for one reminder of a follow-up task.
  /// Shared by the scheduling call site and every cancellation call site so
  /// they can never drift apart and leave a stale alarm uncancellable.
  ///
  /// The base id stays inside 0..99999 and each reminder adds its own disjoint
  /// offset on top, so the three alarms for one task can never collide with
  /// each other or with another task's. [FollowUpReminder.dueNow] deliberately
  /// has offset 0: it keeps the exact id this method returned when a follow-up
  /// had only one reminder, so alarms scheduled by an older build of the app
  /// are still cancellable by this one.
  static int notifIdFor(
    String taskId, [
    FollowUpReminder reminder = FollowUpReminder.dueNow,
  ]) => (taskId.hashCode.abs() % 100000) + reminder.idOffset;

  Future<void> init() async {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings(
      '@drawable/ic_stat_notification',
    );
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
          icon: '@drawable/ic_stat_notification',
          color: _accent,
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

  /// Schedules the full set of reminders for one follow-up: an hour ahead, five
  /// minutes ahead, and at the appointed time. Any of the three already in the
  /// past is skipped rather than fired immediately — a follow-up booked for 20
  /// minutes from now gets the 5-minute and on-time reminders only.
  Future<void> scheduleFollowUpReminders({
    required String taskId,
    required String leadName,
    required String taskText,
    required DateTime scheduledAt,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    for (final reminder in FollowUpReminder.values) {
      final fireAt = reminder.fireTimeFor(scheduledAt);
      if (!fireAt.isAfter(at)) continue;
      await scheduleFollowUp(
        notifId: notifIdFor(taskId, reminder),
        title: 'Follow-up: $leadName',
        body: reminder.bodyFor(taskText),
        scheduledAt: fireAt,
      );
    }
  }

  /// Re-arms reminders for follow-ups this device has no alarms for — ones
  /// created on another device or in the founder's web portal and pulled in by
  /// a sync, and ones whose alarms the OS dropped (app reinstall, some OEM
  /// battery managers). Only schedules what is actually missing, read from the
  /// plugin's own pending list, so a routine refresh doesn't re-register every
  /// alarm on every load.
  ///
  /// [horizon] bounds how far ahead to arm: exact alarms are a finite OS
  /// resource, and a reminder months away is better re-armed by a later sync
  /// than held open now.
  Future<void> syncFollowUpReminders(
    List<FollowUpReminderRequest> tasks, {
    DateTime? now,
    Duration horizon = const Duration(days: 30),
  }) async {
    if (!_ready || tasks.isEmpty) return;
    final at = now ?? DateTime.now();
    final cutoff = at.add(horizon);

    final Set<int> alreadyPending;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      alreadyPending = {for (final p in pending) p.id};
    } catch (_) {
      return; // Can't tell what's armed; re-arming blindly would duplicate.
    }

    for (final task in tasks) {
      if (task.scheduledAt.isAfter(cutoff)) continue;
      for (final reminder in FollowUpReminder.values) {
        final fireAt = reminder.fireTimeFor(task.scheduledAt);
        if (!fireAt.isAfter(at)) continue;
        final id = notifIdFor(task.taskId, reminder);
        if (alreadyPending.contains(id)) continue;
        await scheduleFollowUp(
          notifId: id,
          title: 'Follow-up: ${task.leadName}',
          body: reminder.bodyFor(task.taskText),
          scheduledAt: fireAt,
        );
      }
    }
  }

  /// Cancels every reminder belonging to one follow-up. Call this rather than
  /// [cancel] — a task has three alarms, and cancelling only the on-time one
  /// still leaves the two early reminders to fire for work already done.
  Future<void> cancelFollowUp(String taskId) async {
    if (!_ready) return;
    for (final reminder in FollowUpReminder.values) {
      await _plugin.cancel(notifIdFor(taskId, reminder));
    }
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
          icon: '@drawable/ic_stat_notification',
          color: _accent,
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


/// The three reminders fired for one follow-up. Ordered earliest-first.
enum FollowUpReminder {
  hourBefore(Duration(hours: 1), 100000),
  fiveMinutesBefore(Duration(minutes: 5), 200000),
  dueNow(Duration.zero, 0);

  const FollowUpReminder(this.lead, this.idOffset);

  /// How far ahead of the appointment this reminder fires.
  final Duration lead;

  /// Added to a task's base notification id to keep the three apart. See
  /// [NotificationService.notifIdFor] for why [dueNow] is 0.
  final int idOffset;

  DateTime fireTimeFor(DateTime scheduledAt) => scheduledAt.subtract(lead);

  /// The notification body. The lead's name is already the title, so this
  /// leads with how much warning the telecaller has — that is the whole
  /// difference between the three.
  String bodyFor(String taskText) => switch (this) {
    FollowUpReminder.hourBefore => 'In 1 hour · $taskText',
    FollowUpReminder.fiveMinutesBefore => 'In 5 minutes · $taskText',
    FollowUpReminder.dueNow => 'Due now · $taskText',
  };
}

/// One follow-up's worth of input to [NotificationService.syncFollowUpReminders].
class FollowUpReminderRequest {
  const FollowUpReminderRequest({
    required this.taskId,
    required this.leadName,
    required this.taskText,
    required this.scheduledAt,
  });

  final String taskId;
  final String leadName;
  final String taskText;
  final DateTime scheduledAt;
}
