// Стан додатка: виходи, чернетка планування, налаштування і таймер.
// Усе зберігається на телефоні.
//
// AppState — це ChangeNotifier: коли дані змінюються, він викликає
// notifyListeners(), і екрани, які за ним «слухають», самі перемальовуються.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logic.dart';
import 'sync/records.dart';

/// Ключі у сховищі телефона.
const String kShiftsKey = 'shifts_v1'; // той самий, що в MVP — дані збережуться
const String kPlanKey = 'plan_v1';
const String kSettingsKey = 'settings_v1';
const String kTimerKey = 'timer_v1';

/// Час зміни кожного дня (для синхронізації): ключ дня → мілісекунди.
const String kStampsKey = 'shift_stamps_v1';

class AppState extends ChangeNotifier {
  /// [clock] — годинник (у тестах підставляється фіксований).
  AppState(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _load();
  }

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  /// Час останньої зміни кожного дня. День, якого немає в [_shifts], але є
  /// тут, — видалений (так видалення синхронізується між телефонами).
  Map<String, int> _stamps = {};

  // ── Дані ──────────────────────────────────────────────────

  /// Справжні виходи на роботу: ключ дня → тривалість у хвилинах.
  Map<String, int> _shifts = {};

  /// Чернетка вкладки «Планування»: ключ дня → тривалість у хвилинах.
  /// Не впливає на справжній календар.
  Map<String, int> _plan = {};

  /// Показувати залишок годин на день і тиждень.
  bool _showRemaining = true;

  /// Тема: за системою / світла / темна.
  ThemeMode _themeMode = ThemeMode.system;

  /// Стандартна тривалість виходу (у хвилинах).
  int _defaultShiftMinutes = kDefaultShiftMinutes;

  /// Ім'я працівника для звітів (ПІБ).
  String _employeeName = '';

  /// Нагадування про початок зміни (у дні, коли в календарі є вихід).
  bool _remindStart = false;
  int _remindStartMinutes = 7 * 60 + 30;

  /// Нагадування про кінець зміни (теж у дні з виходом).
  bool _remindEnd = false;
  int _remindEndMinutes = 20 * 60;

  /// Сповіщення про нові версії додатка.
  bool _pushUpdates = true;

  /// Коли запущено таймер (null — таймер не йде).
  DateTime? _timerStart;

  // ── Читання ───────────────────────────────────────────────

  Map<String, int> get shifts => _shifts;
  Map<String, int> get plan => _plan;
  bool get showRemaining => _showRemaining;
  ThemeMode get themeMode => _themeMode;
  int get defaultShiftMinutes => _defaultShiftMinutes;
  String get employeeName => _employeeName;
  bool get remindStart => _remindStart;
  int get remindStartMinutes => _remindStartMinutes;
  bool get remindEnd => _remindEnd;
  int get remindEndMinutes => _remindEndMinutes;
  bool get pushUpdates => _pushUpdates;
  DateTime? get timerStart => _timerStart;
  bool get timerRunning => _timerStart != null;

  /// Скільки секунд минуло з початку таймера.
  int elapsedSeconds(DateTime now) {
    final start = _timerStart;
    if (start == null) return 0;
    final s = now.difference(start).inSeconds;
    return s < 0 ? 0 : s;
  }

  /// Чи таймер запущено саме в цей день (нічна зміна належить дню початку).
  bool isTimerDay(DateTime date) {
    final start = _timerStart;
    return start != null && dayKey(start) == dayKey(date);
  }

  /// Відпрацьовані хвилини за дні від [from] до [to] включно:
  /// майбутні дні (після [today]) не рахуються, а для дня з таймером
  /// береться поточний час таймера.
  int workedBetween(DateTime from, DateTime to, DateTime today, DateTime now) {
    final start = _timerStart;
    return sumRange(
      _shifts,
      from,
      to,
      until: today,
      overrideKey: start == null ? null : dayKey(start),
      overrideMinutes: elapsedSeconds(now) ~/ 60,
    );
  }

  /// Скільки хвилин відпрацьовано в конкретний день.
  int dayWorked(DateTime date, DateTime today, DateTime now) {
    if (date.isAfter(today)) return 0;
    if (isTimerDay(date)) return elapsedSeconds(now) ~/ 60;
    return _shifts[dayKey(date)] ?? 0;
  }

  /// План дня: поставлений вихід; якщо його немає — 8 год у будній день.
  int dayTarget(DateTime date) {
    final minutes = _shifts[dayKey(date)];
    if (isTimerDay(date)) return minutes ?? _defaultShiftMinutes;
    return minutes ?? (date.weekday <= DateTime.friday ? kDayNormMinutes : 0);
  }

  /// Скільки ще лишилось до плану дня.
  int dayLeft(DateTime date, DateTime today, DateTime now) {
    final worked = dayWorked(date, today, now);
    final target = dayTarget(date);
    return target > worked ? target - worked : 0;
  }

  /// Скільки ще лишилось до 40 год у тижні, якому належить [date].
  int weekLeft(DateTime date, DateTime today, DateTime now) {
    final monday = mondayOf(date);
    final worked = workedBetween(monday, addDays(monday, 6), today, now);
    return kWeekNormMinutes > worked ? kWeekNormMinutes - worked : 0;
  }

  // ── Зміни виходів (з можливістю скасувати) ────────────────

  /// Застосувати зміни до таблиці й повернути, що було раніше.
  /// [changes]: ключ дня → нове значення (null — прибрати).
  Map<String, int?> _apply(Map<String, int> target, Map<String, int?> changes) {
    final previous = <String, int?>{};
    changes.forEach((key, value) {
      previous[key] = target[key];
      if (value == null) {
        target.remove(key);
      } else {
        target[key] = value;
      }
    });
    return previous;
  }

  /// Поставити (minutes) або прибрати (null) вихід на кілька днів.
  /// Повертає попередні значення — їх можна передати в [restoreShifts].
  Map<String, int?> setShifts(Iterable<DateTime> dates, int? minutes) {
    final changes = <String, int?>{
      for (final d in dates) dayKey(d): minutes,
    };
    final previous = _apply(_shifts, changes);
    _touch(changes.keys);
    _saveShifts();
    notifyListeners();
    return previous;
  }

  /// Скасувати зміну виходів (повернути попередні значення).
  /// Скасування теж нова зміна: воно отримує свіжий час і синхронізується.
  void restoreShifts(Map<String, int?> previous) {
    _apply(_shifts, previous);
    _touch(previous.keys);
    _saveShifts();
    notifyListeners();
  }

  /// Записати час зміни для днів [keys].
  void _touch(Iterable<String> keys) {
    final now = _clock().millisecondsSinceEpoch;
    for (final key in keys) {
      _stamps[key] = now;
    }
  }

  /// Стерти всі дані на телефоні: виходи, чернетку, таймер (налаштування лишаються).
  void resetAllData() {
    _shifts = {};
    _stamps = {};
    _plan = {};
    _timerStart = null;
    _saveShifts();
    _savePlan();
    _prefs.remove(kTimerKey);
    notifyListeners();
  }

  // ── Синхронізація ─────────────────────────────────────────

  /// Усі записи днів, включно з видаленими (для хмари).
  Map<String, DayRecord> get dayRecords {
    final keys = {..._shifts.keys, ..._stamps.keys};
    return {
      for (final key in keys)
        key: DayRecord(minutes: _shifts[key], stamp: _stamps[key] ?? 0),
    };
  }

  /// Застосувати записи з хмари. Для кожного дня перемагає пізніший.
  /// Повертає true, якщо щось змінилось на телефоні.
  bool mergeRemote(Map<String, DayRecord> remote) {
    final result = mergeDays(dayRecords, remote);
    if (!result.localNeedsUpdate) return false;
    for (final entry in result.merged.entries) {
      final record = entry.value;
      final minutes = record.minutes;
      if (minutes == null) {
        _shifts.remove(entry.key);
      } else {
        _shifts[entry.key] = minutes;
      }
      _stamps[entry.key] = record.stamp;
    }
    _saveShifts();
    notifyListeners();
    return true;
  }

  // ── Зміни чернетки планування ─────────────────────────────

  Map<String, int?> setPlan(Iterable<DateTime> dates, int? minutes) {
    final changes = <String, int?>{
      for (final d in dates) dayKey(d): minutes,
    };
    final previous = _apply(_plan, changes);
    _savePlan();
    notifyListeners();
    return previous;
  }

  void restorePlan(Map<String, int?> previous) {
    _apply(_plan, previous);
    _savePlan();
    notifyListeners();
  }

  /// Прибрати чернетку за дні від [from] до [to] включно.
  Map<String, int?> clearPlanBetween(DateTime from, DateTime to) {
    final a = dayKey(from);
    final b = dayKey(to);
    final changes = <String, int?>{};
    for (final key in _plan.keys) {
      if (key.compareTo(a) >= 0 && key.compareTo(b) <= 0) changes[key] = null;
    }
    final previous = _apply(_plan, changes);
    _savePlan();
    notifyListeners();
    return previous;
  }

  /// Скопіювати майбутні виходи з календаря у чернетку
  /// (лише дні після [today] у проміжку від [from] до [to]).
  Map<String, int?> copyShiftsToPlan(DateTime from, DateTime to, DateTime today) {
    final a = dayKey(from);
    final b = dayKey(to);
    final t = dayKey(today);
    final changes = <String, int?>{};
    _shifts.forEach((key, value) {
      if (key.compareTo(a) >= 0 && key.compareTo(b) <= 0 && key.compareTo(t) > 0) {
        changes[key] = value;
      }
    });
    final previous = _apply(_plan, changes);
    _savePlan();
    notifyListeners();
    return previous;
  }

  // ── Таймер ────────────────────────────────────────────────

  /// Запустити таймер із моменту [start] («Вийшов на роботу»).
  void startTimer(DateTime start) {
    if (_timerStart != null) return;
    _timerStart = start;
    _prefs.setString(kTimerKey, start.toIso8601String());
    notifyListeners();
  }

  /// Змінити час початку вже запущеного таймера.
  void setTimerStart(DateTime start) {
    if (_timerStart == null) return;
    _timerStart = start;
    _prefs.setString(kTimerKey, start.toIso8601String());
    notifyListeners();
  }

  /// Скасувати таймер без збереження.
  void discardTimer() {
    _timerStart = null;
    _prefs.remove(kTimerKey);
    notifyListeners();
  }

  /// Зупинити таймер і зберегти вихід на день початку.
  void finishTimer(DateTime now) {
    final start = _timerStart;
    if (start == null) return;
    final diff = now.difference(start).inMinutes;
    _shifts[dayKey(start)] = diff < 1 ? 1 : diff;
    _touch([dayKey(start)]);
    _saveShifts();
    discardTimer();
  }

  // ── Налаштування ──────────────────────────────────────────

  void setShowRemaining(bool value) {
    _showRemaining = value;
    _saveSettings();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveSettings();
    notifyListeners();
  }

  void setDefaultShiftMinutes(int minutes) {
    if (minutes < 1 || minutes > 24 * 60) return;
    _defaultShiftMinutes = minutes;
    _saveSettings();
    notifyListeners();
  }

  // ── Збереження ────────────────────────────────────────────

  void _saveShifts() {
    _prefs.setString(kShiftsKey, jsonEncode(_shifts));
    _prefs.setString(kStampsKey, jsonEncode(_stamps));
  }

  void _savePlan() {
    _prefs.setString(kPlanKey, jsonEncode(_plan));
  }

  void setRemindStart(bool value) {
    if (value == _remindStart) return;
    _remindStart = value;
    _saveSettings();
    notifyListeners();
  }

  void setRemindStartMinutes(int minutes) {
    _remindStartMinutes = minutes < 0 ? 0 : (minutes > 1439 ? 1439 : minutes);
    _saveSettings();
    notifyListeners();
  }

  void setRemindEnd(bool value) {
    if (value == _remindEnd) return;
    _remindEnd = value;
    _saveSettings();
    notifyListeners();
  }

  void setRemindEndMinutes(int minutes) {
    _remindEndMinutes = minutes < 0 ? 0 : (minutes > 1439 ? 1439 : minutes);
    _saveSettings();
    notifyListeners();
  }

  void setPushUpdates(bool value) {
    if (value == _pushUpdates) return;
    _pushUpdates = value;
    _saveSettings();
    notifyListeners();
  }

  /// Запам'ятати ім'я працівника для звітів.
  void setEmployeeName(String name) {
    final value = name.trim();
    if (value == _employeeName) return;
    _employeeName = value;
    _saveSettings();
    notifyListeners();
  }

  void _saveSettings() {
    _prefs.setString(
      kSettingsKey,
      jsonEncode({
        'showRemaining': _showRemaining,
        'defaultShiftMinutes': _defaultShiftMinutes,
        'theme': _themeMode.name,
        'employee': _employeeName,
        'remindStart': _remindStart,
        'remindStartMinutes': _remindStartMinutes,
        'remindEnd': _remindEnd,
        'remindEndMinutes': _remindEndMinutes,
        'pushUpdates': _pushUpdates,
      }),
    );
  }

  /// Читаємо таблицю «ключ дня → хвилини» зі сховища.
  /// Якщо дані пошкоджені — повертаємо порожню, а не падаємо.
  Map<String, int> _readMap(String storageKey) {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      return {};
    }
  }

  /// Читаємо все зі сховища.
  void _load() {
    _shifts = _readMap(kShiftsKey);
    _stamps = _readMap(kStampsKey);
    _plan = _readMap(kPlanKey);

    final rawSettings = _prefs.getString(kSettingsKey);
    if (rawSettings != null) {
      try {
        final m = jsonDecode(rawSettings) as Map<String, dynamic>;
        _showRemaining = (m['showRemaining'] as bool?) ?? true;
        _defaultShiftMinutes =
            (m['defaultShiftMinutes'] as int?) ?? kDefaultShiftMinutes;
        _employeeName = (m['employee'] as String?) ?? '';
        _remindStart = (m['remindStart'] as bool?) ?? false;
        _remindStartMinutes = (m['remindStartMinutes'] as int?) ?? 7 * 60 + 30;
        _remindEnd = (m['remindEnd'] as bool?) ?? false;
        _remindEndMinutes = (m['remindEndMinutes'] as int?) ?? 20 * 60;
        _pushUpdates = (m['pushUpdates'] as bool?) ?? true;
        final theme = m['theme'] as String?;
        _themeMode = ThemeMode.values.firstWhere(
              (e) => e.name == theme,
          orElse: () => ThemeMode.system,
        );
      } catch (_) {
        // залишаємо значення за замовчуванням
      }
    }

    final rawTimer = _prefs.getString(kTimerKey);
    if (rawTimer != null) {
      _timerStart = DateTime.tryParse(rawTimer);
    }
  }
}
