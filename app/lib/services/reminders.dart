import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// "Emma is calling…" — the daily practice reminder styled as an incoming
/// call (full-screen intent + call category). Answering opens the app, which
/// routes straight into a call via [onAnswer].
abstract final class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _timeKey = 'reminder_minutes'; // minutes since midnight
  static const _channel = AndroidNotificationChannel(
    'daily_call',
    'Daily coach call',
    description: 'Your coach calls you for daily practice',
    importance: Importance.max,
  );

  /// Set by main() — navigates to the call screen.
  static void Function()? onAnswer;

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    // India-first default; falls back gracefully elsewhere because the
    // schedule is relative to whatever location is set.
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == 'incoming_call') onAnswer?.call();
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);

    // If the app was launched by tapping the notification, route to a call.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      if (launch?.notificationResponse?.payload == 'incoming_call') {
        // Delay until the first frame so navigation has a context.
        WidgetsBinding.instance.addPostFrameCallback((_) => onAnswer?.call());
      }
    }
  }

  static Future<TimeOfDay?> scheduledTime() async {
    final sp = await SharedPreferences.getInstance();
    final minutes = sp.getInt(_timeKey);
    if (minutes == null) return null;
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  static Future<bool> schedule(TimeOfDay time, String coachName) async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? true;
    if (!granted) return false;

    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_timeKey, time.hour * 60 + time.minute);

    var next = tz.TZDateTime(
      tz.local,
      tz.TZDateTime.now(tz.local).year,
      tz.TZDateTime.now(tz.local).month,
      tz.TZDateTime.now(tz.local).day,
      time.hour,
      time.minute,
    );
    if (next.isBefore(tz.TZDateTime.now(tz.local))) {
      next = next.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: 1,
      title: '$coachName is calling…',
      body: 'Your daily English practice call 📞',
      scheduledDate: next,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          priority: Priority.max,
          importance: Importance.max,
          actions: const [
            AndroidNotificationAction(
              'answer',
              'Answer',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: 'incoming_call',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
    debugPrint('reminders: daily call scheduled for '
        '${time.hour}:${time.minute.toString().padLeft(2, '0')}');
    return true;
  }

  static Future<void> cancel() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_timeKey);
    await _plugin.cancel(id: 1);
  }
}
