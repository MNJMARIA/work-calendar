// Тести правил злиття днів між телефонами та хмарою.
// Запуск: flutter test test/records_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/diagnostics.dart';
import 'package:work_calendar/sync/records.dart';

DayRecord r(int? minutes, int stamp) => DayRecord(minutes: minutes, stamp: stamp);

void main() {
  group('pickNewer', () {
    test('пізніший час перемагає', () {
      expect(pickNewer(r(480, 10), r(720, 20)), r(720, 20));
      expect(pickNewer(r(720, 20), r(480, 10)), r(720, 20));
    });

    test('видалення пізніше за зміну перемагає', () {
      expect(pickNewer(r(480, 10), r(null, 20)), r(null, 20));
    });

    test('при рівному часі результат однаковий у будь-якому порядку', () {
      expect(pickNewer(r(480, 10), r(720, 10)), pickNewer(r(720, 10), r(480, 10)));
      expect(pickNewer(r(480, 10), r(null, 10)), pickNewer(r(null, 10), r(480, 10)));
    });
  });

  group('mergeDays', () {
    test('нові дні з хмари додаються на телефон', () {
      final res = mergeDays({}, {'2026-10-20': r(720, 5)});
      expect(res.merged, {'2026-10-20': r(720, 5)});
      expect(res.localNeedsUpdate, isTrue);
      expect(res.remoteNeedsUpdate, isFalse);
    });

    test('локальні дні, яких немає в хмарі, лишаються і йдуть у хмару', () {
      final res = mergeDays({'2026-10-20': r(720, 5)}, {});
      expect(res.merged, {'2026-10-20': r(720, 5)});
      expect(res.remoteNeedsUpdate, isTrue);
      expect(res.localNeedsUpdate, isFalse);
    });

    test('однакові дані: нічого оновлювати не треба', () {
      final res = mergeDays({'2026-10-20': r(720, 5)}, {'2026-10-20': r(720, 5)});
      expect(res.localNeedsUpdate, isFalse);
      expect(res.remoteNeedsUpdate, isFalse);
    });

    test('видалення (надгробок) не «воскресає»', () {
      final res = mergeDays(
        {'2026-10-20': r(720, 5)},
        {'2026-10-20': r(null, 9)},
      );
      expect(res.merged['2026-10-20'], r(null, 9));
      expect(res.localNeedsUpdate, isTrue);
    });

    test('старе видалення не перекриває новий вихід', () {
      final res = mergeDays(
        {'2026-10-20': r(720, 9)},
        {'2026-10-20': r(null, 5)},
      );
      expect(res.merged['2026-10-20'], r(720, 9));
      expect(res.remoteNeedsUpdate, isTrue);
    });

    test('різні дні зливаються разом', () {
      final res = mergeDays(
        {'2026-10-20': r(720, 5)},
        {'2026-10-21': r(480, 6)},
      );
      expect(res.merged.keys.toSet(), {'2026-10-20', '2026-10-21'});
      expect(res.localNeedsUpdate, isTrue);
      expect(res.remoteNeedsUpdate, isTrue);
    });
  });

  group('Місяць у хмарі', () {
    test('monthOfDayKey', () {
      expect(monthOfDayKey('2026-10-24'), '2026-10');
    });

    test('вміст місяця проходить туди й назад', () {
      final days = {'2026-10-21': r(480, 6), '2026-10-20': r(null, 5)};
      expect(parseMonthPayload(monthPayload(days)), days);
    });

    test('порожній вміст читається як порожній місяць', () {
      expect(parseMonthPayload({}), isEmpty);
    });

    test('відбиток не залежить від порядку', () {
      final a = {'2026-10-20': r(720, 5), '2026-10-21': r(480, 6)};
      final b = {'2026-10-21': r(480, 6), '2026-10-20': r(720, 5)};
      expect(digestOf(a), digestOf(b));
      expect(digestOf(a), isNot(digestOf({'2026-10-20': r(721, 5)})));
    });

    test('дні розкладаються по місяцях', () {
      final grouped = groupByMonth({
        '2026-10-31': r(1, 1),
        '2026-11-01': r(2, 2),
        '2026-11-02': r(3, 3),
      });
      expect(grouped.keys.toSet(), {'2026-10', '2026-11'});
      expect(grouped['2026-11']!.length, 2);
    });
  });

  group('DayRecord', () {
    test('JSON туди й назад, включно з видаленням', () {
      expect(DayRecord.fromJson(r(720, 5).toJson()), r(720, 5));
      expect(DayRecord.fromJson(r(null, 7).toJson()), r(null, 7));
      expect(r(null, 7).deleted, isTrue);
    });

    test('відсутній час читається як 0', () {
      expect(DayRecord.fromJson({'m': 60}).stamp, 0);
    });
  });

  group('Журнал подій', () {
    setUp(AppLog.clear);

    test('зберігає рядки з часом і віддає хвіст', () {
      AppLog.add('один');
      AppLog.add('два');
      AppLog.add('три');
      final tail = AppLog.tail(2);
      expect(tail.length, 2);
      expect(tail.first, endsWith('два'));
      expect(tail.last, endsWith('три'));
    });

    test('тримає не більше 80 рядків', () {
      for (var i = 0; i < 100; i++) {
        AppLog.add('рядок $i');
      }
      expect(AppLog.tail(500).length, 80);
      expect(AppLog.tail(1).single, endsWith('рядок 99'));
    });
  });
}
