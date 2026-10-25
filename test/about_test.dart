// Тести екрана «Налаштування»: «Про додаток» (розробниця) і повідомлення,
// коли хмара не запустилась. Запуск: flutter test test/about_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/services.dart';
import 'package:work_calendar/settings_page.dart';

Future<void> pumpSettings(WidgetTester tester, AppServices services) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppServicesScope(
      services: services,
      child: MaterialApp(home: SettingsPage(state: AppState(prefs))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Про додаток показує назву, версію й розробницю', (tester) async {
    await pumpSettings(tester, AppServices(currentVersion: '0.5.0 (12)'));

    final tile = find.byKey(const Key('about-tile'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(find.text('0.5.0 (12)'), findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('Робочий календар'), findsWidgets);
    expect(find.textContaining('Mariia Stepanova'), findsOneWidget);
  });

  testWidgets('Без хмари й без помилки блок помилки не показується', (tester) async {
    await pumpSettings(tester, AppServices());
    expect(find.byKey(const Key('cloud-error')), findsNothing);
  });

  testWidgets('Якщо хмара не запустилась, у налаштуваннях видно причину', (tester) async {
    await pumpSettings(tester, AppServices(cloudError: 'Firebase не знайдено: тест'));

    expect(find.byKey(const Key('cloud-error')), findsOneWidget);
    expect(find.textContaining('Firebase не знайдено: тест'), findsOneWidget);
    expect(find.text('Хмара не підключилась'), findsOneWidget);
  });
}
