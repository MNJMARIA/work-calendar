// Завантаження й встановлення APK через пакет ota_update (лише Android).
// Статуси пакета порівнюються за назвою (рядком), щоб код не ламався,
// якщо в новій версії пакета зміняться деякі назви перелічення.

import 'package:ota_update/ota_update.dart';

import 'update_service.dart';

class OtaApkInstaller implements ApkInstaller {
  @override
  Stream<InstallProgress> install(String url, {String? sha256}) async* {
    final events = OtaUpdate().execute(
      url,
      destinationFilename: 'work-calendar-update.apk',
      sha256checksum: sha256,
    );
    await for (final event in events) {
      final status = event.status.name;
      final value = event.value ?? '';
      switch (status) {
        case 'DOWNLOADING':
          yield InstallProgress(InstallPhase.downloading, percent: int.tryParse(value) ?? 0);
        case 'INSTALLING':
        case 'INSTALLATION_DONE':
          yield const InstallProgress(InstallPhase.installing);
        case 'CANCELED':
          yield const InstallProgress(
            InstallPhase.error,
            error: 'Встановлення скасовано. Спробуй ще раз.',
          );
        case 'PERMISSION_NOT_GRANTED_ERROR':
          yield const InstallProgress(
            InstallPhase.error,
            error: 'Телефон не дозволив встановлення. Дозволь встановлення '
                'додатків із цього джерела й спробуй ще раз.',
          );
        case 'CHECKSUM_ERROR':
          yield const InstallProgress(
            InstallPhase.error,
            error: 'Файл оновлення пошкоджено під час завантаження. Спробуй ще раз.',
          );
        case 'DOWNLOAD_ERROR':
          yield const InstallProgress(
            InstallPhase.error,
            error: 'Не вдалося завантажити оновлення. Перевір інтернет.',
          );
        case 'ALREADY_RUNNING_ERROR':
          yield const InstallProgress(
            InstallPhase.error,
            error: 'Оновлення вже завантажується.',
          );
        default:
          if (status.endsWith('ERROR')) {
            yield InstallProgress(
              InstallPhase.error,
              error: 'Не вдалося оновити ($status). Скористайся кнопкою '
                  '«Відкрити сторінку завантаження».',
            );
          }
      }
    }
  }
}
