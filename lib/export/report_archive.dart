// Архів сформованих звітів: кожен збережений PDF лежить файлом на телефоні,
// а список (дата формування, місяць, ім'я, розмір) — в окремому переліку.
// У хмару звіти не потрапляють.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics.dart';
import 'month_report.dart';

/// Запис про один збережений звіт.
class ArchivedReport {
  const ArchivedReport({
    required this.id,
    required this.year,
    required this.month,
    required this.employee,
    required this.createdAt,
    required this.sizeBytes,
    required this.onlyShiftDays,
  });

  final String id;
  final int year;
  final int month;
  final String employee;
  final DateTime createdAt;
  final int sizeBytes;
  final bool onlyShiftDays;

  String get fileName => reportFileName(year, month);

  Map<String, dynamic> toJson() => {
    'id': id,
    'year': year,
    'month': month,
    'employee': employee,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'size': sizeBytes,
    'onlyShiftDays': onlyShiftDays,
  };

  static ArchivedReport fromJson(Map<String, dynamic> m) {
    return ArchivedReport(
      id: '${m['id']}',
      year: m['year'] as int,
      month: m['month'] as int,
      employee: (m['employee'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      sizeBytes: (m['size'] as int?) ?? 0,
      onlyShiftDays: (m['onlyShiftDays'] as bool?) ?? false,
    );
  }
}

/// Спільний інтерфейс архіву. Екрани слухають його, як ChangeNotifier.
abstract class ReportArchive extends ChangeNotifier {
  /// Збережені звіти, найновіші першими.
  List<ArchivedReport> get items;

  /// Зберегти PDF в архів.
  Future<ArchivedReport> add({
    required int year,
    required int month,
    required String employee,
    required DateTime createdAt,
    required bool onlyShiftDays,
    required Uint8List pdf,
  });

  /// Прочитати PDF (null, якщо файл зник).
  Future<Uint8List?> read(String id);

  /// Видалити звіт з архіву.
  Future<void> remove(String id);
}

/// Архів у пам'яті (для тестів).
class MemoryReportArchive extends ReportArchive {
  final Map<String, Uint8List> _files = {};
  List<ArchivedReport> _items = [];
  int _counter = 0;

  @override
  List<ArchivedReport> get items => List.unmodifiable(_items);

  @override
  Future<ArchivedReport> add({
    required int year,
    required int month,
    required String employee,
    required DateTime createdAt,
    required bool onlyShiftDays,
    required Uint8List pdf,
  }) async {
    final item = ArchivedReport(
      id: '${++_counter}',
      year: year,
      month: month,
      employee: employee,
      createdAt: createdAt,
      sizeBytes: pdf.length,
      onlyShiftDays: onlyShiftDays,
    );
    _files[item.id] = pdf;
    _items = [item, ..._items];
    notifyListeners();
    return item;
  }

  @override
  Future<Uint8List?> read(String id) async => _files[id];

  @override
  Future<void> remove(String id) async {
    _files.remove(id);
    _items = _items.where((e) => e.id != id).toList();
    notifyListeners();
  }
}

/// Архів у файлах: PDF лежать у папці [dir], список — у сховищі налаштувань.
class FileReportArchive extends ReportArchive {
  FileReportArchive(this._prefs, this._dir) {
    _load();
  }

  static const String storeKey = 'report_archive_v1';

  final SharedPreferences _prefs;
  final Directory _dir;
  List<ArchivedReport> _items = [];

  @override
  List<ArchivedReport> get items => List.unmodifiable(_items);

  File _file(String id) => File('${_dir.path}${Platform.pathSeparator}$id.pdf');

  void _load() {
    final raw = _prefs.getString(storeKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _items = [
        for (final e in list) ArchivedReport.fromJson(e as Map<String, dynamic>),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      AppLog.add('архів: список пошкоджено, починаємо з порожнього: $e');
      _items = [];
    }
  }

  Future<void> _save() async {
    await _prefs.setString(storeKey, jsonEncode([for (final e in _items) e.toJson()]));
  }

  @override
  Future<ArchivedReport> add({
    required int year,
    required int month,
    required String employee,
    required DateTime createdAt,
    required bool onlyShiftDays,
    required Uint8List pdf,
  }) async {
    await _dir.create(recursive: true);
    var stamp = createdAt.millisecondsSinceEpoch;
    while (_items.any((e) => e.id == '$stamp') || _file('$stamp').existsSync()) {
      stamp++;
    }
    final id = '$stamp';
    await _file(id).writeAsBytes(pdf, flush: true);
    final item = ArchivedReport(
      id: id,
      year: year,
      month: month,
      employee: employee,
      createdAt: createdAt,
      sizeBytes: pdf.length,
      onlyShiftDays: onlyShiftDays,
    );
    _items = [item, ..._items];
    await _save();
    notifyListeners();
    return item;
  }

  @override
  Future<Uint8List?> read(String id) async {
    final file = _file(id);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> remove(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
    _items = _items.where((e) => e.id != id).toList();
    await _save();
    notifyListeners();
  }
}

/// «54 КБ», «1.2 МБ».
String fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}
