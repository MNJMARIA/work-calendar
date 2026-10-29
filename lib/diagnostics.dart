// Короткий журнал подій додатка. Додається до звіту про проблему,
// щоб було видно, що відбувалось перед помилкою.
// Останні рядки зберігаються на телефоні, щоб було видно, що відбувалось перед
// аварійним закриттям. Журнал не містить годин чи інших даних користувача.

import 'package:shared_preferences/shared_preferences.dart';

class AppLog {
  AppLog._();

  static const int _max = 80;
  static const String _storeKey = 'app_log_v1';
  static final List<String> _lines = [];
  static SharedPreferences? _prefs;

  /// Рядки журналу з попереднього запуску (корисно, якщо додаток аварійно
  /// закрився: що відбувалось перед цим). Заповнюється в [attach].
  static List<String> previousSession = const [];

  /// Підключити сховище телефона: журнал переживе перезапуск додатка.
  static void attach(SharedPreferences prefs) {
    _prefs = prefs;
    previousSession = List.unmodifiable(prefs.getStringList(_storeKey) ?? const <String>[]);
  }

  /// Додати рядок (час додається автоматично).
  static void add(String message) {
    final now = DateTime.now();
    final stamp = '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
    _lines.add('$stamp $message');
    if (_lines.length > _max) _lines.removeAt(0);
    // Зберігаємо одразу: після аварії додатка запис уже лежить на телефоні.
    _prefs?.setStringList(_storeKey, List<String>.of(_lines));
  }

  /// Рядки для звіту: кінець попереднього запуску + поточний запуск.
  static List<String> reportLines([int n = 40]) {
    final previous = previousSession.length > 20
        ? previousSession.sublist(previousSession.length - 20)
        : previousSession;
    return [
      if (previous.isNotEmpty) '--- попередній запуск ---',
      ...previous,
      if (previous.isNotEmpty) '--- поточний запуск ---',
      ...tail(n),
    ];
  }

  /// Останні [n] рядків.
  static List<String> tail([int n = 40]) {
    final start = _lines.length > n ? _lines.length - n : 0;
    return List.unmodifiable(_lines.sublist(start));
  }

  static void clear() => _lines.clear();

  static String _two(int v) => v.toString().padLeft(2, '0');
}
