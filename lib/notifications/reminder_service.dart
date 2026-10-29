// Нагадування (пакет flutter_local_notifications версії 20 і новіші, виклики з іменованими параметрами): планувальник сповіщень Android і контролер, який стежить за
// календарем та оновлює заплановані сповіщення.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_state.dart';
import '../diagnostics.dart';
import 'reminder_plan.dart';

/// Те, що вміє платформа: показати й запланувати сповіщення.
abstract class ReminderScheduler {
  /// Запитати дозвіл на сповіщення (Android 13+). true — дозвіл є.
  Future<bool> requestPermission();

  /// Прибрати всі раніше заплановані нагадування й поставити нові.
  Future<void> replaceAll(List<PlannedReminder> items);

  /// Показати сповіщення просто зараз (кнопка «Пробне сповіщення»).
  Future<void> showNow(String title, String body);
}

/// Справжній планувальник на пакеті flutter_local_notifications.
class LocalReminderScheduler implements ReminderScheduler {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'shift_reminders',
      'Нагадування про зміни',
      channelDescription: 'Нагадування почати й закінчити зміну',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureReady();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return (await android?.requestNotificationsPermission()) ?? false;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> items) async {
    await _ensureReady();
    await _plugin.cancelAll();
    for (final item in items) {
      // Час задаємо як момент у UTC: так не потрібна база часових поясів,
      // а перехід на літній/зимовий час враховує сам Dart.
      final utc = item.when.toUtc();
      final moment = tz.TZDateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
      await _plugin.zonedSchedule(
        id: item.id,
        title: item.title,
        body: item.body,
        scheduledDate: moment,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> showNow(String title, String body) async {
    await _ensureReady();
    await _plugin.show(id: 999999, title: title, body: body, notificationDetails: _details);
  }
}

/// Стежить за календарем і налаштуваннями та тримає сповіщення в актуальному стані.
class ReminderController extends ChangeNotifier {
  ReminderController({
    required this.state,
    required this.scheduler,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 2),
  }) : _clock = clock ?? DateTime.now;

  final AppState state;
  final ReminderScheduler scheduler;
  final DateTime Function() _clock;
  final Duration debounce;

  Timer? _timer;
  String? _lastSignature;
  int _scheduled = 0;
  bool? _permission;

  /// Скільки нагадувань зараз заплановано.
  int get scheduledCount => _scheduled;

  /// Результат останнього запиту дозволу (null — ще не питали).
  bool? get permissionGranted => _permission;

  /// Почати стежити за змінами та одразу все розставити.
  void start() {
    state.addListener(_onChange);
    unawaited(sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    state.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(sync()));
  }

  /// Перерахувати нагадування й передати їх планувальнику.
  Future<void> sync() async {
    try {
      final plan = planReminders(
        shifts: state.shifts,
        now: _clock(),
        start: state.remindStart,
        startMinutes: state.remindStartMinutes,
        end: state.remindEnd,
        endMinutes: state.remindEndMinutes,
      );
      final signature = plan.join(';');
      // Нічого не змінилось з минулого разу: платформу не чіпаємо.
      if (signature == _lastSignature) return;
      await scheduler.replaceAll(plan);
      _lastSignature = signature;
      _scheduled = plan.length;
      notifyListeners();
    } catch (e) {
      AppLog.add('нагадування: не вдалося оновити: $e');
    }
  }

  Future<bool> requestPermission() async {
    try {
      _permission = await scheduler.requestPermission();
    } catch (e) {
      AppLog.add('нагадування: запит дозволу не вдався: $e');
      _permission = false;
    }
    notifyListeners();
    return _permission ?? false;
  }

  Future<void> sendTest() {
    return scheduler.showNow(
      'Пробне сповіщення',
      'Якщо ти це бачиш, нагадування працюватимуть.',
    );
  }
}
