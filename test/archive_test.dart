// Тести архіву звітів і вкладки «Звіти».
// Запуск: flutter test test/archive_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/export/month_report_page.dart';
import 'package:work_calendar/export/report_archive.dart';
import 'package:work_calendar/export/reports_page.dart';
import 'package:work_calendar/services.dart';

Uint8List pdfBytes(int n) => Uint8List.fromList(List<int>.generate(n, (i) => i % 200));

Future<AppState> makeState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await SharedPreferences.getInstance());
}

void main() {
  group('Архів у файлах', () {
    test('зберігає, читає, переживає перезапуск і видаляє', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('wc_archive_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final archive = FileReportArchive(prefs, Directory('${dir.path}/reports'));
      expect(archive.items, isEmpty);

      final a = await archive.add(
        year: 2026,
        month: 9,
        employee: 'Марія',
        createdAt: DateTime(2026, 10, 1, 9, 5),
        onlyShiftDays: false,
        pdf: pdfBytes(300),
      );
      final b = await archive.add(
        year: 2026,
        month: 10,
        employee: 'Марія',
        createdAt: DateTime(2026, 10, 25, 16, 12),
        onlyShiftDays: true,
        pdf: pdfBytes(500),
      );
      expect(archive.items.map((e) => e.id).toList(), [b.id, a.id]); // найновіші першими
      expect(b.sizeBytes, 500);
      expect((await archive.read(a.id))!.length, 300);

      // «Перезапуск»: новий об'єкт бачить ті самі звіти.
      final again = FileReportArchive(prefs, Directory('${dir.path}/reports'));
      expect(again.items.length, 2);
      expect(again.items.first.month, 10);
      expect(again.items.first.onlyShiftDays, isTrue);
      expect(again.items.first.createdAt, DateTime(2026, 10, 25, 16, 12));

      await again.remove(a.id);
      expect(again.items.length, 1);
      expect(await again.read(a.id), isNull);
      expect(FileReportArchive(prefs, Directory('${dir.path}/reports')).items.length, 1);
    });

    test('два звіти в одну мить не затирають один одного', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('wc_archive_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final archive = FileReportArchive(prefs, dir);
      final t = DateTime(2026, 10, 25, 16, 12);
      final a = await archive.add(year: 2026, month: 10, employee: '', createdAt: t, onlyShiftDays: false, pdf: pdfBytes(10));
      final b = await archive.add(year: 2026, month: 10, employee: '', createdAt: t, onlyShiftDays: false, pdf: pdfBytes(20));
      expect(a.id == b.id, isFalse);
      expect((await archive.read(a.id))!.length, 10);
      expect((await archive.read(b.id))!.length, 20);
    });

    test('пошкоджений список не ламає додаток', () async {
      SharedPreferences.setMockInitialValues({FileReportArchive.storeKey: '{не json'});
      final prefs = await SharedPreferences.getInstance();
      final archive = FileReportArchive(prefs, Directory.systemTemp);
      expect(archive.items, isEmpty);
    });

    test('розмір читабельно', () {
      expect(fmtSize(500), '500 Б');
      expect(fmtSize(54 * 1024), '54 КБ');
      expect(fmtSize(1536 * 1024), '1.5 МБ');
    });
  });

  group('Вкладка «Звіти»', () {
    Future<void> pump(WidgetTester tester, AppState state, AppServices services) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(home: ReportsPage(state: state)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('порожній архів і недоступний архів пояснені словами', (tester) async {
      final state = await makeState();
      await pump(tester, state, AppServices(archive: MemoryReportArchive()));
      expect(find.byKey(const Key('archive-empty')), findsOneWidget);

      await pump(tester, state, AppServices());
      expect(find.byKey(const Key('archive-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('reports-current')), findsOneWidget);
    });

    testWidgets('збережені звіти видно з датою формування; їх можна видалити', (tester) async {
      final state = await makeState();
      final archive = MemoryReportArchive();
      final item = await archive.add(
        year: 2026,
        month: 10,
        employee: 'Степанова Марія',
        createdAt: DateTime(2026, 10, 25, 16, 12),
        onlyShiftDays: false,
        pdf: pdfBytes(2048),
      );
      await pump(tester, state, AppServices(archive: archive));

      expect(find.text('Жовтень 2026'), findsOneWidget);
      expect(find.textContaining('Сформовано 25.10.2026 о 16:12'), findsOneWidget);
      expect(find.textContaining('Степанова Марія · 2 КБ'), findsOneWidget);

      await tester.tap(find.byKey(Key('archive-delete-${item.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Видалити звіт?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('archive-delete-confirm')));
      await tester.pumpAndSettle();
      expect(archive.items, isEmpty);
      expect(find.byKey(const Key('archive-empty')), findsOneWidget);
    });

    testWidgets('«Скасувати» у вікні видалення нічого не видаляє', (tester) async {
      final state = await makeState();
      final archive = MemoryReportArchive();
      final item = await archive.add(
        year: 2026,
        month: 9,
        employee: '',
        createdAt: DateTime(2026, 10, 1, 8, 0),
        onlyShiftDays: false,
        pdf: pdfBytes(100),
      );
      await pump(tester, state, AppServices(archive: archive));
      expect(find.textContaining('без імені'), findsOneWidget);
      await tester.tap(find.byKey(Key('archive-delete-${item.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Скасувати'));
      await tester.pumpAndSettle();
      expect(archive.items.length, 1);
    });

    testWidgets('збережений звіт відкривається й ним можна поділитись', (tester) async {
      final state = await makeState();
      final archive = MemoryReportArchive();
      final item = await archive.add(
        year: 2026,
        month: 10,
        employee: 'Марія',
        createdAt: DateTime(2026, 10, 25, 16, 12),
        onlyShiftDays: false,
        pdf: pdfBytes(64),
      );
      Uint8List? shared;
      String? sharedName;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ArchivedReportPage(
            archive: archive,
            item: item,
            previewBuilder: (context, pdf, name) => Text('перегляд $name ${pdf.length}'),
            onShare: (pdf, name) async {
              shared = pdf;
              sharedName = name;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('перегляд Zvit_2026-10.pdf 64'), findsOneWidget);
      expect(find.textContaining('Сформовано 25.10.2026 о 16:12'), findsOneWidget);
      await tester.tap(find.byKey(const Key('archived-share')));
      await tester.pumpAndSettle();
      expect(sharedName, 'Zvit_2026-10.pdf');
      expect(shared!.length, 64);
    });

    testWidgets('якщо файл зник, показується пояснення', (tester) async {
      final archive = MemoryReportArchive();
      final item = ArchivedReport(
        id: 'nope',
        year: 2026,
        month: 10,
        employee: '',
        createdAt: DateTime(2026, 10, 25),
        sizeBytes: 1,
        onlyShiftDays: false,
      );
      await tester.pumpWidget(MaterialApp(home: ArchivedReportPage(archive: archive, item: item)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('archived-missing')), findsOneWidget);
    });
  });

  group('Збереження з екрана звіту', () {
    testWidgets('кнопка «В архів» додає звіт з місяцем, іменем і часом формування', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final state = await makeState();
      final archive = MemoryReportArchive();
      await tester.pumpWidget(
        MaterialApp(
          home: MonthReportPage(
            state: state,
            initialMonth: DateTime(2026, 10, 1),
            suggestedName: 'Марія Степанова',
            archive: archive,
            clock: () => DateTime(2026, 10, 25, 16, 12),
            pdfBuilder: (r, e, g, o) async => pdfBytes(120),
            previewBuilder: (c, p, n) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('report-archive')));
      await tester.pumpAndSettle();
      expect(archive.items.length, 1);
      final saved = archive.items.single;
      expect(saved.year, 2026);
      expect(saved.month, 10);
      expect(saved.employee, 'Марія Степанова');
      expect(saved.createdAt, DateTime(2026, 10, 25, 16, 12));
      expect(saved.sizeBytes, 120);
      expect(find.textContaining('збережено в архіві'), findsOneWidget);
    });

    testWidgets('без архіву кнопки «В архів» немає', (tester) async {
      final state = await makeState();
      await tester.pumpWidget(
        MaterialApp(
          home: MonthReportPage(
            state: state,
            initialMonth: DateTime(2026, 10, 1),
            clock: () => DateTime(2026, 10, 25),
            pdfBuilder: (r, e, g, o) async => pdfBytes(10),
            previewBuilder: (c, p, n) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-archive')), findsNothing);
    });
  });
}
