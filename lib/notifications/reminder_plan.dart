// План нагадувань про зміни. Чистий Dart: без Flutter і без плагінів,
// тому його легко перевіряти тестами.
//
// Нагадування ставляться на найближчі дні, у які в календарі є вихід
// (і справжній, і запланований).

import '../logic.dart';

/// Одне нагадування, яке треба показати в [when].
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime when;
  final String title;
  final String body;

  @override
  String toString() => '$id|${when.toIso8601String()}|$title';
}

/// На скільки днів уперед ставимо нагадування.
const int kReminderHorizonDays = 30;

/// Стабільний номер сповіщення: день × 2 + вид (0 — початок, 1 — кінець).
int reminderId(DateTime day, int kind) {
  final days = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(2020, 1, 1))
      .inDays;
  return days * 2 + kind;
}

/// Збирає список нагадувань.
///
/// [shifts] — виходи з календаря (ключ дня → хвилини). [startMinutes] і
/// [endMinutes] — час доби в хвилинах від півночі. Минулий час не планується.
List<PlannedReminder> planReminders({
  required Map<String, int> shifts,
  required DateTime now,
  required bool start,
  required int startMinutes,
  required bool end,
  required int endMinutes,
  int horizonDays = kReminderHorizonDays,
}) {
  final result = <PlannedReminder>[];
  if (!start && !end) return result;
  final today = dateOnly(now);
  for (var i = 0; i <= horizonDays; i++) {
    final day = addDays(today, i);
    final minutes = shifts[dayKey(day)] ?? 0;
    if (minutes <= 0) continue;

    if (start) {
      final when = DateTime(day.year, day.month, day.day, startMinutes ~/ 60, startMinutes % 60);
      if (when.isAfter(now)) {
        result.add(
          PlannedReminder(
            id: reminderId(day, 0),
            when: when,
            title: 'Сьогодні вихід на роботу',
            body: 'Запланована зміна: ${fmtHours(minutes)}. '
                'Не забудь натиснути «Вийшов на роботу».',
          ),
        );
      }
    }
    if (end) {
      final when = DateTime(day.year, day.month, day.day, endMinutes ~/ 60, endMinutes % 60);
      if (when.isAfter(now)) {
        result.add(
          PlannedReminder(
            id: reminderId(day, 1),
            when: when,
            title: 'Кінець зміни',
            body: 'Не забудь закінчити зміну й перевірити години за сьогодні.',
          ),
        );
      }
    }
  }
  return result;
}

/// Час у вигляді «07:30» для екрана налаштувань.
String fmtClockMinutes(int minutes) => '${pad2(minutes ~/ 60)}:${pad2(minutes % 60)}';
