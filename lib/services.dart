// Набір «хмарних» сервісів додатка. Екрани беруть його через AppServicesScope,
// тому їм не треба знати, як саме сервіси створено (Firebase чи імітація).
// Коли хмара не підключена (наприклад, у тестах), усе поля порожні,
// а cloudEnabled = false: додаток працює повністю локально.

import 'package:flutter/widgets.dart';

import 'account/account_controller.dart';
import 'export/report_archive.dart';
import 'notifications/reminder_service.dart';
import 'reports/report_service.dart';
import 'sync/sync_service.dart';
import 'updates/update_service.dart';

/// Вмикає й вимикає автоматичні звіти про збої (Crashlytics).
abstract class CrashControl {
  bool get enabled;

  Future<void> setEnabled(bool value);
}

/// Сигнал «відкрий екран оновлення» (користувач натиснув на сповіщення).
/// Запит може прийти раніше, ніж з'явиться екран, тому він запам'ятовується.
class UpdateOpenSignal extends ChangeNotifier {
  bool _pending = false;

  void request() {
    _pending = true;
    notifyListeners();
  }

  /// Забрати запит: true, якщо він був (повторно вже false).
  bool consume() {
    final was = _pending;
    _pending = false;
    return was;
  }
}

class AppServices {
  AppServices({
    this.account,
    this.sync,
    this.updates,
    ReportService? reports,
    this.crash,
    this.adminUid = '',
    this.currentVersion = '',
    this.openUrl,
    this.justUpdatedFrom,
    this.cloudError,
    this.archive,
    this.reminders,
    this.setUpdatePush,
    UpdateOpenSignal? openUpdateSignal,
  })  : reports = reports ?? OfflineReportService(),
        openUpdateSignal = openUpdateSignal ?? UpdateOpenSignal();

  final AccountController? account;
  final SyncService? sync;
  final UpdateService? updates;
  final ReportService reports;
  final CrashControl? crash;

  /// Ідентифікатор акаунта розробниці (бачить екран «Звіти користувачів»).
  /// Справжній захист — правила Firestore; це лише щоб показати кнопку.
  final String adminUid;

  /// Версія для показу, наприклад «0.5.0 (12)».
  final String currentVersion;

  /// Відкрити посилання в браузері.
  final Future<void> Function(String url)? openUrl;

  final UpdateOpenSignal openUpdateSignal;

  /// Якщо хмара не запустилась: що саме пішло не так (показується в налаштуваннях,
  /// щоб причину було видно, а не «тихо» працювати без акаунта).
  final String? cloudError;

  /// Архів сформованих звітів (null — недоступний).
  final ReportArchive? archive;

  /// Нагадування про зміни (null — недоступні, наприклад у тестах).
  final ReminderController? reminders;

  /// Увімкнути/вимкнути сповіщення про оновлення (потрібна хмара).
  final Future<void> Function(bool enabled)? setUpdatePush;

  /// Копія з доданими архівом і нагадуваннями (їх створює main.dart).
  AppServices copyWith({ReportArchive? archive, ReminderController? reminders}) {
    return AppServices(
      account: account,
      sync: sync,
      updates: updates,
      reports: reports,
      crash: crash,
      adminUid: adminUid,
      currentVersion: currentVersion,
      openUrl: openUrl,
      justUpdatedFrom: justUpdatedFrom,
      cloudError: cloudError,
      archive: archive ?? this.archive,
      reminders: reminders ?? this.reminders,
      setUpdatePush: setUpdatePush,
      openUpdateSignal: openUpdateSignal,
    );
  }

  /// Номер збірки, з якої додаток щойно оновився (для вікна «Додаток оновлено»).
  int? justUpdatedFrom;

  /// Забрати «щойно оновились» (показуємо вікно лише один раз).
  int? takeJustUpdated() {
    final value = justUpdatedFrom;
    justUpdatedFrom = null;
    return value;
  }

  bool get cloudEnabled => account != null;

  bool get isAdmin {
    final uid = account?.user?.uid;
    return adminUid.isNotEmpty && uid == adminUid;
  }

  /// Порожній набір: хмари немає.
  static final AppServices none = AppServices();
}

class AppServicesScope extends InheritedWidget {
  const AppServicesScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppServicesScope>()
        ?.services ??
        AppServices.none;
  }

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) =>
      services != oldWidget.services;
}
