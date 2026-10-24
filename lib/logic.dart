// Чиста логіка розрахунків «Робочого календаря».
//
// Тут НЕМАЄ Flutter — лише Dart. Тому ці функції легко тестувати
// командою `flutter test`, а пізніше можна без змін використати в інших місцях.

// ─────────────────────────────────────────────────────────────
// Константи
// ─────────────────────────────────────────────────────────────

/// Стандартна тривалість виходу на роботу: 12 годин (у хвилинах).
const int kDefaultShiftMinutes = 12 * 60;

/// Норма одного буднього дня: 8 годин (у хвилинах).
const int kDayNormMinutes = 8 * 60;

/// Норма тижня: 5 буднів × 8 годин = 40 годин (у хвилинах).
const int kWeekNormMinutes = 5 * kDayNormMinutes;

const List<String> kMonthsNominative = [
  'Січень', 'Лютий', 'Березень', 'Квітень', 'Травень', 'Червень',
  'Липень', 'Серпень', 'Вересень', 'Жовтень', 'Листопад', 'Грудень',
];

const List<String> kMonthsGenitive = [
  'січня', 'лютого', 'березня', 'квітня', 'травня', 'червня',
  'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня',
];

const List<String> kWeekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

const List<String> kWeekdaysFull = [
  'понеділок', 'вівторок', 'середа', 'четвер', "п'ятниця", 'субота', 'неділя',
];

// ─────────────────────────────────────────────────────────────
// Дати
// ─────────────────────────────────────────────────────────────

/// Число з нулем попереду: 5 → "05".
String pad2(int n) => n.toString().padLeft(2, '0');

/// Ключ дня у форматі РРРР-ММ-ДД, наприклад "2026-10-24".
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${pad2(d.month)}-${pad2(d.day)}';

/// Лише дата, без часу (північ за місцевим часом).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Додати (або відняти) дні. Через конструктор DateTime, а не Duration,
/// щоб перехід на літній/зимовий час не зсував дату.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Понеділок того тижня, до якого належить дата d.
DateTime mondayOf(DateTime d) => addDays(d, -(d.weekday - 1));

/// Скільки днів у місяці (28, 29, 30 або 31).
/// Трюк: «нульовий» день наступного місяця = останній день цього.
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Скільки буднів (пн–пт) у місяці.
int workdaysInMonth(int year, int month) {
  var count = 0;
  for (var day = 1; day <= daysInMonth(year, month); day++) {
    if (DateTime(year, month, day).weekday <= DateTime.friday) count++;
  }
  return count;
}

/// Момент початку роботи за вибраним часом (година й хвилини).
/// Якщо цей час сьогодні ще не настав, вважаємо, що робота почалася вчора
/// (наприклад, зараз 02:00, а вибрано 20:00 — це була нічна зміна).
DateTime resolveStartTime(DateTime now, int hour, int minute) {
  final today = DateTime(now.year, now.month, now.day, hour, minute);
  if (!today.isAfter(now)) return today;
  return DateTime(now.year, now.month, now.day - 1, hour, minute);
}

/// Вид дня для кольорового виділення (вигляд «Тиждень»).
enum DayKind {
  /// Вихід уже відпрацьовано (сьогодні або раніше).
  worked,

  /// Вихід у плані (після сьогодні).
  planned,

  /// Минулий вихідний (сб/нд) без виходу.
  pastOff,

  /// Сьогодні, виходу ще немає.
  today,

  /// Звичайний день без виходу.
  none,
}

/// Визначає вид дня. [hasShift] — чи є в цей день вихід (або йде таймер).
DayKind dayKind(DateTime date, DateTime today, {required bool hasShift}) {
  final d = dateOnly(date);
  final t = dateOnly(today);
  final isFuture = d.isAfter(t);
  if (hasShift) return isFuture ? DayKind.planned : DayKind.worked;
  if (d == t) return DayKind.today;
  if (!isFuture && d.weekday >= DateTime.saturday) return DayKind.pastOff;
  return DayKind.none;
}

// ─────────────────────────────────────────────────────────────
// Години
// ─────────────────────────────────────────────────────────────

/// Місячна норма у хвилинах: будні × 8 год.
/// Не залежить від того, які виходи користувач поставив вручну.
int monthNormMinutes(int year, int month) =>
    workdaysInMonth(year, month) * kDayNormMinutes;

/// Ділення з округленням угору: 7 / 2 = 4.
int ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// Сума хвилин виходів за днями від [from] до [to] включно.
///
///  • [until] — рахуються лише дні до цієї дати включно
///    (так майбутні виходи не потрапляють у «відпрацьовано»);
///  • [overrideKey] + [overrideMinutes] — для дня з увімкненим таймером
///    замість збереженого виходу береться поточний час таймера.
int sumRange(
    Map<String, int> shifts,
    DateTime from,
    DateTime to, {
      DateTime? until,
      String? overrideKey,
      int overrideMinutes = 0,
    }) {
  var total = 0;
  var d = dateOnly(from);
  final end = dateOnly(to);
  while (!d.isAfter(end)) {
    if (until == null || !d.isAfter(until)) {
      final key = dayKey(d);
      total += (key == overrideKey) ? overrideMinutes : (shifts[key] ?? 0);
    }
    d = addDays(d, 1);
  }
  return total;
}

/// Сума хвилин виходів за місяць (див. [sumRange]).
int sumShifts(
    Map<String, int> shifts,
    int year,
    int month, {
      DateTime? until,
    }) {
  return sumRange(
    shifts,
    DateTime(year, month, 1),
    DateTime(year, month, daysInMonth(year, month)),
    until: until,
  );
}

// ─────────────────────────────────────────────────────────────
// Текст
// ─────────────────────────────────────────────────────────────

/// Хвилини → текст: «12 год» або «12 год 30 хв».
String fmtHours(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h год' : '$h год $m хв';
}

/// Коротка форма для клітинки календаря: «12г» або «12.5г».
String shortHours(int minutes) {
  if (minutes % 60 == 0) return '${minutes ~/ 60}г';
  return '${(minutes / 60).toStringAsFixed(1)}г';
}

/// Секунди → годинник «ГГ:ХХ:СС» (для таймера).
String fmtClock(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${pad2(h)}:${pad2(m)}:${pad2(s)}';
}

/// Перша літера велика: «субота» → «Субота».
String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
