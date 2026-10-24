// Синхронізація «спочатку локально»: запис іде в телефон, а в хмару —
// у фоні, коли є зв'язок. У хмару потрапляє лише шифротекст.
//
// Правила безпеки даних:
//  • хмара ніколи не перезаписує те, що не вдалося розшифрувати;
//  • локальні дані ніколи не видаляються через відсутність запису в хмарі
//    (видалення — це окремий запис-«надгробок»);
//  • помилка мережі не ламає додаток: статус стає «немає зв'язку».

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../crypto/crypto_service.dart';
import '../diagnostics.dart';
import 'cloud_store.dart';
import 'records.dart';

enum SyncStatus { off, idle, syncing, offline, error }

class SyncService extends ChangeNotifier {
  SyncService({
    required this.state,
    required this.cloud,
    CryptoService? crypto,
    this.debounce = const Duration(seconds: 2),
    this.putTimeout = const Duration(seconds: 10),
  }) : crypto = crypto ?? CryptoService();

  final AppState state;
  final CloudStore cloud;
  final CryptoService crypto;
  final Duration debounce;
  final Duration putTimeout;

  SyncStatus _status = SyncStatus.off;
  String? _lastError;
  DateTime? _lastSync;

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastSync => _lastSync;

  String? _uid;
  Uint8List? _dataKey;
  StreamSubscription<CloudEvent>? _sub;
  Timer? _timer;
  bool _pushing = false;
  bool _pushAgain = false;

  /// Відбиток того, що, як ми вважаємо, лежить у хмарі: місяць → відбиток.
  final Map<String, String> _known = {};

  /// Місяці, які не вдалося розшифрувати: їх ніколи не перезаписуємо.
  final Set<String> _blocked = {};

  bool get running => _uid != null;

  void _setStatus(SyncStatus status, {String? error}) {
    _status = status;
    _lastError = error;
    notifyListeners();
  }

  /// Запустити синхронізацію для користувача [uid] з ключем даних [dataKey].
  Future<void> start(String uid, Uint8List dataKey) async {
    await stop();
    _uid = uid;
    _dataKey = dataKey;
    _known.clear();
    _blocked.clear();
    _setStatus(SyncStatus.syncing);
    state.addListener(_onLocalChange);
    _sub = cloud.watchMonths(uid).listen(
      _onRemote,
      onError: (Object e) {
        AppLog.add('sync: помилка стеження: $e');
        _setStatus(SyncStatus.offline, error: '$e');
      },
    );
  }

  Future<void> stop() async {
    state.removeListener(_onLocalChange);
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    _dataKey = null;
    if (_status != SyncStatus.off) {
      _status = SyncStatus.off;
      notifyListeners();
    }
  }

  /// Надіслати все, що ще не в хмарі, негайно (кнопка «Синхронізувати»).
  Future<void> syncNow() async {
    _timer?.cancel();
    await _pushDirty();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    state.removeListener(_onLocalChange);
    super.dispose();
  }

  // ── Локальні зміни → хмара ────────────────────────────────

  void _onLocalChange() {
    _timer?.cancel();
    _timer = Timer(debounce, _pushDirty);
  }

  Future<void> _pushDirty() async {
    final uid = _uid;
    final key = _dataKey;
    if (uid == null || key == null) return;
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    try {
      final byMonth = groupByMonth(state.dayRecords);
      var failed = false;
      var pushedAny = false;
      for (final entry in byMonth.entries) {
        final month = entry.key;
        if (_blocked.contains(month)) continue;
        final digest = digestOf(entry.value);
        if (_known[month] == digest) continue;
        pushedAny = true;
        _setStatus(SyncStatus.syncing);
        try {
          final env = await crypto.encryptMonth(
            uid,
            month,
            monthPayload(entry.value),
            key,
          );
          await cloud
              .putMonth(uid, month, {
            'v': kFormatVersion,
            'env': env.toJson(),
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          })
              .timeout(putTimeout);
          _known[month] = digest;
        } on TimeoutException {
          // Немає зв'язку: запис стоїть у черзі Firestore й піде сам.
          failed = true;
        } catch (e) {
          AppLog.add('sync: не вдалося надіслати $month: $e');
          failed = true;
          _setStatus(SyncStatus.error, error: '$e');
        }
      }
      if (failed) {
        if (_status != SyncStatus.error) _setStatus(SyncStatus.offline);
      } else if (_status != SyncStatus.error) {
        if (pushedAny) _lastSync = DateTime.now();
        _setStatus(SyncStatus.idle);
      }
    } finally {
      _pushing = false;
      if (_pushAgain) {
        _pushAgain = false;
        _onLocalChange();
      }
    }
  }

  // ── Хмара → телефон ───────────────────────────────────────

  Future<void> _onRemote(CloudEvent event) async {
    final uid = _uid;
    final key = _dataKey;
    if (uid == null || key == null) return;

    var decryptFailed = false;
    for (final entry in event.months.entries) {
      final month = entry.key;
      try {
        final doc = entry.value;
        final env = Envelope.fromJson(Map<String, dynamic>.from(doc['env'] as Map));
        final payload = await crypto.decryptMonth(uid, month, env, key);
        final remote = parseMonthPayload(payload);
        _blocked.remove(month);
        _known[month] = digestOf(remote);
        state.mergeRemote(remote);
      } catch (e) {
        decryptFailed = true;
        _blocked.add(month);
        AppLog.add('sync: не вдалося розшифрувати $month: $e');
      }
    }

    if (decryptFailed) {
      _setStatus(
        SyncStatus.error,
        error: 'Частину даних у хмарі не вдалося розшифрувати',
      );
    } else if (event.fromCache) {
      _setStatus(SyncStatus.offline);
    } else {
      _lastSync = DateTime.now();
      _setStatus(SyncStatus.idle);
    }
    // Після злиття могло з'явитися те, чого немає в хмарі (наприклад, дні,
    // зроблені без зв'язку): надсилаємо.
    _onLocalChange();
  }
}
