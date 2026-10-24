// Сервіс оновлень: перевіряє GitHub Releases, завантажує й встановлює APK.
// Мережа та інсталятор підставляються ззовні, тому все це легко тестувати.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics.dart';
import 'update_logic.dart';

/// Ключ, де зберігається остання «побачена» збірка (для повідомлення
/// «Додаток оновлено»).
const String kLastSeenBuildKey = 'last_seen_build_v1';

/// Отримати JSON останнього релізу (або null, якщо немає зв'язку).
typedef ReleaseFetcher = Future<Map<String, dynamic>?> Function();

enum InstallPhase { downloading, installing, error }

class InstallProgress {
  const InstallProgress(this.phase, {this.percent = 0, this.error});

  final InstallPhase phase;
  final int percent;
  final String? error;
}

/// Завантажує APK і передає його системному інсталятору.
abstract class ApkInstaller {
  Stream<InstallProgress> install(String url, {String? sha256});
}

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, error }

class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.currentBuild,
    required this.currentVersion,
    required this.fetcher,
    required this.installer,
  });

  final int currentBuild;
  final String currentVersion;
  final ReleaseFetcher fetcher;
  final ApkInstaller installer;

  UpdateStatus _status = UpdateStatus.idle;
  ReleaseInfo? _latest;
  int _percent = 0;
  String? _error;

  UpdateStatus get status => _status;

  /// Найновіший реліз, який вдалося отримати (може бути не новіший за встановлений).
  ReleaseInfo? get latest => _latest;

  /// Реліз, на який можна оновитись (null, якщо оновлення немає).
  ReleaseInfo? get available =>
      (_latest != null && isNewerBuild(current: currentBuild, latest: _latest!.build))
          ? _latest
          : null;

  int get percent => _percent;
  String? get error => _error;

  void _set(UpdateStatus status, {String? error}) {
    _status = status;
    _error = error;
    notifyListeners();
  }

  /// Перевірити, чи є нова версія. Без інтернету тихо нічого не робить.
  Future<void> check() async {
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing) {
      return;
    }
    _set(UpdateStatus.checking);
    try {
      final json = await fetcher();
      if (json == null) {
        _set(UpdateStatus.idle);
        return;
      }
      _latest = parseRelease(json);
      _set(available != null ? UpdateStatus.available : UpdateStatus.upToDate);
    } catch (e) {
      AppLog.add('update: перевірка не вдалась: $e');
      _set(UpdateStatus.idle);
    }
  }

  /// Завантажити й встановити знайдене оновлення.
  Future<void> install() async {
    final release = available;
    if (release == null) return;
    if (_status == UpdateStatus.downloading || _status == UpdateStatus.installing) {
      return;
    }
    _percent = 0;
    _set(UpdateStatus.downloading);
    try {
      await for (final event
      in installer.install(release.apkUrl, sha256: release.sha256)) {
        switch (event.phase) {
          case InstallPhase.downloading:
            _percent = event.percent;
            _set(UpdateStatus.downloading);
          case InstallPhase.installing:
            _set(UpdateStatus.installing);
          case InstallPhase.error:
            AppLog.add('update: помилка встановлення: ${event.error}');
            _set(UpdateStatus.error, error: event.error ?? 'Не вдалося оновити');
            return;
        }
      }
      // Потік завершився без помилки: система показала вікно встановлення.
      if (_status != UpdateStatus.installing) _set(UpdateStatus.installing);
    } catch (e) {
      AppLog.add('update: виняток: $e');
      _set(UpdateStatus.error, error: '$e');
    }
  }

  /// Скинути помилку (після того як користувач її побачив).
  void clearError() {
    if (_status == UpdateStatus.error) _set(available != null ? UpdateStatus.available : UpdateStatus.idle);
  }
}

/// Чи додаток щойно оновився. Повертає номер попередньої збірки, якщо
/// поточна новіша; зберігає поточну як «побачену».
/// На першому запуску після встановлення повертає null.
int? detectJustUpdated(SharedPreferences prefs, int currentBuild) {
  final previous = prefs.getInt(kLastSeenBuildKey);
  prefs.setInt(kLastSeenBuildKey, currentBuild);
  if (previous == null) return null;
  return currentBuild > previous ? previous : null;
}
