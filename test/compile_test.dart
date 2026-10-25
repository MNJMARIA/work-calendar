// Перевірка, що файли, які тести зазвичай не підключають (Firebase, оновлення),
// принаймні компілюються. Без цього помилку в них видно лише при запуску на
// телефоні або при збірці APK. Запуск: flutter test test/compile_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/export/month_report_page.dart';
import 'package:work_calendar/firebase_services.dart';
import 'package:work_calendar/main.dart' as app;
import 'package:work_calendar/updates/github_fetcher.dart';
import 'package:work_calendar/updates/ota_installer.dart';

void main() {
  test('Файли Firebase і оновлень компілюються', () {
    expect(createCloudServices, isNotNull);
    expect(app.main, isNotNull);
    expect(githubLatestRelease, isNotNull);
    expect(OtaApkInstaller(), isNotNull);
    expect(FirebaseCrashControl, isNotNull);
    expect(MonthReportPage, isNotNull);
  });
}
