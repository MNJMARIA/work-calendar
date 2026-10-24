// Тести «часу зміни» днів у AppState: на них тримається синхронізація.
// Запуск: flutter test test/app_state_sync_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/sync/records.dart';

Future<(AppState, SharedPreferences, List<DateTime>)> make([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final time = <DateTime>[DateTime(2026, 10, 24, 10)];
  final state = AppState(prefs, clock: () => time.last);
  return (state, prefs, time);
}

void main() {
  final day = DateTime(2026, 10, 20);

  test('зміна дня отримує час зміни', () async {
    final (state, _, _) = await make();
    state.setShifts([day], 720);
    final rec = state.dayRecords['2026-10-20']!;
    expect(rec.minutes, 720);
    expect(rec.stamp, DateTime(2026, 10, 24, 10).millisecondsSinceEpoch);
  });

  test('видалення лишає «надгробок» із часом', () async {
    final (state, _, time) = await make();
    state.setShifts([day], 720);
    time.add(DateTime(2026, 10, 24, 11));
    state.setShifts([day], null);
    expect(state.shifts.containsKey('2026-10-20'), isFalse);
    final rec = state.dayRecords['2026-10-20']!;
    expect(rec.deleted, isTrue);
    expect(rec.stamp, DateTime(2026, 10, 24, 11).millisecondsSinceEpoch);
  });

  test('скасування — теж нова зміна зі свіжим часом', () async {
    final (state, _, time) = await make();
    final previous = state.setShifts([day], 720);
    time.add(DateTime(2026, 10, 24, 12));
    state.restoreShifts(previous);
    final rec = state.dayRecords['2026-10-20']!;
    expect(rec.deleted, isTrue);
    expect(rec.stamp, DateTime(2026, 10, 24, 12).millisecondsSinceEpoch);
  });

  test('завершення таймера ставить час зміни', () async {
    final (state, _, time) = await make();
    state.startTimer(DateTime(2026, 10, 24, 8));
    time.add(DateTime(2026, 10, 24, 16));
    state.finishTimer(DateTime(2026, 10, 24, 16));
    final rec = state.dayRecords['2026-10-24']!;
    expect(rec.minutes, 480);
    expect(rec.stamp, DateTime(2026, 10, 24, 16).millisecondsSinceEpoch);
  });

  test('чернетка планування не потрапляє в записи для хмари', () async {
    final (state, _, _) = await make();
    state.setPlan([day], 720);
    expect(state.dayRecords, isEmpty);
  });

  test('часи зміни зберігаються між запусками', () async {
    final (state, prefs, _) = await make();
    state.setShifts([day], 720);
    state.setShifts([day], null);
    final again = AppState(prefs);
    expect(again.dayRecords['2026-10-20']!.deleted, isTrue);
  });

  group('mergeRemote', () {
    test('пізніший запис із хмари застосовується', () async {
      final (state, _, _) = await make();
      state.setShifts([day], 480);
      final newer = DateTime(2026, 10, 25).millisecondsSinceEpoch;
      var notified = 0;
      state.addListener(() => notified++);
      final changed = state.mergeRemote({'2026-10-20': DayRecord(minutes: 720, stamp: newer)});
      expect(changed, isTrue);
      expect(state.shifts['2026-10-20'], 720);
      expect(notified, 1);
    });

    test('старіший запис ігнорується', () async {
      final (state, _, _) = await make();
      state.setShifts([day], 480);
      final older = DateTime(2026, 10, 1).millisecondsSinceEpoch;
      var notified = 0;
      state.addListener(() => notified++);
      final changed = state.mergeRemote({'2026-10-20': DayRecord(minutes: 720, stamp: older)});
      expect(changed, isFalse);
      expect(state.shifts['2026-10-20'], 480);
      expect(notified, 0);
    });

    test('видалення з хмари прибирає день', () async {
      final (state, _, _) = await make();
      state.setShifts([day], 480);
      final newer = DateTime(2026, 10, 25).millisecondsSinceEpoch;
      state.mergeRemote({'2026-10-20': DayRecord(minutes: null, stamp: newer)});
      expect(state.shifts, isEmpty);
      expect(state.dayRecords['2026-10-20']!.deleted, isTrue);
    });

    test('результат зберігається на телефоні', () async {
      final (state, prefs, _) = await make();
      state.mergeRemote({'2026-10-22': const DayRecord(minutes: 600, stamp: 5)});
      final again = AppState(prefs);
      expect(again.shifts['2026-10-22'], 600);
      expect(again.dayRecords['2026-10-22']!.stamp, 5);
    });

    test('старі дані без часу зміни: хмарний запис перемагає', () async {
      // Дані, збережені до появи синхронізації, не мають часу зміни (0).
      final (state, _, _) = await make({'shifts_v1': '{"2026-10-20":480}'});
      expect(state.dayRecords['2026-10-20']!.stamp, 0);
      state.mergeRemote({'2026-10-20': const DayRecord(minutes: 720, stamp: 1)});
      expect(state.shifts['2026-10-20'], 720);
    });
  });

  group('resetAllData', () {
    test('стирає виходи, чернетку й таймер, але не налаштування', () async {
      final (state, prefs, _) = await make();
      state.setShifts([day], 480);
      state.setPlan([day], 600);
      state.startTimer(DateTime(2026, 10, 24, 8));
      state.setDefaultShiftMinutes(600);
      state.resetAllData();
      expect(state.shifts, isEmpty);
      expect(state.plan, isEmpty);
      expect(state.dayRecords, isEmpty);
      expect(state.timerRunning, isFalse);
      expect(state.defaultShiftMinutes, 600);

      final again = AppState(prefs);
      expect(again.shifts, isEmpty);
      expect(again.timerRunning, isFalse);
    });
  });
}
