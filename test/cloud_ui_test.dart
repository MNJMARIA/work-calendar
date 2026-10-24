// Тести екранів хмари: вхід, реєстрація, ключ відновлення, оновлення, звіти.
// Тести самі «натискають» кнопки. Запуск: flutter test test/cloud_ui_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/account/account_controller.dart';
import 'package:work_calendar/app.dart';
import 'package:work_calendar/crypto/crypto_service.dart';
import 'package:work_calendar/reports/report_service.dart';
import 'package:work_calendar/services.dart';
import 'package:work_calendar/settings_page.dart';
import 'package:work_calendar/updates/update_service.dart';

import 'fakes.dart';

// ── Допоміжні функції ────────────────────────────────────────

void setView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

AppServices servicesFor(
    Phone p, {
      UpdateService? updates,
      FakeReportService? reports,
      FakeCrash? crash,
      String adminUid = '',
      int? justUpdatedFrom,
    }) {
  return AppServices(
    account: p.account,
    sync: p.sync,
    updates: updates,
    reports: reports,
    crash: crash,
    adminUid: adminUid,
    currentVersion: '0.5.0 (10)',
    justUpdatedFrom: justUpdatedFrom,
  );
}

Future<void> pumpCloud(WidgetTester tester, Phone p, AppServices services) async {
  setView(tester);
  await tester.pumpWidget(WorkCalendarApp(state: p.state, services: services));
  await tester.pumpAndSettle();
}

/// Тест екрана з обмеженням у 60 секунд: якщо щось зависне, це видно одразу,
/// а не через 10 хвилин (і одне зависання не «ламає» всі наступні тести).
void cloudTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, body, timeout: const Timeout(Duration(seconds: 60)));
}

/// Закінчує тест: прибирає екран, зупиняє синхронізацію, дає таймерам спрацювати.
/// Екран прибираємо ПЕРШИМ, щоб після зупинки синхронізації нічого не перемальовувалось.
/// Таймерам даємо час дрібними кроками (50 × 100 мс), а не одним стрибком на 5 секунд.
Future<void> endTest(WidgetTester tester, [Phone? p]) async {
  await tester.pumpWidget(const SizedBox());
  await p?.sync.stop();
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typeKey(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

/// «Телефон» зі свіжим акаунтом, який вже пройшов реєстрацію до кінця.
/// Усе відбувається в «уявному часі» тесту, тому паузи роблять через pump.
Future<Phone> readyPhone(WidgetTester tester) async {
  final phone = await Phone.create();
  await phone.account.init();
  await phone.registerAndFinish(settleFn: () => pumpSome(tester));
  return phone;
}

Future<Phone> freshPhone(WidgetTester tester, {Map<String, Object> prefsData = const {}}) async {
  final phone = await Phone.create(prefsData: prefsData);
  await phone.account.init();
  return phone;
}

Future<void> pumpSome(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// Відкрити налаштування й прокрутити до елемента з ключем [key].
Future<void> openSettingsAndScrollTo(WidgetTester tester, String key) async {
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();
  await scrollSettingsTo(tester, key);
}

Future<void> scrollSettingsTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find
        .descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Вхід і реєстрація', () {
    cloudTest('спершу показується привітання з вибором', (tester) async {
      final p = await freshPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      expect(find.byKey(const Key('welcome-signin')), findsOneWidget);
      expect(find.byKey(const Key('welcome-register')), findsOneWidget);
      expect(find.byKey(const Key('welcome-local')), findsOneWidget);
      expect(find.text('Робочий календар'), findsOneWidget);
      await endTest(tester, p);
    });

    cloudTest('«Продовжити без акаунта» відкриває календар', (tester) async {
      final p = await freshPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      await tapKey(tester, 'welcome-local');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(p.account.stage, AccountStage.localOnly);
      await endTest(tester, p);
    });

    cloudTest('режим «без акаунта» пам\'ятається при наступному запуску', (tester) async {
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      await pumpCloud(tester, p, servicesFor(p));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const Key('welcome-signin')), findsNothing);
      await endTest(tester, p);
    });

    cloudTest('перевірка полів реєстрації', (tester) async {
      final p = await freshPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      await tapKey(tester, 'welcome-register');

      await tapKey(tester, 'auth-submit');
      expect(find.text('Введи правильну пошту.'), findsOneWidget);

      await typeKey(tester, 'field-email', 'olena@example.com');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Введи ім\'я.'), findsOneWidget);

      await typeKey(tester, 'field-name', 'Олена');
      await typeKey(tester, 'field-password', 'short');
      await typeKey(tester, 'field-password2', 'short');
      await tapKey(tester, 'auth-submit');
      expect(find.textContaining('щонайменше 8 символів'), findsOneWidget);

      await typeKey(tester, 'field-password', 'password123');
      await typeKey(tester, 'field-password2', 'password124');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Паролі не збігаються.'), findsOneWidget);

      expect(p.auth.currentUser, isNull);
      await endTest(tester, p);
    });

    cloudTest('реєстрація → пошта → ключ → календар', (tester) async {
      final p = await freshPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));

      // 1. Реєстрація.
      await tapKey(tester, 'welcome-register');
      await typeKey(tester, 'field-name', 'Олена');
      await typeKey(tester, 'field-email', 'olena@example.com');
      await typeKey(tester, 'field-password', 'password123');
      await typeKey(tester, 'field-password2', 'password123');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Підтвердь пошту'), findsOneWidget);
      expect(p.auth.verificationsSent, 1);

      // 2. Спершу пошту не підтверджено.
      await tapKey(tester, 'verify-done');
      expect(find.byKey(const Key('auth-error')), findsOneWidget);
      expect(find.text('Підтвердь пошту'), findsOneWidget);

      // 3. Підтвердила пошту → показується ключ відновлення.
      p.auth.markVerified();
      await tapKey(tester, 'verify-done');
      expect(find.byKey(const Key('recovery-key-text')), findsOneWidget);
      final groups = recoveryKeyGroups(p.account.pendingRecoveryText!);
      expect(groups.length, 14);

      // «Далі» неактивна, поки не поставлена галочка.
      await tester.ensureVisible(find.byKey(const Key('recovery-next')));
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('recovery-next'))).onPressed,
        isNull,
      );
      await tapKey(tester, 'recovery-saved');
      await tapKey(tester, 'recovery-next');

      // 4. Підтвердження трьох груп: спершу неправильно.
      for (var i = 0; i < 3; i++) {
        await typeKey(tester, 'confirm-$i', 'AAAA');
      }
      await tapKey(tester, 'recovery-finish');
      expect(find.text('Групи не збігаються. Перевір збережений ключ.'), findsOneWidget);
      expect(p.account.stage, AccountStage.newKey);

      // Тепер правильно: номер групи написаний у підписі поля.
      for (var i = 0; i < 3; i++) {
        final field = tester.widget<TextField>(find.byKey(Key('confirm-$i')));
        final number = int.parse(field.decoration!.labelText!.split(' ').last);
        await typeKey(tester, 'confirm-$i', groups[number - 1].toLowerCase());
      }
      await tapKey(tester, 'recovery-finish');

      // 5. Готово: відкрився календар, ключ у хмарі.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(p.account.stage, AccountStage.ready);
      expect(p.cloud.keyDocs, isNotEmpty);
      await endTest(tester, p);
    });

    cloudTest('кнопка «Скопіювати ключ» кладе ключ у буфер', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
            (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final p = await freshPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      await tapKey(tester, 'welcome-register');
      await typeKey(tester, 'field-name', 'Олена');
      await typeKey(tester, 'field-email', 'olena@example.com');
      await typeKey(tester, 'field-password', 'password123');
      await typeKey(tester, 'field-password2', 'password123');
      await tapKey(tester, 'auth-submit');
      p.auth.markVerified();
      await tapKey(tester, 'verify-done');

      await tapKey(tester, 'recovery-copy');
      expect(copied, p.account.pendingRecoveryText);
      await endTest(tester, p);
    });

    cloudTest('вхід з неправильним паролем показує помилку', (tester) async {
      final p = await freshPhone(tester);
      p.auth.addAccount();
      await pumpCloud(tester, p, servicesFor(p));
      await tapKey(tester, 'welcome-signin');
      await typeKey(tester, 'field-email', 'olena@example.com');
      await typeKey(tester, 'field-password', 'nope');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Неправильна пошта або пароль.'), findsOneWidget);
      await endTest(tester, p);
    });

    cloudTest('«Забув пароль?» надсилає лист', (tester) async {
      final p = await freshPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      await tapKey(tester, 'welcome-signin');

      await tapKey(tester, 'auth-forgot');
      expect(find.textContaining('введи пошту'), findsOneWidget);
      expect(p.auth.resetsSent, 0);

      await typeKey(tester, 'field-email', 'olena@example.com');
      await tapKey(tester, 'auth-forgot');
      expect(p.auth.resetsSent, 1);
      expect(find.text('Лист для відновлення пароля надіслано.'), findsOneWidget);
      await endTest(tester, p);
    });

    cloudTest('новий телефон: ключ відновлення повертає дані', (tester) async {
      // Перший телефон: реєстрація й один вихід у хмарі.
      final phone1 = await Phone.create();
      await phone1.account.init();
      final recovery = await phone1.registerAndFinish(settleFn: () => pumpSome(tester));
      phone1.state.setShifts([DateTime(2026, 10, 20)], 720);
      await phone1.sync.syncNow();
      await phone1.account.signOut();
      await phone1.sync.stop();
      phone1.account.dispose();

      // Другий телефон: той самий акаунт і хмара, але ключа ще немає.
      final p = await Phone.create(auth: phone1.auth, cloud: phone1.cloud);
      await p.account.init();
      await pumpCloud(tester, p, servicesFor(p));

      await tapKey(tester, 'welcome-signin');
      await typeKey(tester, 'field-email', 'olena@example.com');
      await typeKey(tester, 'field-password', 'password123');
      await tapKey(tester, 'auth-submit');
      expect(find.byKey(const Key('field-recovery')), findsOneWidget);

      // Неправильний ключ.
      await typeKey(tester, 'field-recovery', 'ABCD-EFGH');
      await tapKey(tester, 'recovery-submit');
      expect(find.byKey(const Key('auth-error')), findsOneWidget);

      // Правильний ключ.
      await typeKey(tester, 'field-recovery', recovery);
      await tapKey(tester, 'recovery-submit');
      expect(find.byType(NavigationBar), findsOneWidget);
      await pumpSome(tester);
      expect(p.state.shifts['2026-10-20'], 720);
      await endTest(tester, p);
    });
  });

  group('Оновлення', () {
    UpdateService updatesWith({int build = 10, FakeInstaller? installer}) {
      return UpdateService(
        currentBuild: build,
        currentVersion: '0.4.0',
        fetcher: () async => releaseJson(build: 12, version: '0.5.1'),
        installer: installer ??
            FakeInstaller(const [
              InstallProgress(InstallPhase.downloading, percent: 40),
              InstallProgress(InstallPhase.installing),
            ]),
      );
    }

    cloudTest('смужка про нову версію і кнопка «Оновити»', (tester) async {
      final installer = FakeInstaller(const [
        InstallProgress(InstallPhase.downloading, percent: 40),
        InstallProgress(InstallPhase.installing),
      ]);
      final updates = updatesWith(installer: installer);
      await updates.check();
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      await pumpCloud(tester, p, AppServices(updates: updates, currentVersion: '0.4.0 (10)'));

      expect(find.byKey(const Key('update-banner')), findsOneWidget);
      expect(find.text('Доступне оновлення 0.5.1'), findsOneWidget);

      await tapKey(tester, 'update-banner');
      expect(find.byKey(const Key('update-available-title')), findsOneWidget);
      expect(find.textContaining('Додано таймер'), findsOneWidget);

      await tapKey(tester, 'update-install');
      expect(installer.lastUrl, isNotNull);
      expect(find.textContaining('Підтверди встановлення'), findsOneWidget);
      await endTest(tester);
    });

    cloudTest('без нової версії смужки немає', (tester) async {
      final updates = updatesWith(build: 12);
      await updates.check();
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      await pumpCloud(tester, p, AppServices(updates: updates));
      expect(find.byKey(const Key('update-banner')), findsNothing);
      await endTest(tester);
    });

    cloudTest('помилка встановлення видно, є запасний шлях', (tester) async {
      final updates = updatesWith(
        installer: FakeInstaller(const [
          InstallProgress(InstallPhase.error, error: 'Не вдалося завантажити оновлення.'),
        ]),
      );
      await updates.check();
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      String? opened;
      await pumpCloud(
        tester,
        p,
        AppServices(updates: updates, openUrl: (url) async => opened = url),
      );
      await tapKey(tester, 'update-banner');
      await tapKey(tester, 'update-install');
      expect(find.text('Не вдалося завантажити оновлення.'), findsOneWidget);

      await tester.tap(find.text('Відкрити сторінку завантаження'));
      await tester.pump();
      expect(opened, contains('/releases/tag/b12'));
      await endTest(tester);
    });

    cloudTest('натискання на сповіщення відкриває екран оновлення', (tester) async {
      final updates = updatesWith();
      await updates.check();
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      final services = AppServices(updates: updates);
      await pumpCloud(tester, p, services);
      expect(find.byKey(const Key('update-available-title')), findsNothing);

      services.openUpdateSignal.request();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-available-title')), findsOneWidget);
      expect(find.byKey(const Key('update-install')), findsOneWidget);
      await endTest(tester);
    });

    cloudTest('сповіщення, натиснуте ще до запуску екрана, теж працює', (tester) async {
      final updates = updatesWith();
      await updates.check();
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      final services = AppServices(updates: updates)..openUpdateSignal.request();
      await pumpCloud(tester, p, services);
      expect(find.byKey(const Key('update-install')), findsOneWidget);
      await endTest(tester);
    });

    cloudTest('після оновлення показується «Додаток оновлено»', (tester) async {
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      final services = AppServices(currentVersion: '0.5.0 (4)', justUpdatedFrom: 3);
      await pumpCloud(tester, p, services);
      expect(find.text('Додаток оновлено'), findsOneWidget);
      expect(find.textContaining('0.5.0 (4)'), findsOneWidget);

      await tapKey(tester, 'updated-ok');
      expect(find.text('Додаток оновлено'), findsNothing);
      expect(services.justUpdatedFrom, isNull);
      await endTest(tester);
    });

    cloudTest('без оновлення вікна «Додаток оновлено» немає', (tester) async {
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      await pumpCloud(tester, p, AppServices());
      expect(find.text('Додаток оновлено'), findsNothing);
      await endTest(tester);
    });
  });

  group('Налаштування з хмарою', () {
    cloudTest('значок хмари показує стан синхронізації', (tester) async {
      final p = await readyPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      expect(find.byKey(const Key('sync-indicator')), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      await endTest(tester, p);
    });

    cloudTest('акаунт: пошта, синхронізація, ключ, вихід', (tester) async {
      final p = await readyPhone(tester);
      await pumpCloud(tester, p, servicesFor(p, crash: FakeCrash()));
      await openSettingsAndScrollTo(tester, 'sync-now');
      expect(find.text('olena@example.com'), findsOneWidget);
      expect(find.byKey(const Key('sync-now')), findsOneWidget);
      expect(find.byKey(const Key('new-recovery-key')), findsOneWidget);
      await scrollSettingsTo(tester, 'delete-account');
      expect(find.byKey(const Key('delete-account')), findsOneWidget);
      await endTest(tester, p);
    });

    cloudTest('вихід з акаунта повертає на вхід', (tester) async {
      final p = await readyPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      await openSettingsAndScrollTo(tester, 'sign-out');
      await tapKey(tester, 'sign-out');
      await tapKey(tester, 'signout-keep');
      expect(find.byKey(const Key('welcome-signin')), findsOneWidget);
      expect(p.sync.running, isFalse);
      await endTest(tester, p);
    });

    cloudTest('вихід зі стиранням видаляє дані на телефоні', (tester) async {
      final p = await readyPhone(tester);
      p.state.setShifts([DateTime(2026, 10, 20)], 720);
      await pumpCloud(tester, p, servicesFor(p));
      await openSettingsAndScrollTo(tester, 'sign-out');
      await tapKey(tester, 'sign-out');
      await tapKey(tester, 'signout-wipe');
      expect(find.byKey(const Key('welcome-signin')), findsOneWidget);
      expect(p.state.shifts, isEmpty);
      await endTest(tester, p);
    });

    cloudTest('новий ключ відновлення відкриває екран ключа', (tester) async {
      final p = await readyPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      await openSettingsAndScrollTo(tester, 'new-recovery-key');
      await tapKey(tester, 'new-recovery-key');
      expect(find.byKey(const Key('recovery-key-text')), findsOneWidget);
      expect(find.text('Новий ключ відновлення'), findsOneWidget);

      // Можна передумати.
      await tester.ensureVisible(find.text('Скасувати'));
      await tester.tap(find.text('Скасувати'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await endTest(tester, p);
    });

    cloudTest('видалення акаунта вимагає пароль', (tester) async {
      final p = await readyPhone(tester);
      await pumpCloud(tester, p, servicesFor(p));
      await openSettingsAndScrollTo(tester, 'delete-account');
      await tapKey(tester, 'delete-account');

      await typeKey(tester, 'delete-password', 'wrong');
      await tapKey(tester, 'delete-confirm');
      expect(find.text('Неправильна пошта або пароль.'), findsOneWidget);
      expect(p.account.stage, AccountStage.ready);

      await tester.pump(const Duration(seconds: 5));
      await scrollSettingsTo(tester, 'delete-account');
      await tapKey(tester, 'delete-account');
      await typeKey(tester, 'delete-password', 'password123');
      await tapKey(tester, 'delete-confirm');
      expect(find.byKey(const Key('welcome-signin')), findsOneWidget);
      expect(p.cloud.keyDocs, isEmpty);
      await endTest(tester, p);
    });

    cloudTest('автоматичні звіти про збої вмикаються перемикачем', (tester) async {
      final p = await readyPhone(tester);
      final crash = FakeCrash();
      await pumpCloud(tester, p, servicesFor(p, crash: crash));
      await openSettingsAndScrollTo(tester, 'crash-switch');
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('crash-switch'))).value, isTrue);

      await tapKey(tester, 'crash-switch');
      expect(crash.enabled, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('crash-switch'))).value, isFalse);
      await endTest(tester, p);
    });

    cloudTest('без акаунта в налаштуваннях є вхід', (tester) async {
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      await pumpCloud(tester, p, servicesFor(p));
      await openSettingsAndScrollTo(tester, 'account-signin');
      await tapKey(tester, 'account-signin');
      expect(find.byKey(const Key('welcome-signin')), findsOneWidget);
      await endTest(tester, p);
    });
  });

  group('Звіти про проблеми', () {
    cloudTest('користувач надсилає звіт', (tester) async {
      final p = await readyPhone(tester);
      final reports = FakeReportService();
      await pumpCloud(tester, p, servicesFor(p, reports: reports));
      await openSettingsAndScrollTo(tester, 'report-tile');
      await tapKey(tester, 'report-tile');

      // Занадто короткий текст.
      await typeKey(tester, 'report-text', 'ой');
      await tapKey(tester, 'report-send');
      expect(find.text('Опиши проблему хоча б кількома словами.'), findsOneWidget);
      expect(reports.sent, isEmpty);

      await typeKey(tester, 'report-text', 'Таймер не рахує час після перезапуску');
      await tapKey(tester, 'report-send');
      expect(reports.sent.length, 1);
      expect(reports.sent.single.category, 'bug');
      expect(reports.sent.single.attachLog, isTrue);
      expect(reports.sent.single.text, contains('Таймер'));
      expect(find.text('Дякуємо! Звіт надіслано.'), findsOneWidget);
      await endTest(tester, p);
    });

    cloudTest('помилка надсилання показується, звіт можна повторити', (tester) async {
      final p = await readyPhone(tester);
      final reports = FakeReportService()..fail = true;
      await pumpCloud(tester, p, servicesFor(p, reports: reports));
      await openSettingsAndScrollTo(tester, 'report-tile');
      await tapKey(tester, 'report-tile');
      await typeKey(tester, 'report-text', 'Щось пішло не так зі звітом');
      await tapKey(tester, 'report-send');
      expect(find.textContaining('Не вдалося надіслати звіт'), findsOneWidget);

      reports.fail = false;
      await tapKey(tester, 'report-send');
      expect(reports.sent.length, 1);
      await endTest(tester, p);
    });

    cloudTest('без акаунта звіт надіслати не можна', (tester) async {
      final p = await freshPhone(tester, prefsData: {kLocalModeKey: true});
      await pumpCloud(tester, p, servicesFor(p));
      await openSettingsAndScrollTo(tester, 'report-tile');
      await tapKey(tester, 'report-tile');
      expect(find.textContaining('увійди в акаунт'), findsOneWidget);
      expect(find.byKey(const Key('report-send')), findsNothing);
      await endTest(tester, p);
    });

    cloudTest('розробниця бачить звіти й може їх видалити', (tester) async {
      final p = await readyPhone(tester);
      final reports = FakeReportService()
        ..entries.add(
          ReportEntry(
            id: 'r1',
            category: 'bug',
            text: 'Не відкривається день',
            appVersion: '0.5.0 (12)',
            device: 'OPPO CPH2000',
            email: 'tato@example.com',
            createdAt: DateTime(2026, 10, 24, 9, 30),
            log: '09:29:00 start',
          ),
        );
      await pumpCloud(
        tester,
        p,
        servicesFor(p, reports: reports, adminUid: p.account.user!.uid),
      );
      await openSettingsAndScrollTo(tester, 'admin-tile');
      await tapKey(tester, 'admin-tile');

      expect(find.text('Не відкривається день'), findsOneWidget);
      expect(find.textContaining('tato@example.com'), findsOneWidget);

      await tester.tap(find.text('Не відкривається день'));
      await tester.pumpAndSettle();
      expect(find.textContaining('OPPO CPH2000'), findsOneWidget);
      expect(find.text('09:29:00 start'), findsOneWidget);

      await tester.tap(find.byTooltip('Видалити'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Видалити'));
      await tester.pumpAndSettle();
      expect(reports.deleted, ['r1']);
      await endTest(tester, p);
    });

    cloudTest('звичайний користувач розділу звітів не бачить', (tester) async {
      final p = await readyPhone(tester);
      await pumpCloud(tester, p, servicesFor(p, reports: FakeReportService(), adminUid: 'other'));
      await openSettingsAndScrollTo(tester, 'report-tile');
      expect(find.byKey(const Key('admin-tile')), findsNothing);
      await endTest(tester, p);
    });
  });

  group('AppServices', () {
    test('без хмари: нічого не підключено', () {
      final s = AppServices();
      expect(s.cloudEnabled, isFalse);
      expect(s.isAdmin, isFalse);
    });

    cloudTest('isAdmin лише для збігу UID', (tester) async {
      final p = await readyPhone(tester);
      final uid = p.account.user!.uid;
      expect(AppServices(account: p.account, adminUid: uid).isAdmin, isTrue);
      expect(AppServices(account: p.account, adminUid: 'other').isAdmin, isFalse);
      expect(AppServices(account: p.account, adminUid: '').isAdmin, isFalse);
      await p.sync.stop();
    });

    test('сигнал оновлення запам\'ятовується і віддається один раз', () {
      final signal = UpdateOpenSignal();
      expect(signal.consume(), isFalse);
      signal.request();
      expect(signal.consume(), isTrue);
      expect(signal.consume(), isFalse);
    });
  });
}
