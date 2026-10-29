// Тести місячного звіту: розрахунки, PDF-файл і екран.
// Запуск: flutter test test/month_report_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/export/month_report.dart';
import 'package:work_calendar/export/month_report_page.dart';

Uint8List font(String name) => File('assets/fonts/$name').readAsBytesSync();

void main() {
  // Жовтень 2026: 22 робочі дні = 176 год. 1 жовтня — четвер.
  final shifts = <String, int>{
    '2026-10-01': 720, // чт
    '2026-10-02': 720, // пт
    '2026-10-03': 360, // сб
    '2026-10-28': 600, // середа, у майбутньому
  };

  group('Розрахунки', () {
    test('місяць ще триває: підсумки, тижні, план', () {
      final r = MonthReport(year: 2026, month: 10, shifts: shifts, today: DateTime(2026, 10, 25));
      expect(r.normMinutes, 176 * 60);
      expect(r.normWorkdays, 22);
      expect(r.workedMinutes, 1800);
      expect(r.workedShifts, 3);
      expect(r.plannedMinutes, 600);
      expect(r.plannedShifts, 1);
      expect(r.longestMinutes, 720);
      expect(r.averageMinutes, 600);
      expect(r.finished, isFalse);
      expect(r.days.length, 31);

      expect(r.weeks.length, 5);
      expect(r.weeks.first.from, DateTime(2026, 10, 1));
      expect(r.weeks.first.to, DateTime(2026, 10, 4));
      expect(r.weeks.first.shifts, 3);
      expect(r.weeks.first.minutes, 1800);
      expect(r.weeks.first.normMinutes, 2 * 480); // чт і пт
      expect(r.weeks.last.from, DateTime(2026, 10, 26));
      expect(r.weeks.last.to, DateTime(2026, 10, 31));
      expect(r.weeks.last.normMinutes, 5 * 480);
      expect(r.weeks.last.minutes, 0); // вихід 28-го ще попереду
      // Тижні разом дають ту саму норму, що й місяць.
      expect(r.weeks.fold<int>(0, (a, w) => a + w.normMinutes), r.normMinutes);
    });

    test('місяць закінчився: усе, що було в календарі, враховано', () {
      final r = MonthReport(year: 2026, month: 10, shifts: shifts, today: DateTime(2026, 11, 5));
      expect(r.finished, isTrue);
      expect(r.workedMinutes, 2400);
      expect(r.plannedShifts, 0);
      expect(r.diffMinutes, 2400 - 176 * 60);
    });

    test('порожній місяць', () {
      final r = MonthReport(year: 2026, month: 2, shifts: const {}, today: DateTime(2026, 3, 1));
      expect(r.workedMinutes, 0);
      expect(r.averageMinutes, 0);
      expect(r.days.length, 28);
    });

    test('текст: дати, різниця, назва файлу', () {
      expect(fmtDate(DateTime(2026, 3, 5)), '05.03.2026');
      expect(fmtSigned(0), '0 год');
      expect(fmtSigned(90), '+1 год 30 хв');
      expect(fmtSigned(-480), '−8 год');
      expect(reportFileName(2026, 3), 'Zvit_2026-03.pdf');
    });
  });

  group('PDF', () {
    test('звіт збирається і є справжнім PDF-файлом', () async {
      final r = MonthReport(year: 2026, month: 10, shifts: shifts, today: DateTime(2026, 10, 25));
      final bytes = await buildMonthReportPdf(
        r,
        employee: 'Степанова Марія',
        generatedAt: DateTime(2026, 10, 25),
        regularFont: font('LiberationSerif-Regular.ttf'),
        boldFont: font('LiberationSerif-Bold.ttf'),
      );
      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('збільшений текст: PDF збирається при кожному розмірі', () async {
      final r = MonthReport(year: 2026, month: 10, shifts: shifts, today: DateTime(2026, 10, 25));
      for (final scale in kReportTextScales) {
        final bytes = await buildMonthReportPdf(
          r,
          employee: 'Степанова Марія Олександрівна',
          generatedAt: DateTime(2026, 10, 25),
          regularFont: font('LiberationSerif-Regular.ttf'),
          boldFont: font('LiberationSerif-Bold.ttf'),
          textScale: scale,
        );
        expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-', reason: 'масштаб $scale');
      }
      expect(kReportTextScales.length, kReportTextLabels.length);
    });

    test('варіант «лише дні з виходами» і порожнє ім\'я теж збираються', () async {
      final r = MonthReport(year: 2026, month: 10, shifts: shifts, today: DateTime(2026, 11, 5));
      final bytes = await buildMonthReportPdf(
        r,
        employee: '',
        generatedAt: DateTime(2026, 11, 5),
        regularFont: font('LiberationSerif-Regular.ttf'),
        boldFont: font('LiberationSerif-Bold.ttf'),
        onlyShiftDays: true,
      );
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('місяць без жодного виходу теж збирається', () async {
      final r = MonthReport(year: 2026, month: 2, shifts: const {}, today: DateTime(2026, 3, 1));
      final bytes = await buildMonthReportPdf(
        r,
        employee: 'Тест',
        generatedAt: DateTime(2026, 3, 1),
        regularFont: font('LiberationSerif-Regular.ttf'),
        boldFont: font('LiberationSerif-Bold.ttf'),
        onlyShiftDays: true,
      );
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('Розмір тексту', () {
    testWidgets('вибір розміру перебудовує звіт і запам\'ятовується', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final state = AppState(prefs);
      final scales = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MonthReportPage(
            state: state,
            initialMonth: DateTime(2026, 10, 25),
            clock: () => DateTime(2026, 10, 25),
            pdfBuilder: (r, e, g, o, scale) async {
              scales.add(scale);
              return Uint8List.fromList([37, 80, 68, 70, 45]);
            },
            previewBuilder: (c, p, n) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scales.last, 1.0);

      await tester.tap(find.byKey(const Key('report-text-size-1')));
      await tester.pumpAndSettle();
      expect(scales.last, 1.25);
      expect(state.reportTextSize, 1);

      await tester.tap(find.byKey(const Key('report-text-size-2')));
      await tester.pumpAndSettle();
      expect(scales.last, 1.5);

      // Після «перезапуску» вибір на місці.
      expect(AppState(prefs).reportTextSize, 2);
    });

    test('пошкоджене значення розміру не ламає стан', () async {
      SharedPreferences.setMockInitialValues({
        kSettingsKey: '{"reportTextSize": 99}',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(AppState(prefs).reportTextSize, 2);
    });
  });

  group('Екран', () {
    Future<AppState> makeState() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      return AppState(prefs);
    }

    testWidgets('показує місяць, підставляє ім\'я, перемикає місяці й ділиться', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = await makeState();
      final built = <String>[];
      Uint8List? shared;
      String? sharedName;

      await tester.pumpWidget(
        MaterialApp(
          home: MonthReportPage(
            state: state,
            initialMonth: DateTime(2026, 10, 25),
            suggestedName: 'Марія Степанова',
            clock: () => DateTime(2026, 10, 25),
            pdfBuilder: (report, employee, generatedAt, onlyShiftDays, textScale) async {
              built.add('${report.year}-${report.month}|$employee|$onlyShiftDays');
              return Uint8List.fromList([37, 80, 68, 70, 45, report.month]);
            },
            previewBuilder: (context, pdf, name) => Text('перегляд $name', key: const Key('fake-preview')),
            onShare: (pdf, name) async {
              shared = pdf;
              sharedName = name;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Жовтень 2026'), findsOneWidget);
      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
      expect(find.text('перегляд Zvit_2026-10.pdf'), findsOneWidget);
      expect(built.last, '2026-10|Марія Степанова|false');
      expect(tester.widget<TextField>(find.byKey(const Key('report-name'))).controller!.text, 'Марія Степанова');

      // Попередній місяць.
      await tester.tap(find.byKey(const Key('report-prev')));
      await tester.pumpAndSettle();
      expect(find.text('Вересень 2026'), findsOneWidget);
      expect(built.last.startsWith('2026-9'), isTrue);

      // Лише дні з виходами.
      await tester.tap(find.byKey(const Key('report-only-shifts')));
      await tester.pumpAndSettle();
      expect(built.last, '2026-9|Марія Степанова|true');

      // Поділитися.
      await tester.tap(find.byKey(const Key('report-share')));
      await tester.pumpAndSettle();
      expect(sharedName, 'Zvit_2026-09.pdf');
      expect(shared, isNotNull);
    });

    testWidgets('ім\'я зберігається, і вдруге вже підставляється воно', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = await makeState();
      Widget page() => MaterialApp(
        home: MonthReportPage(
          state: state,
          initialMonth: DateTime(2026, 10, 1),
          suggestedName: 'Запасне ім\'я',
          clock: () => DateTime(2026, 10, 25),
          pdfBuilder: (r, e, g, o, sc) async => Uint8List.fromList([37, 80, 68, 70, 45]),
          previewBuilder: (c, p, n) => const SizedBox(),
        ),
      );

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('report-name')), 'Іваненко Петро');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(state.employeeName, 'Іваненко Петро');

      // Закрили й відкрили знову.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('report-name'))).controller!.text, 'Іваненко Петро');
    });

    testWidgets('помилка складання PDF показується текстом, а не падінням', (tester) async {
      final state = await makeState();
      await tester.pumpWidget(
        MaterialApp(
          home: MonthReportPage(
            state: state,
            initialMonth: DateTime(2026, 10, 1),
            clock: () => DateTime(2026, 10, 25),
            pdfBuilder: (r, e, g, o, sc) async => throw StateError('тестова помилка'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-error')), findsOneWidget);
      expect(find.textContaining('тестова помилка'), findsOneWidget);
    });
  });
}
