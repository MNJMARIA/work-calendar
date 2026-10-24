// Тести оновлень і звітів про проблеми.
// Запуск: flutter test test/update_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/reports/report_service.dart';
import 'package:work_calendar/updates/update_logic.dart';
import 'package:work_calendar/updates/update_service.dart';

import 'fakes.dart';

void main() {
  group('Розбір релізу GitHub', () {
    test('звичайний реліз розбирається повністю', () {
      final info = parseRelease(releaseJson())!;
      expect(info.build, 12);
      expect(info.versionName, '0.5.0');
      expect(info.notes, 'Додано таймер');
      expect(info.apkUrl, endsWith('/b12/work-calendar.apk'));
      expect(info.pageUrl, contains('/releases/tag/b12'));
      expect(
        info.sha256,
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
      );
    });

    test('без контрольної суми — sha256 порожній', () {
      expect(parseRelease(releaseJson(sha: null))!.sha256, isNull);
    });

    test('рядок із контрольною сумою не потрапляє в опис змін', () {
      final info = parseRelease(releaseJson(notes: 'Перший рядок\nДругий рядок'))!;
      expect(info.notes, 'Перший рядок\nДругий рядок');
    });

    test('чужий тег ігнорується', () {
      final json = releaseJson()..['tag_name'] = 'v1.0.0';
      expect(parseRelease(json), isNull);
    });

    test('реліз без APK ігнорується', () {
      final json = releaseJson()..['assets'] = <dynamic>[];
      expect(parseRelease(json), isNull);
    });

    test('без назви версією стає тег', () {
      final json = releaseJson()..['name'] = '';
      expect(parseRelease(json)!.versionName, 'b12');
    });

    test('порожня відповідь не ламає розбір', () {
      expect(parseRelease(<String, dynamic>{}), isNull);
    });
  });

  group('Порівняння версій', () {
    test('isNewerBuild', () {
      expect(isNewerBuild(current: 10, latest: 11), isTrue);
      expect(isNewerBuild(current: 11, latest: 11), isFalse);
      expect(isNewerBuild(current: 12, latest: 11), isFalse);
    });

    test('номер збірки з версії pubspec', () {
      expect(buildNumberFromVersion('0.5.0+15'), 15);
      expect(buildNumberFromVersion('0.5.0'), isNull);
      expect(buildNumberFromVersion('0.5.0+abc'), isNull);
    });
  });

  group('UpdateService', () {
    UpdateService make({
      int build = 10,
      Future<Map<String, dynamic>?> Function()? fetcher,
      FakeInstaller? installer,
    }) {
      return UpdateService(
        currentBuild: build,
        currentVersion: '0.4.0',
        fetcher: fetcher ?? () async => releaseJson(build: 12),
        installer: installer ?? FakeInstaller(const []),
      );
    }

    test('знаходить нову версію', () async {
      final s = make();
      await s.check();
      expect(s.status, UpdateStatus.available);
      expect(s.available!.build, 12);
    });

    test('та сама версія — «остання»', () async {
      final s = make(build: 12);
      await s.check();
      expect(s.status, UpdateStatus.upToDate);
      expect(s.available, isNull);
      expect(s.latest, isNotNull);
    });

    test('новіша встановлена версія — оновлення немає', () async {
      final s = make(build: 20);
      await s.check();
      expect(s.available, isNull);
    });

    test('без інтернету тихо нічого не показує', () async {
      final s = make(fetcher: () async => null);
      await s.check();
      expect(s.status, UpdateStatus.idle);
      expect(s.available, isNull);
    });

    test('помилка запиту не ламає додаток', () async {
      final s = make(fetcher: () async => throw Exception('boom'));
      await s.check();
      expect(s.status, UpdateStatus.idle);
    });

    test('не наш реліз — оновлення немає', () async {
      final s = make(fetcher: () async => {'tag_name': 'v9'});
      await s.check();
      expect(s.available, isNull);
    });

    test('слухачі отримують сповіщення про перевірку', () async {
      final s = make();
      var count = 0;
      s.addListener(() => count++);
      await s.check();
      expect(count, greaterThanOrEqualTo(2)); // «перевіряю» і результат
    });

    test('встановлення: прогрес, потім вікно системи', () async {
      final installer = FakeInstaller(const [
        InstallProgress(InstallPhase.downloading, percent: 30),
        InstallProgress(InstallPhase.downloading, percent: 80),
        InstallProgress(InstallPhase.installing),
      ]);
      final s = make(installer: installer);
      await s.check();
      await s.install();
      expect(s.status, UpdateStatus.installing);
      expect(s.percent, 80);
      expect(installer.lastUrl, endsWith('work-calendar.apk'));
      expect(installer.lastSha, isNotNull);
    });

    test('помилка встановлення показується і скидається', () async {
      final installer = FakeInstaller(const [
        InstallProgress(InstallPhase.downloading, percent: 10),
        InstallProgress(InstallPhase.error, error: 'Не вдалося завантажити'),
      ]);
      final s = make(installer: installer);
      await s.check();
      await s.install();
      expect(s.status, UpdateStatus.error);
      expect(s.error, 'Не вдалося завантажити');
      s.clearError();
      expect(s.status, UpdateStatus.available);
      expect(s.error, isNull);
    });

    test('без нової версії встановлювати нічого', () async {
      final installer = FakeInstaller(const [InstallProgress(InstallPhase.installing)]);
      final s = make(build: 12, installer: installer);
      await s.check();
      await s.install();
      expect(installer.lastUrl, isNull);
      expect(s.status, UpdateStatus.upToDate);
    });

    test('потік без подій вважається початком встановлення', () async {
      final s = make(installer: FakeInstaller(const []));
      await s.check();
      await s.install();
      expect(s.status, UpdateStatus.installing);
    });
  });

  group('«Додаток оновлено»', () {
    Future<SharedPreferences> prefs() async {
      SharedPreferences.setMockInitialValues({});
      return SharedPreferences.getInstance();
    }

    test('перший запуск після встановлення — без вікна', () async {
      final p = await prefs();
      expect(detectJustUpdated(p, 5), isNull);
    });

    test('повторний запуск тієї ж збірки — без вікна', () async {
      final p = await prefs();
      detectJustUpdated(p, 5);
      expect(detectJustUpdated(p, 5), isNull);
    });

    test('нова збірка → повертає попередню, і лише один раз', () async {
      final p = await prefs();
      detectJustUpdated(p, 5);
      expect(detectJustUpdated(p, 7), 5);
      expect(detectJustUpdated(p, 7), isNull);
    });

    test('повернення на старішу збірку не вважається оновленням', () async {
      final p = await prefs();
      detectJustUpdated(p, 7);
      expect(detectJustUpdated(p, 5), isNull);
    });
  });

  group('Звіти про проблеми', () {
    Map<String, dynamic> build({
      ReportDraft? draft,
      List<String> log = const [],
    }) {
      return buildReportPayload(
        draft: draft ?? const ReportDraft(category: 'bug', text: 'Не працює таймер'),
        appVersion: '0.5.0 (12)',
        device: 'OPPO CPH2000, Android 14 (SDK 34)',
        email: 'olena@example.com',
        uid: 'uid-1',
        logLines: log,
        nowMillis: 1000,
      );
    }

    test('містить усі потрібні поля', () {
      final p = build(log: ['10:00:00 start']);
      expect(p['category'], 'bug');
      expect(p['text'], 'Не працює таймер');
      expect(p['appVersion'], '0.5.0 (12)');
      expect(p['device'], contains('OPPO'));
      expect(p['email'], 'olena@example.com');
      expect(p['uid'], 'uid-1');
      expect(p['log'], '10:00:00 start');
      expect(p['createdAt'], 1000);
    });

    test('довгий текст обрізається', () {
      final p = build(draft: ReportDraft(category: 'bug', text: 'а' * 3000));
      expect((p['text'] as String).length, kReportMaxText);
    });

    test('текст обрізається по краях пробілів', () {
      final p = build(draft: const ReportDraft(category: 'bug', text: '  привіт  '));
      expect(p['text'], 'привіт');
    });

    test('журнал обмежено, а зберігається його кінець', () {
      final lines = [for (var i = 0; i < 100; i++) 'рядок-$i-${'x' * 300}'];
      final p = build(log: lines);
      final log = p['log'] as String;
      expect(log.length, lessThanOrEqualTo(kReportMaxLog));
      // Кожен рядок обрізано до 200 символів.
      expect(log.split('\n').every((l) => l.length <= 200), isTrue);
    });

    test('без журналу — порожній рядок', () {
      final p = build(
        draft: const ReportDraft(category: 'bug', text: 'Текст', attachLog: false),
        log: ['щось'],
      );
      expect(p['log'], '');
    });

    test('невідома категорія стає «інше»', () {
      final p = build(draft: const ReportDraft(category: 'hack', text: 'Текст'));
      expect(p['category'], 'other');
    });

    test('без хмари звіт надіслати не можна', () {
      expect(
            () => OfflineReportService().send(const ReportDraft(category: 'bug', text: 'Текст')),
        throwsStateError,
      );
    });
  });
}
