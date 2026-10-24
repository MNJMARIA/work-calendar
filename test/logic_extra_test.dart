// Додаткові тести розрахунків: крайні випадки (межі місяців і років,
// перехід на літній/зимовий час, формати тексту, вибір часу).
// Запуск: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/duration_picker.dart';
import 'package:work_calendar/logic.dart';

void main() {
  group('Календар: місяці й роки', () {
    test('кількість днів: звичайний і високосний рік', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2000, 2), 29); // ділиться на 400
      expect(daysInMonth(2100, 2), 28); // ділиться на 100, але не на 400
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
    });

    test('норма: січень 2027 = 21 будень = 168 год', () {
      expect(workdaysInMonth(2027, 1), 21);
      expect(monthNormMinutes(2027, 1), 168 * 60);
    });

    test('норма: грудень 2026 = 23 будні = 184 год', () {
      expect(workdaysInMonth(2026, 12), 23);
      expect(monthNormMinutes(2026, 12), 184 * 60);
    });

    test('норма завжди = будні × 8 год, а буднів 20–23', () {
      for (var year = 2026; year <= 2030; year++) {
        for (var month = 1; month <= 12; month++) {
          final days = workdaysInMonth(year, month);
          expect(days, inInclusiveRange(20, 23), reason: '$month.$year');
          expect(monthNormMinutes(year, month), days * 480, reason: '$month.$year');
        }
      }
    });

    test('перехід через новий рік', () {
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addDays(DateTime(2027, 1, 1), -1), DateTime(2026, 12, 31));
    });

    test('mondayOf: неділя належить тижню, що починається в понеділок', () {
      expect(mondayOf(DateTime(2026, 10, 25)), DateTime(2026, 10, 19));
    });
  });

  group('Перехід на зимовий/літній час', () {
    test('додавання днів ніколи не зсуває дату (весь рік)', () {
      var d = DateTime(2026, 1, 1);
      for (var i = 0; i < 365; i++) {
        final next = addDays(d, 1);
        // Наступний календарний день, час — північ.
        expect(next.hour, 0, reason: dayKey(next));
        expect(next.difference(d).inHours, inInclusiveRange(23, 25),
            reason: dayKey(next));
        expect(
          next.weekday,
          d.weekday % 7 + 1,
          reason: 'день тижня має йти по колу: ${dayKey(next)}',
        );
        d = next;
      }
      expect(d, DateTime(2027, 1, 1));
    });

    test('дні в ніч переходу (25.10.2026 і 29.03.2026) мають свій ключ', () {
      expect(dayKey(addDays(DateTime(2026, 10, 24), 1)), '2026-10-25');
      expect(dayKey(addDays(DateTime(2026, 10, 25), 1)), '2026-10-26');
      expect(dayKey(addDays(DateTime(2026, 3, 28), 1)), '2026-03-29');
      expect(dayKey(addDays(DateTime(2026, 3, 29), 1)), '2026-03-30');
    });

    test('тиждень завжди має рівно 7 різних днів', () {
      final monday = mondayOf(DateTime(2026, 10, 25));
      final keys = {for (var i = 0; i < 7; i++) dayKey(addDays(monday, i))};
      expect(keys.length, 7);
    });
  });

  group('Сума виходів', () {
    test('діапазон через межу місяців', () {
      final shifts = {'2026-10-31': 100, '2026-11-01': 200, '2026-11-02': 999};
      expect(
        sumRange(shifts, DateTime(2026, 10, 26), DateTime(2026, 11, 1)),
        300,
      );
    });

    test('порожній діапазон (from після to) = 0', () {
      final shifts = {'2026-10-20': 720};
      expect(sumRange(shifts, DateTime(2026, 10, 25), DateTime(2026, 10, 19)), 0);
    });

    test('час у даті ігнорується (рахується день)', () {
      final shifts = {'2026-10-20': 720};
      expect(
        sumRange(shifts, DateTime(2026, 10, 20, 23, 59), DateTime(2026, 10, 20, 1)),
        720,
      );
    });

    test('until обмежує по даті, а не по часу', () {
      final shifts = {'2026-10-24': 720};
      expect(
        sumRange(
          shifts,
          DateTime(2026, 10, 24),
          DateTime(2026, 10, 24),
          until: DateTime(2026, 10, 24, 0, 0),
        ),
        720,
      );
    });

    test('sumShifts не чіпає виходи інших місяців', () {
      final shifts = {'2026-09-30': 1, '2026-10-01': 10, '2026-11-01': 100};
      expect(sumShifts(shifts, 2026, 10), 10);
    });
  });

  group('Час початку роботи', () {
    test('точно зараз → сьогодні', () {
      final now = DateTime(2026, 10, 24, 8, 0);
      expect(resolveStartTime(now, 8, 0), DateTime(2026, 10, 24, 8, 0));
    });

    test('хвилина тому → сьогодні, хвилина вперед → вчора', () {
      final now = DateTime(2026, 10, 24, 8, 0);
      expect(resolveStartTime(now, 7, 59), DateTime(2026, 10, 24, 7, 59));
      expect(resolveStartTime(now, 8, 1), DateTime(2026, 10, 23, 8, 1));
    });

    test('1 січня вчора = 31 грудня', () {
      final now = DateTime(2027, 1, 1, 1, 0);
      expect(resolveStartTime(now, 22, 0), DateTime(2026, 12, 31, 22, 0));
    });
  });

  group('Текст', () {
    test('fmtHours: нуль, хвилини, межа доби', () {
      expect(fmtHours(0), '0 год');
      expect(fmtHours(59), '0 год 59 хв');
      expect(fmtHours(60), '1 год');
      expect(fmtHours(774), '12 год 54 хв');
      expect(fmtHours(1439), '23 год 59 хв');
      expect(fmtHours(1440), '24 год');
    });

    test('shortHours: цілі й дробові години', () {
      expect(shortHours(720), '12г');
      expect(shortHours(750), '12.5г');
      expect(shortHours(480), '8г');
    });

    test('fmtClock: межі', () {
      expect(fmtClock(0), '00:00:00');
      expect(fmtClock(59), '00:00:59');
      expect(fmtClock(3600), '01:00:00');
      expect(fmtClock(86399), '23:59:59');
      expect(fmtClock(100 * 3600), '100:00:00');
    });

    test('dayKey додає нулі', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKey(DateTime(999, 1, 1)), '0999-01-01');
    });

    test('capitalize: порожній рядок і українські літери', () {
      expect(capitalize(''), '');
      expect(capitalize('неділя'), 'Неділя');
      expect(capitalize('Субота'), 'Субота');
    });

    test('назви місяців і днів: по 12 і по 7', () {
      expect(kMonthsNominative.length, 12);
      expect(kMonthsGenitive.length, 12);
      expect(kWeekdaysShort.length, 7);
      expect(kWeekdaysFull.length, 7);
    });
  });

  group('Планування: скільки виходів не вистачає', () {
    test('ceilDiv: нуль і точні ділення', () {
      expect(ceilDiv(0, 720), 0);
      expect(ceilDiv(720, 720), 1);
      expect(ceilDiv(721, 720), 2);
    });

    test('приклад: не вистачає 30 год при виходах по 12 год → 3', () {
      expect(ceilDiv(30 * 60, 12 * 60), 3);
    });
  });

  group('Вибір тривалості колесами', () {
    test('межі: 0 … 23:59', () {
      expect(kMaxPickMinutes, 1439);
      expect(clampPickMinutes(-5), 0);
      expect(clampPickMinutes(0), 0);
      expect(clampPickMinutes(774), 774);
      expect(clampPickMinutes(1440), 1439);
      expect(clampPickMinutes(99999), 1439);
    });
  });

  group('Вид дня для кольорів (dayKind)', () {
    final today = DateTime(2026, 10, 24); // субота

    test('відпрацьований вихід: минулий день і сьогодні', () {
      expect(dayKind(DateTime(2026, 10, 20), today, hasShift: true), DayKind.worked);
      expect(dayKind(today, today, hasShift: true), DayKind.worked);
    });

    test('вихід у майбутньому — «У плані»', () {
      expect(dayKind(DateTime(2026, 10, 25), today, hasShift: true), DayKind.planned);
      expect(dayKind(DateTime(2026, 11, 3), today, hasShift: true), DayKind.planned);
    });

    test('сьогодні без виходу — «Сьогодні» (навіть якщо це вихідний)', () {
      expect(dayKind(today, today, hasShift: false), DayKind.today);
    });

    test('минулі вихідні без виходу', () {
      expect(dayKind(DateTime(2026, 10, 17), today, hasShift: false), DayKind.pastOff); // сб
      expect(dayKind(DateTime(2026, 10, 18), today, hasShift: false), DayKind.pastOff); // нд
    });

    test('минулий вихідний, у який був вихід, — відпрацьований', () {
      expect(dayKind(DateTime(2026, 10, 17), today, hasShift: true), DayKind.worked);
    });

    test('звичайні дні без виходу', () {
      expect(dayKind(DateTime(2026, 10, 20), today, hasShift: false), DayKind.none); // минулий будній
      expect(dayKind(DateTime(2026, 10, 26), today, hasShift: false), DayKind.none); // майбутній будній
      expect(dayKind(DateTime(2026, 10, 25), today, hasShift: false), DayKind.none); // майбутній вихідний
    });

    test('час доби не впливає на результат', () {
      expect(
        dayKind(DateTime(2026, 10, 24, 15, 30), DateTime(2026, 10, 24, 3, 0), hasShift: false),
        DayKind.today,
      );
    });
  });

  group('Константи', () {
    test('стандартні значення', () {
      expect(kDefaultShiftMinutes, 720);
      expect(kDayNormMinutes, 480);
      expect(kWeekNormMinutes, 2400);
    });
  });
}
