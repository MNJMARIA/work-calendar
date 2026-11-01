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
import 'package:work_calendar/logic.dart';

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

  group('День, тиждень, місяць', () {
    test('тиждень: пн–нд, норма, відпрацьоване', () {
      // 25.10.2026 — неділя; тиждень 19–25 жовтня.
      final r = MonthReport.forKind(ReportKind.week, DateTime(2026, 10, 22),
          shifts: shifts, today: DateTime(2026, 10, 25));
      expect(r.kind, ReportKind.week);
      expect(r.firstDay, DateTime(2026, 10, 19));
      expect(r.lastDay, DateTime(2026, 10, 25));
      expect(r.days.length, 7);
      expect(r.normWorkdays, 5);
      expect(r.normMinutes, 5 * 480);
      expect(r.workedMinutes, 0); // у цьому тижні виходів немає
      final w1 = MonthReport.forKind(ReportKind.week, DateTime(2026, 10, 1),
          shifts: shifts, today: DateTime(2026, 10, 25));
      expect(w1.firstDay, DateTime(2026, 9, 28)); // тиждень починається у вересні
      expect(w1.lastDay, DateTime(2026, 10, 4));
      expect(w1.workedMinutes, 1800);
      expect(w1.workedShifts, 3);
      expect(w1.finished, isTrue);
    });

    test('день: з виходом, без виходу, у майбутньому', () {
      final worked = MonthReport.forKind(ReportKind.day, DateTime(2026, 10, 2),
          shifts: shifts, today: DateTime(2026, 10, 25));
      expect(worked.days.length, 1);
      expect(worked.normMinutes, 480); // п'ятниця
      expect(worked.workedMinutes, 720);
      expect(worked.diffMinutes, 720 - 480);

      final weekend = MonthReport.forKind(ReportKind.day, DateTime(2026, 10, 4),
          shifts: shifts, today: DateTime(2026, 10, 25));
      expect(weekend.normMinutes, 0);
      expect(weekend.workedMinutes, 0);

      final planned = MonthReport.forKind(ReportKind.day, DateTime(2026, 10, 28),
          shifts: shifts, today: DateTime(2026, 10, 25));
      expect(planned.workedMinutes, 0);
      expect(planned.plannedMinutes, 600);
      expect(planned.finished, isFalse);
    });

    test('місяць через forKind збігається зі звичайним звітом', () {
      final a = MonthReport(year: 2026, month: 10, shifts: shifts, today: DateTime(2026, 10, 25));
      final b = MonthReport.forKind(ReportKind.month, DateTime(2026, 10, 17),
          shifts: shifts, today: DateTime(2026, 10, 25));
      expect(b.normMinutes, a.normMinutes);
      expect(b.workedMinutes, a.workedMinutes);
      expect(b.days.length, a.days.length);
      expect(b.normMinutes, monthNormMinutes(2026, 10));
    });

    test('назви файлів, заголовки, відмінювання', () {
      final d = DateTime(2026, 10, 25);
      expect(reportFileNameFor(ReportKind.month, DateTime(2026, 10, 1), DateTime(2026, 10, 31)), 'Zvit_2026-10.pdf');
      expect(reportFileNameFor(ReportKind.week, DateTime(2026, 10, 19), d), 'Zvit_2026-10-19_2026-10-25.pdf');
      expect(reportFileNameFor(ReportKind.day, d, d), 'Zvit_2026-10-25.pdf');
      expect(reportPeriodTitle(ReportKind.week, DateTime(2026, 10, 19), d), '19.10.2026 – 25.10.2026');
      expect(reportPeriodTitle(ReportKind.day, d, d), '25.10.2026');
      expect(workdaysLabel(1), '1 робочий день');
      expect(workdaysLabel(3), '3 робочі дні');
      expect(workdaysLabel(5), '5 робочих днів');
      expect(workdaysLabel(11), '11 робочих днів');
      expect(workdaysLabel(21), '21 робочий день');
      expect(workdaysLabel(22), '22 робочі дні');
    });

    test('PDF збирається для дня, тижня і місяця (також у збільшеному тексті)', () async {
      for (final kind in ReportKind.values) {
        for (final scale in [1.0, 1.5]) {
          final r = MonthReport.forKind(kind, DateTime(2026, 10, 2),
              shifts: shifts, today: DateTime(2026, 10, 25));
          final bytes = await buildMonthReportPdf(
            r,
            employee: 'Степанова Марія',
            generatedAt: DateTime(2026, 10, 25),
            regularFont: font('LiberationSerif-Regular.ttf'),
            boldFont: font('LiberationSerif-Bold.ttf'),
            textScale: scale,
          );
          expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-', reason: '$kind × $scale');
        }
      }
    });
  });

  group('Вибір періоду на екрані', () {
    testWidgets('День / Тиждень / Місяць: заголовок, стрілки, звіт перебудовується', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      final built = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MonthReportPage(
            state: state,
            initialMonth: DateTime(2026, 10, 25),
            clock: () => DateTime(2026, 10, 25),
            pdfBuilder: (r, e, g, o, sc) async {
              built.add('${r.kind.name}|${fmtDate(r.firstDay)}|${fmtDate(r.lastDay)}');
              return Uint8List.fromList([37, 80, 68, 70, 45]);
            },
            previewBuilder: (c, p, n) => Text('файл $n'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Жовтень 2026'), findsOneWidget);
      expect(built.last, 'month|01.10.2026|31.10.2026');

      await tester.tap(find.byKey(const Key('report-kind-week')));
      await tester.pumpAndSettle();
      expect(find.text('19.10.2026 – 25.10.2026'), findsOneWidget);
      expect(built.last, 'week|19.10.2026|25.10.2026');
      expect(find.text('файл Zvit_2026-10-19_2026-10-25.pdf'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-prev')));
      await tester.pumpAndSettle();
      expect(find.text('12.10.2026 – 18.10.2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-kind-day')));
      await tester.pumpAndSettle();
      expect(find.text('18.10.2026'), findsOneWidget);
      expect(built.last, 'day|18.10.2026|18.10.2026');
      // Для одного дня перемикач «лише дні з виходами» не потрібен.
      expect(find.byKey(const Key('report-only-shifts')), findsNothing);

      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      expect(find.text('19.10.2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-kind-month')));
      await tester.pumpAndSettle();
      expect(find.text('Жовтень 2026'), findsOneWidget);
      expect(find.byKey(const Key('report-only-shifts')), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      expect(find.text('Листопад 2026'), findsOneWidget);
    });

    testWidgets('початковий вигляд «день» відкривається одразу', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          home: MonthReportPage(
            state: state,
            initialMonth: DateTime(2026, 10, 25),
            initialKind: ReportKind.day,
            clock: () => DateTime(2026, 10, 25),
            pdfBuilder: (r, e, g, o, sc) async => Uint8List.fromList([37, 80, 68, 70, 45]),
            previewBuilder: (c, p, n) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('25.10.2026'), findsOneWidget);
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
