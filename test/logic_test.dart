// Тести розрахунків. Запуск: flutter test
//
// Це найважливіші тести проєкту: вони перевіряють норму годин
// і правило «майбутні виходи не рахуються у відпрацьовані».

import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/logic.dart';

void main() {
  group('Норма місяця (будні × 8 год)', () {
    test('жовтень 2026: 31 день, 22 будні = 176 год', () {
      expect(workdaysInMonth(2026, 10), 22);
      expect(monthNormMinutes(2026, 10), 176 * 60);
    });

    test('листопад 2026: 30 днів = 168 год', () {
      expect(monthNormMinutes(2026, 11), 168 * 60);
    });

    test('лютий 2027: 28 днів = 160 год', () {
      expect(daysInMonth(2027, 2), 28);
      expect(monthNormMinutes(2027, 2), 160 * 60);
    });

    test('лютий 2028 (високосний): 29 днів = 168 год', () {
      expect(daysInMonth(2028, 2), 29);
      expect(monthNormMinutes(2028, 2), 168 * 60);
    });

    test('норма тижня = 40 год', () {
      expect(kWeekNormMinutes, 40 * 60);
    });
  });

  group('Відпрацьовані години', () {
    // Два виходи по 12 год: один у минулому, один у майбутньому.
    final shifts = {'2026-10-20': 720, '2026-10-25': 720};
    final today = DateTime(2026, 10, 24);

    test('майбутній вихід не рахується у відпрацьовані', () {
      expect(sumShifts(shifts, 2026, 10, until: today), 720);
    });

    test('без обмеження по даті рахуються всі виходи (план + факт)', () {
      expect(sumShifts(shifts, 2026, 10), 1440);
    });

    test('вихід сьогодні рахується (дата включно)', () {
      final withToday = {'2026-10-24': 720};
      expect(sumShifts(withToday, 2026, 10, until: today), 720);
    });
  });

  group('Тиждень і таймер', () {
    final today = DateTime(2026, 10, 24); // субота

    test('понеділок тижня для суботи 24.10.2026 — це 19.10.2026', () {
      expect(mondayOf(today), DateTime(2026, 10, 19));
    });

    test('понеділок для самого понеділка — він сам', () {
      expect(mondayOf(DateTime(2026, 10, 19)), DateTime(2026, 10, 19));
    });

    test('додавання днів переходить через кінець місяця', () {
      expect(addDays(DateTime(2026, 10, 31), 1), DateTime(2026, 11, 1));
    });

    test('день із таймером рахується за часом таймера, а не за збереженим', () {
      final shifts = {'2026-10-20': 720, '2026-10-21': 720};
      final total = sumRange(
        shifts,
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 25),
        until: today,
        overrideKey: '2026-10-21',
        overrideMinutes: 30,
      );
      expect(total, 750);
    });

    test('таймер у майбутньому дні не потрапляє у відпрацьовані', () {
      final total = sumRange(
        {},
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 25),
        until: today,
        overrideKey: '2026-10-25',
        overrideMinutes: 600,
      );
      expect(total, 0);
    });
  });

  group('Час початку роботи', () {
    test('час, що вже минув сьогодні, лишається сьогоднішнім', () {
      final now = DateTime(2026, 10, 24, 19, 0);
      expect(resolveStartTime(now, 8, 0), DateTime(2026, 10, 24, 8, 0));
    });

    test('час, що ще не настав, означає вчорашню (нічну) зміну', () {
      final now = DateTime(2026, 10, 24, 2, 0);
      expect(resolveStartTime(now, 20, 0), DateTime(2026, 10, 23, 20, 0));
    });

    test('на межі місяця «вчора» — це останній день попереднього місяця', () {
      final now = DateTime(2026, 11, 1, 1, 0);
      expect(resolveStartTime(now, 22, 30), DateTime(2026, 10, 31, 22, 30));
    });
  });

  group('Планування', () {
    test('ділення з округленням угору', () {
      expect(ceilDiv(1440, 720), 2);
      expect(ceilDiv(1441, 720), 3);
      expect(ceilDiv(1, 720), 1);
    });
  });

  group('Форматування', () {
    test('повні години', () => expect(fmtHours(720), '12 год'));
    test('години й хвилини', () => expect(fmtHours(750), '12 год 30 хв'));
    test('ключ дня', () => expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05'));
    test('годинник таймера', () => expect(fmtClock(3725), '01:02:05'));
    test('велика літера', () => expect(capitalize("п'ятниця"), "П'ятниця"));
  });
}