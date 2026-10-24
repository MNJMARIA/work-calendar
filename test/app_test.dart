// Тести екранів: тести самі «натискають» кнопки, як це робила б ти пальцем.
// Запуск: flutter test
//
// Важливо: тести працюють із ПОТОЧНИМ місяцем (він береться з годинника
// телефона/комп'ютера), тому 1-ше і 2-ге числа місяця завжди вже минули
// або сьогодні — їх можна редагувати у вкладці «Календар».

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/dialogs.dart';
import 'package:work_calendar/duration_picker.dart';
import 'package:work_calendar/logic.dart';
import 'package:work_calendar/app.dart';
import 'package:work_calendar/widgets.dart';

// ── Допоміжні функції ────────────────────────────────────────

/// Запускає додаток на «екрані телефона» 360×800 з потрібним сховищем.
Future<AppState> pumpApp(
    WidgetTester tester, {
      Map<String, Object> initial = const {},
    }) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  await tester.pumpWidget(WorkCalendarApp(state: state));
  await tester.pump();
  return state;
}

/// Закінчує тест: чекає, поки зникнуть повідомлення, і прибирає екран.
Future<void> finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox());
}

/// Клітинка дня [day] у відкритій вкладці.
Finder dayCell(int day) =>
    find.byWidgetPredicate((w) => w is DayCellBox && w.day == day);

/// Ключ дня [day] поточного місяця.
String keyOf(int day) {
  final now = DateTime.now();
  return dayKey(DateTime(now.year, now.month, day));
}

/// Ключ дня [day] наступного місяця.
String nextMonthKeyOf(int day) {
  final now = DateTime.now();
  return dayKey(DateTime(now.year, now.month + 1, day));
}

String shiftsJson(Map<String, int> shifts) => jsonEncode(shifts);

/// Текст великого підсумку у нижньому вікні («12 год 54 хв»).
String sheetTotal(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('shift-total'))).data!;

/// Відкрити вікно виходу на сьогодні через вигляд «День»
/// (кнопка вгорі сторінки — її не перекриває жовта кнопка внизу).
Future<void> openTodaySheet(WidgetTester tester) async {
  await tester.tap(find.text('День'));
  await tester.pump();
  // Коли таймер уже йде, картка «Йде робота» зсуває кнопку нижче екрана:
  // спершу прокручуємо до неї, інакше натискання «промахується».
  final add = find.text('Додати вихід на роботу');
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
  await tester.pumpAndSettle();
}

/// Перейти у вкладку «Планування».
Future<void> openPlanningTab(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Планування'),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('Старт додатка', () {
    testWidgets('показує назву, норму місяця і нижнє меню', (tester) async {
      await pumpApp(tester);
      final now = DateTime.now();
      final norm = monthNormMinutes(now.year, now.month);

      expect(find.text('Робочий календар'), findsOneWidget);
      expect(find.textContaining('норма ${fmtHours(norm)}'), findsOneWidget);
      expect(find.text('Календар'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Планування'),
        ),
        findsOneWidget,
      );
      expect(find.text('Вийшов на роботу'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('кільце показує відсоток від норми', (tester) async {
      final now = DateTime.now();
      final norm = monthNormMinutes(now.year, now.month);
      await pumpApp(tester, initial: {kShiftsKey: shiftsJson({keyOf(1): 720})});

      final percent = (720 * 100 / norm).round();
      expect(find.text('$percent %'), findsOneWidget);
      expect(find.text('12 год з ${fmtHours(norm)}'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('збережені виходи видно в сітці місяця', (tester) async {
      await pumpApp(tester, initial: {kShiftsKey: shiftsJson({keyOf(1): 720})});
      expect(
        find.descendant(of: dayCell(1), matching: find.text('12г')),
        findsOneWidget,
      );
      await finish(tester);
    });
  });

  group('Вікно вибору годин і хвилин', () {
    testWidgets('тап по дню відкриває вікно, стандартно 12 год', (tester) async {
      await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();

      expect(find.text('Додати вихід на роботу'), findsOneWidget);
      expect(sheetTotal(tester), '12 год');
      expect(find.byKey(const Key('wheel-hours')), findsOneWidget);
      expect(find.byKey(const Key('wheel-minutes')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('зберегти без змін → 12 год', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Додати вихід на роботу'));
      await tester.pumpAndSettle();

      expect(state.shifts[keyOf(1)], 720);
      await finish(tester);
    });

    testWidgets('колесо годин і колесо хвилин змінюються окремо', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();

      // Годин: 12 → 15 (потягнули вгору на 3 позиції).
      await tester.drag(find.byKey(const Key('wheel-hours')), const Offset(0, -156));
      await tester.pumpAndSettle();
      expect(sheetTotal(tester), '15 год');

      // Хвилин: 0 → 10.
      await tester.drag(find.byKey(const Key('wheel-minutes')), const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(sheetTotal(tester), '15 год 10 хв');

      await tester.tap(find.text('Додати вихід на роботу'));
      await tester.pumpAndSettle();
      expect(state.shifts[keyOf(1)], 15 * 60 + 10);
      await finish(tester);
    });

    testWidgets('швидкий варіант «8 год» ставить рівно 8 год 0 хв', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ActionChip, '8 год'));
      await tester.pumpAndSettle();
      expect(sheetTotal(tester), '8 год');

      await tester.tap(find.text('Додати вихід на роботу'));
      await tester.pumpAndSettle();
      expect(state.shifts[keyOf(1)], 480);
      await finish(tester);
    });

    testWidgets('0 год 0 хв зберегти не можна', (tester) async {
      await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();

      // Тягнемо години вниз до нуля (12 позицій).
      await tester.drag(find.byKey(const Key('wheel-hours')), const Offset(0, 624));
      await tester.pumpAndSettle();

      expect(sheetTotal(tester), '0 хв');
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Додати вихід на роботу'),
      );
      expect(button.onPressed, isNull);
      await finish(tester);
    });

    testWidgets('існуючий вихід відкривається з його значенням', (tester) async {
      await pumpApp(tester, initial: {kShiftsKey: shiftsJson({keyOf(1): 774})});
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();

      expect(sheetTotal(tester), '12 год 54 хв');
      expect(find.text('Зберегти зміни'), findsOneWidget);
      expect(find.text('Прибрати вихід'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('«Прибрати вихід» видаляє день', (tester) async {
      final state = await pumpApp(
        tester,
        initial: {kShiftsKey: shiftsJson({keyOf(1): 720})},
      );
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Прибрати вихід'));
      await tester.pumpAndSettle();

      expect(state.shifts, isEmpty);
      await finish(tester);
    });

    testWidgets('закрити вікно тапом поза ним — нічого не змінюється', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(180, 20)); // тап поза вікном
      await tester.pumpAndSettle();
      expect(find.text('Додати вихід на роботу'), findsNothing);
      expect(state.shifts, isEmpty);
      await finish(tester);
    });
  });

  group('Окремий віджет DurationPicker', () {
    testWidgets('швидкі варіанти повертають правильні хвилини', (tester) async {
      var last = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPicker(initialMinutes: 0, onChanged: (v) => last = v),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(ActionChip, '6 год'));
      await tester.pumpAndSettle();
      expect(last, 360);

      await tester.tap(find.widgetWithText(ActionChip, '12 год'));
      await tester.pumpAndSettle();
      expect(last, 720);
    });

    testWidgets('початкове значення за межею обмежується 23:59', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPicker(initialMinutes: 5000, onChanged: (_) {}),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Повідомлення зникають через 2 секунди', () {
    testWidgets('з\'являється після збереження і зникає', (tester) async {
      await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Додати вихід на роботу'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Збережено: 1 дн. по 12 год'), findsOneWidget);

      // Через 1 секунду ще на місці.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Збережено: 1 дн. по 12 год'), findsOneWidget);

      // Через ~3 секунди вже зникло (навіть з кнопкою «Скасувати»).
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Збережено: 1 дн. по 12 год'), findsNothing);
      expect(find.text('Скасувати'), findsNothing);
      await finish(tester);
    });

    testWidgets('кнопка «Скасувати» повертає попередній стан', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Додати вихід на роботу'));
      // Чекаємо, поки повідомлення повністю виїде (інакше тап промахнеться).
      await tester.pumpAndSettle();
      expect(state.shifts[keyOf(1)], 720);

      await tester.tap(find.text('Скасувати'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.shifts, isEmpty);
      await finish(tester);
    });

    testWidgets('нове повідомлення замінює старе', (tester) async {
      await pumpApp(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Додати вихід на роботу'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(dayCell(2));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '8 год'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Додати вихід на роботу'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Старе повідомлення (12 год) замінилось новим (8 год).
      expect(find.text('Збережено: 1 дн. по 12 год'), findsNothing);
      expect(find.text('Збережено: 1 дн. по 8 год'), findsOneWidget);
      await finish(tester);
    });
  });

  group('Вибір кількох днів', () {
    testWidgets('довге натискання вмикає вибір, тап додає дні', (tester) async {
      await pumpApp(tester);
      await tester.longPress(dayCell(1));
      await tester.pump();
      expect(find.text('Вибрано: 1'), findsOneWidget);

      await tester.tap(dayCell(2));
      await tester.pump();
      expect(find.text('Вибрано: 2'), findsOneWidget);

      // Повторний тап знімає вибір з дня.
      await tester.tap(dayCell(2));
      await tester.pump();
      expect(find.text('Вибрано: 1'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('хрестик скасовує вибір', (tester) async {
      await pumpApp(tester);
      await tester.longPress(dayCell(1));
      await tester.pump();
      await tester.tap(find.byTooltip('Скасувати вибір'));
      await tester.pump();

      expect(find.textContaining('Вибрано:'), findsNothing);
      expect(find.text('Робочий календар'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('«Вибрати всі» вибирає всі дні місяця', (tester) async {
      await pumpApp(tester);
      final now = DateTime.now();
      await tester.longPress(dayCell(1));
      await tester.pump();
      await tester.tap(find.byTooltip('Вибрати всі'));
      await tester.pump();

      expect(
        find.text('Вибрано: ${daysInMonth(now.year, now.month)}'),
        findsOneWidget,
      );
      await finish(tester);
    });

    testWidgets('масово поставити 8 год двом дням', (tester) async {
      final state = await pumpApp(tester);
      await tester.longPress(dayCell(1));
      await tester.pump();
      await tester.tap(dayCell(2));
      await tester.pump();

      await tester.tap(find.byTooltip('Змінити години'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '8 год'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Застосувати до 2 дн.'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.shifts, {keyOf(1): 480, keyOf(2): 480});
      expect(find.textContaining('Вибрано:'), findsNothing);
      expect(find.text('Збережено: 2 дн. по 8 год'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('масово прибрати виходи', (tester) async {
      final state = await pumpApp(
        tester,
        initial: {kShiftsKey: shiftsJson({keyOf(1): 720, keyOf(2): 720})},
      );
      await tester.longPress(dayCell(1));
      await tester.pump();
      await tester.tap(dayCell(2));
      await tester.pump();
      await tester.tap(find.byTooltip('Прибрати виходи'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.shifts, isEmpty);
      await finish(tester);
    });
  });

  group('Види календаря', () {
    testWidgets('Місяць → Тиждень → День → Місяць', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Тиждень'));
      await tester.pump();
      expect(find.text('Відпрацьовано за тиждень'), findsOneWidget);

      await tester.tap(find.text('День'));
      await tester.pump();
      expect(find.text('Виходу немає'), findsOneWidget);
      expect(find.text('Додати вихід на роботу'), findsOneWidget);

      await tester.tap(find.text('Місяць'));
      await tester.pump();
      expect(dayCell(1), findsOneWidget);
      await finish(tester);
    });

    testWidgets('стрілки перемикають місяць, «Сьогодні» повертає назад', (tester) async {
      await pumpApp(tester);
      final now = DateTime.now();
      final next = DateTime(now.year, now.month + 1, 1);

      await tester.tap(find.byTooltip('Вперед'));
      await tester.pump();
      expect(
        find.text('${kMonthsNominative[next.month - 1]} ${next.year}'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Сьогодні'));
      await tester.pump();
      expect(
        find.text('${kMonthsNominative[now.month - 1]} ${now.year}'),
        findsOneWidget,
      );
      await finish(tester);
    });
  });

  group('Таймер «Вийшов на роботу»', () {
    testWidgets('старт зараз → іде відлік → завершення зберігає вихід', (tester) async {
      final state = await pumpApp(tester);

      await tester.tap(find.text('Вийшов на роботу'));
      await tester.pumpAndSettle();
      expect(find.text('Початок роботи'), findsOneWidget);
      expect(find.text('Почати відлік зараз'), findsOneWidget);

      await tester.tap(find.text('Почати'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.timerRunning, isTrue);
      expect(find.text('Йде робота'), findsOneWidget);
      expect(find.text('Завершив роботу'), findsOneWidget);
      expect(find.textContaining('Відлік іде з'), findsOneWidget);

      await tester.tap(find.text('Завершив роботу'));
      await tester.pumpAndSettle();
      expect(find.text('Завершити роботу?'), findsOneWidget);

      await tester.tap(find.text('Зберегти'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.timerRunning, isFalse);
      // Менше хвилини → зберігається мінімум 1 хв.
      expect(state.shifts[dayKey(DateTime.now())], 1);
      await finish(tester);
    });

    testWidgets('зняти галочку «зараз» показує вибір часу', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Вийшов на роботу'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.textContaining('Час початку:'), findsOneWidget);
      expect(find.textContaining('Відлік піде з'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('«Скасувати» у вікні старту не запускає таймер', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(find.text('Вийшов на роботу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Скасувати'));
      await tester.pumpAndSettle();

      expect(state.timerRunning, isFalse);
      expect(find.text('Вийшов на роботу'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('«Скасувати таймер» нічого не зберігає', (tester) async {
      final state = await pumpApp(tester);
      state.startTimer(DateTime.now());
      await tester.pump();

      await tester.tap(find.text('Завершив роботу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Скасувати таймер'));
      await tester.pumpAndSettle();

      expect(state.timerRunning, isFalse);
      expect(state.shifts, isEmpty);
      await finish(tester);
    });

    testWidgets('«Продовжити» лишає таймер увімкненим', (tester) async {
      final state = await pumpApp(tester);
      state.startTimer(DateTime.now());
      await tester.pump();

      await tester.tap(find.text('Завершив роботу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продовжити'));
      await tester.pumpAndSettle();

      expect(state.timerRunning, isTrue);
      await finish(tester);
    });

    testWidgets('таймер, запущений до перезапуску, продовжує йти', (tester) async {
      final start = DateTime.now().subtract(const Duration(hours: 2));
      final state = await pumpApp(
        tester,
        initial: {kTimerKey: start.toIso8601String()},
      );
      expect(state.timerRunning, isTrue);
      expect(find.text('Йде робота'), findsOneWidget);
      expect(find.text('Завершив роботу'), findsOneWidget);
      await finish(tester);
    });
  });

  group('Вихід на сьогодні: почати відлік', () {
    testWidgets('вікно сьогодні пропонує «Почати відлік»', (tester) async {
      final state = await pumpApp(tester);
      await openTodaySheet(tester);
      expect(find.byKey(const Key('start-timer-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('start-timer-button')));
      await tester.pumpAndSettle();
      expect(find.text('Початок роботи'), findsOneWidget);

      await tester.tap(find.text('Почати'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.timerRunning, isTrue);
      await finish(tester);
    });

    testWidgets('можна вибрати час початку', (tester) async {
      await pumpApp(tester);
      await openTodaySheet(tester);
      await tester.tap(find.byKey(const Key('start-timer-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.textContaining('Час початку:'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('для минулого дня кнопки відліку немає', (tester) async {
      await pumpApp(tester);
      if (DateTime.now().day == 1) return; // 1-ше число — це і є сьогодні
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('start-timer-button')), findsNothing);
      await finish(tester);
    });

    testWidgets('коли таймер уже йде, кнопки відліку немає', (tester) async {
      final state = await pumpApp(tester);
      state.startTimer(DateTime.now());
      await tester.pump();
      await openTodaySheet(tester);
      expect(find.byKey(const Key('start-timer-button')), findsNothing);
      await finish(tester);
    });

    test('SheetResult: звичайний і «таймер»', () {
      expect(const SheetResult(300).startTimer, isFalse);
      expect(const SheetResult(300).minutes, 300);
      expect(const SheetResult.timer().startTimer, isTrue);
      expect(const SheetResult.timer().minutes, isNull);
    });
  });

  group('Вигляд «Тиждень»: кольорове виділення', () {
    ColorScheme schemeOf(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(AppShell))).colorScheme;

    Finder rowOf(DateTime d) => find.byKey(Key('week-row-${dayKey(d)}'));

    testWidgets('сьогодні — акцентна рамка', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Тиждень'));
      await tester.pump();

      final today = dateOnly(DateTime.now());
      final card = tester.widget<AppCard>(rowOf(today));
      expect(card.borderColor, schemeOf(tester).primary);
      expect(card.borderWidth, greaterThan(1));
      await finish(tester);
    });

    testWidgets('відпрацьований вихід — колір primaryContainer', (tester) async {
      final today = dateOnly(DateTime.now());
      await pumpApp(
        tester,
        initial: {kShiftsKey: shiftsJson({dayKey(today): 720})},
      );
      await tester.tap(find.text('Тиждень'));
      await tester.pump();

      final card = tester.widget<AppCard>(rowOf(today));
      expect(card.color, schemeOf(tester).primaryContainer);
      await finish(tester);
    });

    testWidgets('вихід у плані — колір tertiaryContainer', (tester) async {
      final today = dateOnly(DateTime.now());
      final sunday = addDays(mondayOf(today), 6);
      if (!sunday.isAfter(today)) return; // сьогодні неділя — майбутніх днів тижня немає
      await pumpApp(
        tester,
        initial: {kShiftsKey: shiftsJson({dayKey(sunday): 600})},
      );
      await tester.tap(find.text('Тиждень'));
      await tester.pump();

      final card = tester.widget<AppCard>(rowOf(sunday));
      expect(card.color, schemeOf(tester).tertiaryContainer);
      await finish(tester);
    });

    testWidgets('минулий вихідний має свій відтінок', (tester) async {
      final today = dateOnly(DateTime.now());
      final saturday = addDays(mondayOf(today), 5);
      if (!saturday.isBefore(today)) return; // субота ще не минула
      await pumpApp(tester);
      await tester.tap(find.text('Тиждень'));
      await tester.pump();

      final scheme = schemeOf(tester);
      final card = tester.widget<AppCard>(rowOf(saturday));
      expect(
        card.color,
        Color.alphaBlend(scheme.error.withAlpha(40), scheme.surfaceContainer),
      );
      await finish(tester);
    });

    testWidgets('є підказка з кольорами', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Тиждень'));
      await tester.pump();
      expect(find.text('Сьогодні'), findsOneWidget);
      expect(find.text('Відпрацьовано'), findsOneWidget);
      expect(find.text('У плані'), findsOneWidget);
      expect(find.text('Минулий вихідний'), findsOneWidget);
      await finish(tester);
    });
  });

  group('Налаштування', () {
    testWidgets('перемикач «Показувати залишок» ховає «пігулки»', (tester) async {
      final state = await pumpApp(tester);
      expect(find.textContaining('Тиждень: ще'), findsOneWidget);

      await tester.tap(find.byTooltip('Налаштування'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(state.showRemaining, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Тиждень: ще'), findsNothing);
      await finish(tester);
    });

    testWidgets('тема «Темна» застосовується одразу', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(find.byTooltip('Налаштування'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Темна'));
      await tester.pumpAndSettle();

      expect(state.themeMode, ThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await finish(tester);
    });

    testWidgets('стандартна тривалість змінюється колесами', (tester) async {
      final state = await pumpApp(tester);
      await tester.tap(find.byTooltip('Налаштування'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('default-shift-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '8 год'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Зберегти'));
      await tester.pumpAndSettle();

      expect(state.defaultShiftMinutes, 480);
      expect(find.text('8 год'), findsOneWidget);
      await finish(tester);
    });
  });

  group('Дизайн і теми', () {
    testWidgets('темна тема: графітовий фон і помаранчевий акцент', (tester) async {
      await pumpApp(
        tester,
        initial: {kSettingsKey: jsonEncode({'theme': 'dark'})},
      );
      final theme = Theme.of(tester.element(find.byType(AppShell)));
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.surface, const Color(0xFF0D0D0F));
      expect(theme.colorScheme.primary, const Color(0xFFFF6B2C));
      await finish(tester);
    });

    testWidgets('світла тема: світло-сірий фон і той самий акцент', (tester) async {
      await pumpApp(
        tester,
        initial: {kSettingsKey: jsonEncode({'theme': 'light'})},
      );
      final theme = Theme.of(tester.element(find.byType(AppShell)));
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.surface, const Color(0xFFF3F3F5));
      await finish(tester);
    });

    testWidgets('усі вигляди малюються без помилок у темній темі', (tester) async {
      await pumpApp(
        tester,
        initial: {kSettingsKey: jsonEncode({'theme': 'dark'})},
      );
      for (final label in ['Тиждень', 'День', 'Місяць']) {
        await tester.tap(find.text(label));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: label);
      }
      await openPlanningTab(tester);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  });

  group('Вкладка «Планування»', () {
    testWidgets('показує прогноз і не дає міняти минулі дні', (tester) async {
      final state = await pumpApp(tester);
      await openPlanningTab(tester);

      expect(find.textContaining('Прогноз:'), findsOneWidget);

      await tester.tap(dayCell(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Минулі дні'), findsOneWidget);
      expect(find.text('Додати в план'), findsNothing);
      expect(state.plan, isEmpty);
      await finish(tester);
    });

    testWidgets('чернетка наступного місяця не чіпає справжні виходи', (tester) async {
      final state = await pumpApp(tester);
      await openPlanningTab(tester);

      await tester.tap(find.byTooltip('Наступний місяць'));
      await tester.pump();
      await tester.tap(dayCell(10));
      await tester.pumpAndSettle();
      expect(find.text('Додати в план'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, '10 год'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Додати в план'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.plan, {nextMonthKeyOf(10): 600});
      expect(state.shifts, isEmpty);
      expect(find.text('У плані: 1 дн. по 10 год'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('«Скасувати» у плані повертає чернетку', (tester) async {
      final state = await pumpApp(tester);
      await openPlanningTab(tester);
      await tester.tap(find.byTooltip('Наступний місяць'));
      await tester.pump();
      await tester.tap(dayCell(10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Додати в план'));
      await tester.pumpAndSettle();
      expect(state.plan.length, 1);

      await tester.tap(find.text('Скасувати'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.plan, isEmpty);
      await finish(tester);
    });

    testWidgets('очищення чернетки: підтвердження і скасування', (tester) async {
      final state = await pumpApp(
        tester,
        initial: {kPlanKey: jsonEncode({nextMonthKeyOf(10): 720})},
      );
      await openPlanningTab(tester);
      await tester.tap(find.byTooltip('Наступний місяць'));
      await tester.pump();

      await tester.tap(find.byTooltip('Очистити чернетку місяця'));
      await tester.pumpAndSettle();
      expect(find.text('Очистити чернетку?'), findsOneWidget);

      await tester.tap(find.text('Очистити'));
      // Діалог ще закривається — чекаємо, щоб його «Скасувати» зник.
      await tester.pumpAndSettle();
      expect(state.plan, isEmpty);
      expect(find.text('Чернетку очищено'), findsOneWidget);

      await tester.tap(find.text('Скасувати'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.plan.length, 1);
      await finish(tester);
    });

    testWidgets('прогноз: чернетка наступного місяця рахується проти його норми', (tester) async {
      await pumpApp(
        tester,
        initial: {kPlanKey: jsonEncode({nextMonthKeyOf(10): 720})},
      );
      await openPlanningTab(tester);
      await tester.tap(find.byTooltip('Наступний місяць'));
      await tester.pump();

      final now = DateTime.now();
      final next = DateTime(now.year, now.month + 1, 1);
      final norm = monthNormMinutes(next.year, next.month);
      expect(find.text('12 год з ${fmtHours(norm)}'), findsOneWidget);
      await finish(tester);
    });
  });
}
