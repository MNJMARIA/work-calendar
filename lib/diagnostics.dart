// Короткий журнал подій додатка. Додається до звіту про проблему,
// щоб було видно, що відбувалось перед помилкою.
// Журнал живе лише в пам'яті й не містить годин чи інших даних користувача.

class AppLog {
  AppLog._();

  static const int _max = 80;
  static final List<String> _lines = [];

  /// Додати рядок (час додається автоматично).
  static void add(String message) {
    final now = DateTime.now();
    final stamp = '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
    _lines.add('$stamp $message');
    if (_lines.length > _max) _lines.removeAt(0);
  }

  /// Останні [n] рядків.
  static List<String> tail([int n = 40]) {
    final start = _lines.length > n ? _lines.length - n : 0;
    return List.unmodifiable(_lines.sublist(start));
  }

  static void clear() => _lines.clear();

  static String _two(int v) => v.toString().padLeft(2, '0');
}
