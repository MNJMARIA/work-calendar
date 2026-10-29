// Тести нагадувань: план за календарем, оновлення планувальника, екран «Сповіщення».
// Запуск: flutter test test/reminder_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/notifications/notification_settings_page.dart';
import 'package:work_calendar/notifications/reminder_plan.dart';
import 'package:work_calendar/notifications/reminder_service.dart';
import 'package:work_calendar/services.dart';

class FakeScheduler implements ReminderScheduler {
  final List<List<PlannedReminder>> calls = [];
  final List<String> shown = [];
  bool permission = true;
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> items) async => calls.add(items);

  @override
  Future<void> showNow(String title, String body) async => shown.add(title);
}

Future<AppState> makeState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await SharedPreferences.getInstance());
}

void main() {
  // Неділя, 25 жовтня 2026, 10:00.
  final now = DateTime(2026, 10, 25, 10, 0);
  final shifts = <String, int>{
    '2026-10-24': 720, // учора: пропускаємо
    '2026-10-25': 720, // сьогодні
    '2026-10-27': 600,
    '2026-11-30': 720, // далі за 30 днів
  };

  group('План', () {
    test('нічого не ввімкнено — порожній план', () {
      expect(
        planReminders(shifts: shifts, now: now, start: false, startMinutes: 450, end: false, endMinutes: 1200),
        isEmpty,
      );
    });

    test('початок зміни: лише дні з виходом, лише майбутній час', () {
      final plan = planReminders(shifts: shifts, now: now, start: true, startMinutes: 7 * 60 + 30, end: false, endMinutes: 0);
      // Сьогодні 07:30 уже минуло, лишається лише 27 жовтня.
      expect(plan.length, 1);
      expect(plan.single.when, DateTime(2026, 10, 27, 7, 30));
      expect(plan.single.title, 'Сьогодні вихід на роботу');
      expect(plan.single.body, contains('10 год'));
    });

    test('кінець зміни сьогодні ще попереду', () {
      final plan = planReminders(shifts: shifts, now: now, start: false, startMinutes: 0, end: true, endMinutes: 20 * 60);
      expect(plan.map((e) => e.when).toList(), [DateTime(2026, 10, 25, 20, 0), DateTime(2026, 10, 27, 20, 0)]);
    });

    test('обидва нагадування мають різні номери, номери стабільні', () {
      final a = planReminders(shifts: shifts, now: DateTime(2026, 10, 25, 5), start: true, startMinutes: 450, end: true, endMinutes: 1200);
      final b = planReminders(shifts: shifts, now: DateTime(2026, 10, 25, 5), start: true, startMinutes: 450, end: true, endMinutes: 1200);
      expect(a.length, 4);
      expect(a.map((e) => e.id).toSet().length, 4);
      expect(a.map((e) => e.id).toList(), b.map((e) => e.id).toList());
      expect(reminderId(DateTime(2026, 10, 25), 0) + 1, reminderId(DateTime(2026, 10, 25), 1));
    });

    test('горизонт 30 днів: 30 листопада вже за межами', () {
      final plan = planReminders(shifts: shifts, now: DateTime(2026, 10, 25, 5), start: true, startMinutes: 450, end: false, endMinutes: 0);
      expect(plan.any((e) => e.when.month == 11), isFalse);
    });

    test('час у вигляді годинника', () {
      expect(fmtClockMinutes(450), '07:30');
      expect(fmtClockMinutes(0), '00:00');
      expect(fmtClockMinutes(20 * 60 + 5), '20:05');
    });
  });

  group('Налаштування в стані', () {
    test('зберігаються й читаються після перезапуску', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = AppState(prefs);
      expect(a.remindStart, isFalse);
      expect(a.pushUpdates, isTrue);
      a.setRemindStart(true);
      a.setRemindStartMinutes(8 * 60);
      a.setRemindEnd(true);
      a.setRemindEndMinutes(19 * 60 + 30);
      a.setPushUpdates(false);

      final b = AppState(prefs);
      expect(b.remindStart, isTrue);
      expect(b.remindStartMinutes, 480);
      expect(b.remindEnd, isTrue);
      expect(b.remindEndMinutes, 19 * 60 + 30);
      expect(b.pushUpdates, isFalse);
    });

    test('час поза межами доби обрізається', () async {
      final state = await makeState();
      state.setRemindStartMinutes(5000);
      expect(state.remindStartMinutes, 1439);
      state.setRemindStartMinutes(-5);
      expect(state.remindStartMinutes, 0);
    });
  });

  group('Контролер', () {
    test('ставить нагадування за календарем і не чіпає платформу без змін', () async {
      final state = await makeState();
      state.setShifts([DateTime(2026, 10, 27), DateTime(2026, 10, 28)], 600);
      state.setRemindStart(true);
      final scheduler = FakeScheduler();
      final c = ReminderController(state: state, scheduler: scheduler, clock: () => now);

      await c.sync();
      expect(scheduler.calls.length, 1);
      expect(scheduler.calls.single.length, 2);
      expect(c.scheduledCount, 2);

      await c.sync(); // нічого не змінилось
      expect(scheduler.calls.length, 1);

      state.setShifts([DateTime(2026, 10, 29)], 600);
      await c.sync();
      expect(scheduler.calls.length, 2);
      expect(scheduler.calls.last.length, 3);
    });

    test('вимкнули нагадування — планувальник отримує порожній список', () async {
      final state = await makeState();
      state.setShifts([DateTime(2026, 10, 27)], 600);
      state.setRemindStart(true);
      final scheduler = FakeScheduler();
      final c = ReminderController(state: state, scheduler: scheduler, clock: () => now);
      await c.sync();
      state.setRemindStart(false);
      await c.sync();
      expect(scheduler.calls.last, isEmpty);
      expect(c.scheduledCount, 0);
    });

    test('збій планувальника не падає', () async {
      final state = await makeState();
      state.setShifts([DateTime(2026, 10, 27)], 600);
      state.setRemindStart(true);
      final c = ReminderController(state: state, scheduler: _Broken(), clock: () => now);
      await c.sync();
      expect(c.scheduledCount, 0);
    });

    test('запит дозволу й пробне сповіщення', () async {
      final state = await makeState();
      final scheduler = FakeScheduler()..permission = false;
      final c = ReminderController(state: state, scheduler: scheduler);
      expect(await c.requestPermission(), isFalse);
      expect(c.permissionGranted, isFalse);
      await c.sendTest();
      expect(scheduler.shown, ['Пробне сповіщення']);
    });
  });

  group('Екран «Сповіщення»', () {
    testWidgets('перемикачі змінюють налаштування й просять дозвіл', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = await makeState();
      final scheduler = FakeScheduler();
      final reminders = ReminderController(state: state, scheduler: scheduler, clock: () => now);
      var pushOn = true;
      final services = AppServices(
        reminders: reminders,
        setUpdatePush: (v) async => pushOn = v,
      );

      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(home: NotificationSettingsPage(state: state)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('07:30'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remind-start')));
      await tester.pumpAndSettle();
      expect(state.remindStart, isTrue);
      expect(scheduler.permissionRequests, 1);

      await tester.tap(find.byKey(const Key('remind-end')));
      await tester.pumpAndSettle();
      expect(state.remindEnd, isTrue);

      await tester.ensureVisible(find.byKey(const Key('push-updates')));
      await tester.tap(find.byKey(const Key('push-updates')));
      await tester.pumpAndSettle();
      expect(state.pushUpdates, isFalse);
      expect(pushOn, isFalse);

      await tester.ensureVisible(find.byKey(const Key('notif-test')));
      await tester.tap(find.byKey(const Key('notif-test')));
      await tester.pumpAndSettle();
      expect(scheduler.shown, ['Пробне сповіщення']);
    });

    testWidgets('якщо дозвіл не дали, показується підказка і пробне не надсилається', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = await makeState();
      final scheduler = FakeScheduler()..permission = false;
      final services = AppServices(
        reminders: ReminderController(state: state, scheduler: scheduler),
      );
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(home: NotificationSettingsPage(state: state)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('notif-test')));
      await tester.tap(find.byKey(const Key('notif-test')));
      await tester.pumpAndSettle();
      expect(scheduler.shown, isEmpty);
      expect(find.textContaining('Сповіщення вимкнені'), findsOneWidget);
    });
  });
}

class _Broken implements ReminderScheduler {
  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(List<PlannedReminder> items) async => throw StateError('збій');

  @override
  Future<void> showNow(String title, String body) async {}
}
