import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'store.dart';

/// Local notifications: timer end, task reminders, prayer reminders.
/// Reminders are scheduled for the next 7 days and re-scheduled every time
/// data changes or the app opens.
class Notif {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool ok = false;
  static DateTime? _timerAt;
  static String _timerTitle = '', _timerBody = '';

  static const _nd = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Task, prayer and timer reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    try {
      await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ));
      ok = true;
    } catch (_) {
      ok = false;
    }
  }

  static Future<void> askPermission() async {
    if (!ok) return;
    try {
      await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
  }

  static Future<void> _at(int id, String title, String body, DateTime when) async {
    if (!ok || when.isBefore(DateTime.now().add(const Duration(seconds: 2)))) return;
    final d = tz.TZDateTime.from(when, tz.UTC); // absolute instant, so timezone is not an issue
    Future<void> go(AndroidScheduleMode m) => _p.zonedSchedule(
          id, title, body, d, _nd,
          androidScheduleMode: m,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      // exact alarms not permitted -> fall back to inexact
      try { await go(AndroidScheduleMode.inexactAllowWhileIdle); } catch (_) {}
    }
  }

  static Future<void> setTimer(String title, String body, DateTime at) async {
    _timerAt = at;
    _timerTitle = title;
    _timerBody = body;
    await _at(1, title, body, at);
  }

  static Future<void> clearTimer() async {
    _timerAt = null;
    if (!ok) return;
    try { await _p.cancel(1); } catch (_) {}
  }

  static Future<void> test() => _at(2, 'Daily Tracker', 'Notifications are working ✅', DateTime.now().add(const Duration(seconds: 5)));

  static DateTime? _hm(DateTime day, String? rt) {
    if (rt == null) return null;
    final x = rt.split(':');
    if (x.length != 2) return null;
    final h = int.tryParse(x[0]), m = int.tryParse(x[1]);
    if (h == null || m == null) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  static Future<void> rescheduleAll(Store s) async {
    if (!ok) return;
    try {
      await _p.cancelAll();
      if (_timerAt != null) await _at(1, _timerTitle, _timerBody, _timerAt!);
      var id = 100;
      final now = DateTime.now();
      for (var i = 0; i < s.profiles.length; i++) {
        final m = s.dataOf(i);
        final name = s.profiles[i]['n'];
        final isPrayer = s.profiles[i]['t'] == 'prayer';
        for (var o = 0; o < 7; o++) {
          final day = DateTime(now.year, now.month, now.day + o), k = dk(day);
          if (isPrayer) {
            final done = ((m['pdone'] as Map?)?[k] as List?) ?? [];
            for (final p in (m['prayers'] as List? ?? [])) {
              final when = _hm(day, p['rt'] as String?);
              if (when == null || done.contains(p['n']) || id > 450) continue;
              await _at(id++, '🕌 ${p['n']}', name.toString(), when);
            }
          } else {
            for (final e in (m['tasks'] as List? ?? [])) {
              final when = _hm(day, e['rt'] as String?);
              if (when == null || !occurs(e, k) || isDone(e, k) || id > 450) continue;
              await _at(id++, '⏰ ${e['t']}', '$name  •  ${e['s']}', when);
            }
          }
        }
      }
      // Exam reminders: group milestones and individual subject exam dates.
      var examId = 500;
      Future<void> scheduleExamDate(String? raw, String title, String label) async {
        if (raw == null || raw.isEmpty || examId > 650) return;
        final date = DateTime.tryParse(raw);
        if (date == null) return;
        for (final offset in [7, 1, 0]) {
          if (examId > 650) break;
          final day = DateTime(date.year, date.month, date.day - offset, 8);
          if (day.isBefore(now)) continue;
          final body = offset == 7 ? '$label "$title" is in 7 days. Keep preparing!' : offset == 1 ? '$label "$title" is tomorrow. Review your syllabus.' : '$label "$title" is today. Good luck!';
          await _at(examId++, '📚 Exam reminder', body, day);
        }
      }
      for (var i = 0; i < s.profiles.length; i++) {
        if (s.profiles[i]['t'] == 'prayer') continue;
        final data = s.dataOf(i);
        for (final exam in (data['exams'] as List? ?? [])) {
          if (exam['done'] == true) continue;
          final title = (exam['title'] ?? 'Upcoming exam').toString();
          await scheduleExamDate((exam['startDate'] ?? '').toString(), title, 'Exam group starts:');
          await scheduleExamDate((exam['endDate'] ?? exam['date'] ?? '').toString(), title, 'Exam group ends:');
          for (final subject in (exam['subjects'] as List? ?? [])) {
            await scheduleExamDate((subject['date'] ?? exam['endDate'] ?? exam['date'] ?? '').toString(), (subject['name'] ?? 'Subject').toString(), '$title •');
          }
        }
      }
    } catch (_) {}
  }
}
