// Точка входу. Тут запускається Firebase (хмара), а сам додаток — в app.dart.
//
// Якщо Firebase не налаштовано (немає android/app/google-services.json) або
// не вдалося запуститися, додаток працює повністю локально, як і раніше.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_state.dart';
import 'diagnostics.dart';
import 'export/report_archive.dart';
import 'firebase_services.dart';
import 'notifications/reminder_service.dart';
import 'services.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  AppLog.attach(prefs);
  final state = AppState(prefs);

  var services = AppServices.none;
  try {
    services = await createCloudServices(prefs, state);
  } catch (e) {
    AppLog.add('Хмара не запущена, працюємо локально: $e');
    // Запам'ятовуємо причину: її покаже екран «Налаштування».
    services = AppServices(cloudError: '$e');
  }

  // Архів звітів і нагадування працюють і без хмари.
  final reminders = ReminderController(state: state, scheduler: LocalReminderScheduler())..start();
  services = services.copyWith(archive: await _openArchive(prefs), reminders: reminders);

  runApp(WorkCalendarApp(state: state, services: services));
}

/// Папка архіву звітів у сховищі додатка (інші додатки її не бачать).
Future<ReportArchive?> _openArchive(SharedPreferences prefs) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    return FileReportArchive(prefs, Directory('${docs.path}${Platform.pathSeparator}reports'));
  } catch (e) {
    AppLog.add('архів звітів недоступний: $e');
    return null;
  }
}
