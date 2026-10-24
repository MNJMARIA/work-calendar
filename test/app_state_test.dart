// Тести стану додатка (AppState): виходи, чернетка, таймер, налаштування,
// збереження на телефоні. Запуск: flutter test
//
// Справжнє сховище телефона тут підміняється «пам'яттю» —
// SharedPreferences.setMockInitialValues.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/logic.dart';

/// Створює AppState з порожнім (або заданим) сховищем.
Future<(AppState, SharedPreferences)> makeState([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return (AppState(prefs), prefs);
}

void main() {
  // Усі дати в тестах фіксовані: сьогодні = субота 24.10.2026.
  final today = DateTime(2026, 10, 24);
  final now = DateTime(2026, 10, 24, 12, 0);

  group('Виходи', () {
    test('на старті виходів немає', () async {
      final (state, _) = await makeState();
      expect(state.shifts, isEmpty);
      expect(state.plan, isEmpty);
    });

    test('setShifts ставить вихід на кілька днів', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20), DateTime(2026, 10, 21)], 720);
      expect(state.shifts, {'2026-10-20': 720, '2026-10-21': 720});
    });

    test('setShifts(null) прибирає вихід', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20)], 720);
      state.setShifts([DateTime(2026, 10, 20)], null);
      expect(state.shifts, isEmpty);
    });

    test('точні хвилини зберігаються без округлення (12 год 54 хв)', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20)], 12 * 60 + 54);
      expect(state.shifts['2026-10-20'], 774);
    });

    test('скасування повертає попередні значення', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20)], 600);
      final previous = state.setShifts(
        [DateTime(2026, 10, 20), DateTime(2026, 10, 21)],
        720,
      );
      expect(state.shifts, {'2026-10-20': 720, '2026-10-21': 720});

      state.restoreShifts(previous);
      expect(state.shifts, {'2026-10-20': 600});
    });

    test('зміни повідомляють слухачів', () async {
      final (state, _) = await makeState();
      var calls = 0;
      state.addListener(() => calls++);
      state.setShifts([DateTime(2026, 10, 20)], 720);
      state.restoreShifts({'2026-10-20': null});
      expect(calls, 2);
    });
  });

  group('Збереження на телефоні', () {
    test('виходи переживають перезапуск додатка', () async {
      final (state, prefs) = await makeState();
      state.setShifts([DateTime(2026, 10, 20)], 774);

      // «Перезапуск»: новий AppState над тим самим сховищем.
      final reloaded = AppState(prefs);
      expect(reloaded.shifts, {'2026-10-20': 774});
    });

    test('чернетка й налаштування переживають перезапуск', () async {
      final (state, prefs) = await makeState();
      state.setPlan([DateTime(2026, 11, 3)], 600);
      state.setShowRemaining(false);
      state.setThemeMode(ThemeMode.dark);
      state.setDefaultShiftMinutes(500);

      final reloaded = AppState(prefs);
      expect(reloaded.plan, {'2026-11-03': 600});
      expect(reloaded.showRemaining, isFalse);
      expect(reloaded.themeMode, ThemeMode.dark);
      expect(reloaded.defaultShiftMinutes, 500);
    });

    test('таймер переживає перезапуск', () async {
      final (state, prefs) = await makeState();
      final start = DateTime(2026, 10, 24, 8, 30);
      state.startTimer(start);

      final reloaded = AppState(prefs);
      expect(reloaded.timerRunning, isTrue);
      expect(reloaded.timerStart, start);
    });

    test('пошкоджені дані не валять додаток', () async {
      final (state, _) = await makeState({
        kShiftsKey: 'це не json',
        kPlanKey: '[1,2,3]',
        kSettingsKey: '{{{',
        kTimerKey: 'не дата',
      });
      expect(state.shifts, isEmpty);
      expect(state.plan, isEmpty);
      expect(state.showRemaining, isTrue);
      expect(state.defaultShiftMinutes, kDefaultShiftMinutes);
      expect(state.timerRunning, isFalse);
    });

    test('старі дані з MVP (shifts_v1) читаються', () async {
      final (state, _) = await makeState({
        kShiftsKey: jsonEncode({'2026-10-01': 720}),
      });
      expect(state.shifts, {'2026-10-01': 720});
    });

    test('невідома тема в налаштуваннях → системна', () async {
      final (state, _) = await makeState({
        kSettingsKey: jsonEncode({'theme': 'неонова'}),
      });
      expect(state.themeMode, ThemeMode.system);
    });
  });

  group('Відпрацьовані години', () {
    test('майбутні виходи не рахуються у відпрацьовані', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20)], 720);
      state.setShifts([DateTime(2026, 10, 25)], 720); // завтра
      final worked = state.workedBetween(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
        today,
        now,
      );
      expect(worked, 720);
    });

    test('вихід сьогодні рахується', () async {
      final (state, _) = await makeState();
      state.setShifts([today], 480);
      expect(state.dayWorked(today, today, now), 480);
    });

    test('dayWorked для майбутнього дня = 0', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 25)], 720);
      expect(state.dayWorked(DateTime(2026, 10, 25), today, now), 0);
    });

    test('ручна зміна виходу не змінює норму місяця', () async {
      final (state, _) = await makeState();
      final before = monthNormMinutes(2026, 10);
      state.setShifts([DateTime(2026, 10, 3)], 1000);
      expect(monthNormMinutes(2026, 10), before);
      expect(before, 176 * 60);
    });

    test('переробка допускається (більше за норму)', () async {
      final (state, _) = await makeState();
      final days = [for (var d = 1; d <= 20; d++) DateTime(2026, 10, d)];
      state.setShifts(days, 720); // 20 × 12 год = 240 год > 176 год
      final worked = state.workedBetween(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
        today,
        now,
      );
      expect(worked, 240 * 60);
      expect(worked > monthNormMinutes(2026, 10), isTrue);
    });
  });

  group('План дня і тижня', () {
    test('будній день без виходу: план 8 год', () async {
      final (state, _) = await makeState();
      expect(state.dayTarget(DateTime(2026, 10, 23)), 480); // п'ятниця
    });

    test('вихідний без виходу: план 0', () async {
      final (state, _) = await makeState();
      expect(state.dayTarget(DateTime(2026, 10, 24)), 0); // субота
      expect(state.dayTarget(DateTime(2026, 10, 25)), 0); // неділя
    });

    test('поставлений вихід задає план дня', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 24)], 720);
      expect(state.dayTarget(DateTime(2026, 10, 24)), 720);
    });

    test('dayLeft: скільки лишилось до плану', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 23)], 300);
      // п'ятниця: план 300 (вихід), відпрацьовано 300 → лишилось 0
      expect(state.dayLeft(DateTime(2026, 10, 23), today, now), 0);
    });

    test('dayLeft ніколи не від\'ємний', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 23)], 900);
      expect(state.dayLeft(DateTime(2026, 10, 23), today, now), 0);
    });

    test('weekLeft: 40 год мінус відпрацьоване, майбутнє не рахується', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20), DateTime(2026, 10, 21)], 720);
      state.setShifts([DateTime(2026, 10, 25)], 720); // неділя — майбутнє
      // відпрацьовано 24 год → лишилось 16 год
      expect(state.weekLeft(today, today, now), 16 * 60);
    });

    test('weekLeft = 0, коли 40 год уже є', () async {
      final (state, _) = await makeState();
      state.setShifts(
        [for (var d = 19; d <= 23; d++) DateTime(2026, 10, d)],
        720,
      );
      expect(state.weekLeft(today, today, now), 0);
    });
  });

  group('Таймер', () {
    test('старт і час, що минув', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 8, 0));
      expect(state.timerRunning, isTrue);
      expect(state.elapsedSeconds(DateTime(2026, 10, 24, 10, 0)), 7200);
    });

    test('другий старт ігнорується, поки перший іде', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 8, 0));
      state.startTimer(DateTime(2026, 10, 24, 9, 0));
      expect(state.timerStart, DateTime(2026, 10, 24, 8, 0));
    });

    test('від\'ємний час (старт у майбутньому) = 0', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 15, 0));
      expect(state.elapsedSeconds(DateTime(2026, 10, 24, 12, 0)), 0);
    });

    test('зміна часу початку', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 8, 0));
      state.setTimerStart(DateTime(2026, 10, 24, 7, 15));
      expect(state.timerStart, DateTime(2026, 10, 24, 7, 15));
    });

    test('setTimerStart без запущеного таймера нічого не робить', () async {
      final (state, _) = await makeState();
      state.setTimerStart(DateTime(2026, 10, 24, 7, 15));
      expect(state.timerRunning, isFalse);
    });

    test('день із таймером: план = стандартна тривалість', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 8, 0));
      expect(state.isTimerDay(today), isTrue);
      expect(state.dayTarget(today), kDefaultShiftMinutes);
    });

    test('у відпрацьоване дня береться час таймера', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 8, 0));
      expect(state.dayWorked(today, today, now), 4 * 60); // 08:00 → 12:00
    });

    test('завершення зберігає вихід у день початку', () async {
      final (state, prefs) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 8, 0));
      state.finishTimer(DateTime(2026, 10, 24, 20, 30));
      expect(state.shifts['2026-10-24'], 12 * 60 + 30);
      expect(state.timerRunning, isFalse);
      expect(prefs.getString(kTimerKey), isNull);
    });

    test('нічна зміна належить дню початку', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 23, 20, 0));
      state.finishTimer(DateTime(2026, 10, 24, 8, 0));
      expect(state.shifts['2026-10-23'], 12 * 60);
      expect(state.shifts.containsKey('2026-10-24'), isFalse);
    });

    test('дуже коротка робота зберігається як мінімум 1 хв', () async {
      final (state, _) = await makeState();
      final start = DateTime(2026, 10, 24, 8, 0);
      state.startTimer(start);
      state.finishTimer(start.add(const Duration(seconds: 20)));
      expect(state.shifts['2026-10-24'], 1);
    });

    test('скасування таймера нічого не зберігає', () async {
      final (state, _) = await makeState();
      state.startTimer(DateTime(2026, 10, 24, 8, 0));
      state.discardTimer();
      expect(state.timerRunning, isFalse);
      expect(state.shifts, isEmpty);
    });

    test('finishTimer без таймера нічого не робить', () async {
      final (state, _) = await makeState();
      state.finishTimer(now);
      expect(state.shifts, isEmpty);
    });
  });

  group('Чернетка планування', () {
    test('чернетка не змінює справжні виходи', () async {
      final (state, _) = await makeState();
      state.setPlan([DateTime(2026, 11, 3)], 720);
      expect(state.plan, {'2026-11-03': 720});
      expect(state.shifts, isEmpty);
    });

    test('скасування зміни чернетки', () async {
      final (state, _) = await makeState();
      final previous = state.setPlan([DateTime(2026, 11, 3)], 720);
      state.restorePlan(previous);
      expect(state.plan, isEmpty);
    });

    test('copyShiftsToPlan копіює лише майбутні дні вибраного періоду', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20)], 720); // минуле
      state.setShifts([DateTime(2026, 10, 24)], 720); // сьогодні
      state.setShifts([DateTime(2026, 10, 27)], 600); // майбутнє
      state.setShifts([DateTime(2026, 11, 2)], 600); // інший місяць

      final previous = state.copyShiftsToPlan(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
        today,
      );
      expect(state.plan, {'2026-10-27': 600});
      expect(previous.length, 1);
    });

    test('copyShiftsToPlan без майбутніх виходів повертає порожнє', () async {
      final (state, _) = await makeState();
      state.setShifts([DateTime(2026, 10, 20)], 720);
      final previous = state.copyShiftsToPlan(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
        today,
      );
      expect(previous, isEmpty);
    });

    test('clearPlanBetween чистить лише вибраний місяць', () async {
      final (state, _) = await makeState();
      state.setPlan([DateTime(2026, 10, 27), DateTime(2026, 11, 3)], 720);
      final previous = state.clearPlanBetween(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
      );
      expect(state.plan, {'2026-11-03': 720});

      state.restorePlan(previous);
      expect(state.plan.length, 2);
    });
  });

  group('Налаштування', () {
    test('значення за замовчуванням', () async {
      final (state, _) = await makeState();
      expect(state.showRemaining, isTrue);
      expect(state.themeMode, ThemeMode.system);
      expect(state.defaultShiftMinutes, 720);
    });

    test('стандартна тривалість: допустимі межі 1 хв … 24 год', () async {
      final (state, _) = await makeState();
      state.setDefaultShiftMinutes(0);
      expect(state.defaultShiftMinutes, 720);
      state.setDefaultShiftMinutes(24 * 60 + 1);
      expect(state.defaultShiftMinutes, 720);
      state.setDefaultShiftMinutes(1);
      expect(state.defaultShiftMinutes, 1);
      state.setDefaultShiftMinutes(7 * 60 + 45);
      expect(state.defaultShiftMinutes, 465);
    });

    test('перемикач «Показувати залишок»', () async {
      final (state, _) = await makeState();
      state.setShowRemaining(false);
      expect(state.showRemaining, isFalse);
      state.setShowRemaining(true);
      expect(state.showRemaining, isTrue);
    });
  });
}
