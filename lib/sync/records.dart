// Записи днів для синхронізації й правила злиття.
//
// Кожен день має «час зміни» (stamp, мілісекунди). Видалення теж запис
// (minutes = null): тому видалений день не «воскресає» з іншого телефона.
// Під час злиття для кожного дня перемагає запис із пізнішим часом;
// при рівному часі — детермінований вибір, однаковий на всіх пристроях.

import 'dart:convert';

class DayRecord {
  const DayRecord({required this.minutes, required this.stamp});

  /// Тривалість виходу у хвилинах; null — день видалено.
  final int? minutes;

  /// Час останньої зміни (мілісекунди від 1970).
  final int stamp;

  bool get deleted => minutes == null;

  Map<String, dynamic> toJson() => {'m': minutes, 't': stamp};

  factory DayRecord.fromJson(Map<String, dynamic> json) {
    return DayRecord(minutes: json['m'] as int?, stamp: (json['t'] as int?) ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      other is DayRecord && other.minutes == minutes && other.stamp == stamp;

  @override
  int get hashCode => Object.hash(minutes, stamp);

  @override
  String toString() => 'DayRecord($minutes, $stamp)';
}

/// «2026-10-24» → «2026-10».
String monthOfDayKey(String dayKey) => dayKey.substring(0, 7);

/// Який із двох записів новіший (перемагає).
DayRecord pickNewer(DayRecord a, DayRecord b) {
  if (a.stamp != b.stamp) return a.stamp > b.stamp ? a : b;
  // Однаковий час: вибираємо передбачувано (більше значення; видалення — найменше).
  final am = a.minutes ?? -1;
  final bm = b.minutes ?? -1;
  return am >= bm ? a : b;
}

class MergeResult {
  const MergeResult({
    required this.merged,
    required this.remoteNeedsUpdate,
    required this.localNeedsUpdate,
  });

  /// Результат злиття.
  final Map<String, DayRecord> merged;

  /// Хмара відстає: треба надіслати злитий результат.
  final bool remoteNeedsUpdate;

  /// Телефон відстає: треба застосувати дані з хмари.
  final bool localNeedsUpdate;
}

/// Злиття записів двох сторін (локальної та хмарної).
MergeResult mergeDays(
    Map<String, DayRecord> local,
    Map<String, DayRecord> remote,
    ) {
  final merged = <String, DayRecord>{};
  var remoteNeedsUpdate = false;
  var localNeedsUpdate = false;

  for (final key in {...local.keys, ...remote.keys}) {
    final l = local[key];
    final r = remote[key];
    final DayRecord winner;
    if (l == null) {
      winner = r!;
    } else if (r == null) {
      winner = l;
    } else {
      winner = pickNewer(l, r);
    }
    merged[key] = winner;
    if (r == null || r != winner) remoteNeedsUpdate = true;
    if (l == null || l != winner) localNeedsUpdate = true;
  }

  return MergeResult(
    merged: merged,
    remoteNeedsUpdate: remoteNeedsUpdate,
    localNeedsUpdate: localNeedsUpdate,
  );
}

/// Вміст зашифрованого запису місяця (до шифрування).
Map<String, dynamic> monthPayload(Map<String, DayRecord> days) {
  final keys = days.keys.toList()..sort();
  return {
    'days': {for (final k in keys) k: days[k]!.toJson()},
  };
}

/// Прочитати записи місяця з розшифрованого вмісту.
Map<String, DayRecord> parseMonthPayload(Map<String, dynamic> payload) {
  final raw = (payload['days'] as Map?) ?? const {};
  return {
    for (final e in raw.entries)
      e.key as String: DayRecord.fromJson(Map<String, dynamic>.from(e.value as Map)),
  };
}

/// Короткий «відбиток» вмісту місяця: однакові дані → однаковий рядок.
String digestOf(Map<String, DayRecord> days) {
  final keys = days.keys.toList()..sort();
  return jsonEncode([
    for (final k in keys) [k, days[k]!.minutes, days[k]!.stamp],
  ]);
}

/// Розкласти записи по місяцях: «2026-10» → записи цього місяця.
Map<String, Map<String, DayRecord>> groupByMonth(Map<String, DayRecord> days) {
  final out = <String, Map<String, DayRecord>>{};
  days.forEach((key, record) {
    out.putIfAbsent(monthOfDayKey(key), () => {})[key] = record;
  });
  return out;
}
