// Керування акаунтом: вхід, підтвердження пошти, ключ даних і ключ відновлення.
// Це «мозок» екранів входу: самі екрани лише показують його стан.
//
// Етапи (AccountStage):
//   loading → welcome → needVerify → (newKey | needRecoveryKey) → ready
//   або localOnly (користувач вирішив працювати без акаунта).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../crypto/crypto_service.dart';
import '../diagnostics.dart';
import '../sync/cloud_store.dart';
import '../sync/sync_service.dart';
import 'auth_service.dart';
import 'key_store.dart';

const String kLocalModeKey = 'local_mode_v1';

enum AccountStage {
  loading,
  welcome,
  needVerify,
  keyCheckFailed,
  needRecoveryKey,
  newKey,
  ready,
  localOnly,
}

class AccountController extends ChangeNotifier {
  AccountController({
    required this.auth,
    required this.cloud,
    required this.keys,
    required this.sync,
    required this.state,
    required this.prefs,
    CryptoService? crypto,
    this.cloudTimeout = const Duration(seconds: 15),
  }) : crypto = crypto ?? CryptoService();

  final AuthService auth;
  final CloudStore cloud;
  final KeyStore keys;
  final SyncService sync;
  final AppState state;
  final SharedPreferences prefs;
  final CryptoService crypto;
  final Duration cloudTimeout;

  AccountStage _stage = AccountStage.loading;
  bool _busy = false;
  String? _error;

  /// Ключ відновлення, який зараз показується користувачу (текст).
  String? _pendingRecoveryText;
  Uint8List? _pendingRecovery;
  Uint8List? _pendingDataKey;
  bool _regenerating = false;

  /// Для якого користувача вже запущена синхронізація.
  String? _readyUid;
  Future<void>? _resolveFuture;

  StreamSubscription<AuthUser?>? _sub;

  AccountStage get stage => _stage;
  bool get busy => _busy;
  String? get error => _error;
  String? get pendingRecoveryText => _pendingRecoveryText;
  bool get regenerating => _regenerating;
  AuthUser? get user => auth.currentUser;
  bool get signedIn => _stage == AccountStage.ready;

  void _setStage(AccountStage stage) {
    _stage = stage;
    notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  /// Виконати дію з індикатором «зайнято» й показом помилки.
  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on AuthException catch (e) {
      _error = e.message;
    } on CryptoException catch (e) {
      _error = e.message;
    } on TimeoutException {
      _error = 'Немає зв\'язку із сервером. Перевір інтернет і спробуй ще раз.';
    } catch (e) {
      AppLog.add('account: $e');
      _error = 'Щось пішло не так. Спробуй ще раз.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── Запуск ────────────────────────────────────────────────

  Future<void> init() async {
    try {
      if (prefs.getBool(kLocalModeKey) == true) {
        _setStage(AccountStage.localOnly);
      } else {
        await _onUser(auth.currentUser);
      }
    } catch (e) {
      AppLog.add('account: помилка запуску: $e');
      if (_stage == AccountStage.loading) _setStage(AccountStage.welcome);
    }
    _sub = auth.userChanges.listen((u) {
      if (prefs.getBool(kLocalModeKey) == true) return;
      _onUser(u).catchError((Object e) {
        AppLog.add('account: помилка після зміни користувача: $e');
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onUser(AuthUser? user) async {
    if (user == null) {
      await sync.stop();
      _readyUid = null;
      _pendingDataKey = null;
      _pendingRecovery = null;
      _pendingRecoveryText = null;
      _setStage(AccountStage.welcome);
      return;
    }
    if (!user.emailVerified) {
      _setStage(AccountStage.needVerify);
      return;
    }
    // Ключ уже створюється чи показується — не перебиваємо.
    if (_stage == AccountStage.newKey) return;
    // Уже працюємо під цим користувачем (Firebase часто надсилає оновлення).
    if (_stage == AccountStage.ready && _readyUid == user.uid) return;
    await _resolveKey(user);
  }

  /// Визначити, чи є ключ даних. Якщо така перевірка вже триває (подія входу
  /// та явний виклик приходять майже одночасно), чекаємо на ту саму.
  Future<void> _resolveKey(AuthUser user) {
    return _resolveFuture ??=
        _doResolveKey(user).whenComplete(() => _resolveFuture = null);
  }

  Future<void> _doResolveKey(AuthUser user) async {
    final local = await keys.readDataKey(user.uid);
    if (local != null) {
      await _enterReady(user, local);
      return;
    }
    try {
      final doc = await cloud.getKeyDoc(user.uid).timeout(cloudTimeout);
      if (doc == null) {
        _beginNewKey();
      } else {
        _setStage(AccountStage.needRecoveryKey);
      }
    } catch (e) {
      AppLog.add('account: не вдалося перевірити ключ: $e');
      _setStage(AccountStage.keyCheckFailed);
    }
  }

  Future<void> _enterReady(AuthUser user, Uint8List dataKey) async {
    await sync.start(user.uid, dataKey);
    _readyUid = user.uid;
    _setStage(AccountStage.ready);
  }

  // ── Вхід і реєстрація ─────────────────────────────────────

  Future<void> register(String name, String email, String password) {
    return _run(() async {
      await auth.register(name: name, email: email, password: password);
      try {
        await auth.sendVerificationEmail();
      } catch (e) {
        AppLog.add('account: лист підтвердження не надіслано: $e');
      }
      await _onUser(auth.currentUser);
    });
  }

  Future<void> signIn(String email, String password) {
    return _run(() async {
      await auth.signIn(email: email, password: password);
      await _onUser(auth.currentUser);
    });
  }

  Future<void> sendPasswordReset(String email) {
    return _run(() => auth.sendPasswordReset(email));
  }

  Future<void> resendVerification() {
    return _run(auth.sendVerificationEmail);
  }

  /// Користувач натиснув «Я підтвердив пошту».
  Future<void> checkVerified() {
    return _run(() async {
      final u = await auth.reload();
      if (u != null && !u.emailVerified) {
        _error = 'Пошту ще не підтверджено. Відкрий лист і натисни посилання.';
        return;
      }
      await _onUser(u);
    });
  }

  Future<void> retryKeyCheck() {
    return _run(() async {
      final u = auth.currentUser;
      if (u != null) await _resolveKey(u);
    });
  }

  // ── Ключ відновлення ──────────────────────────────────────

  void _beginNewKey() {
    _pendingDataKey = crypto.newKey();
    _pendingRecovery = crypto.newKey();
    _pendingRecoveryText = encodeRecoveryKey(_pendingRecovery!);
    _regenerating = false;
    _setStage(AccountStage.newKey);
  }

  /// Новий ключ відновлення з налаштувань (дані й ключ даних лишаються).
  Future<void> beginRegenerateKey() async {
    final u = auth.currentUser;
    if (u == null) return;
    final dataKey = await keys.readDataKey(u.uid);
    if (dataKey == null) {
      _error = 'На цьому телефоні немає ключа даних. Увійди з ключем відновлення.';
      notifyListeners();
      return;
    }
    _pendingDataKey = dataKey;
    _pendingRecovery = crypto.newKey();
    _pendingRecoveryText = encodeRecoveryKey(_pendingRecovery!);
    _regenerating = true;
    _setStage(AccountStage.newKey);
  }

  /// Скасувати створення нового ключа (повернутися до роботи).
  void cancelRegenerate() {
    _pendingDataKey = null;
    _pendingRecovery = null;
    _pendingRecoveryText = null;
    _regenerating = false;
    _setStage(AccountStage.ready);
  }

  /// Користувач зберіг ключ і підтвердив це: завантажуємо зашифрований
  /// ключ даних у хмару й завершуємо.
  Future<void> confirmKeySaved() {
    return _run(() async {
      final u = auth.currentUser;
      final dataKey = _pendingDataKey;
      final recovery = _pendingRecovery;
      if (u == null || dataKey == null || recovery == null) return;

      final wrapped = await crypto.wrapDataKey(dataKey, recovery);
      // Спершу хмара, потім телефон: якщо зв'язку немає, нічого не втрачено.
      await cloud.putKeyDoc(u.uid, {
        'v': kFormatVersion,
        'env': wrapped.toJson(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }).timeout(cloudTimeout);
      await keys.writeDataKey(u.uid, dataKey);

      _pendingDataKey = null;
      _pendingRecovery = null;
      _pendingRecoveryText = null;
      _regenerating = false;
      await _enterReady(u, dataKey);
    });
  }

  /// Новий телефон: ввести ключ відновлення (текстом).
  Future<void> enterRecoveryKey(String text) {
    return _run(() async {
      final u = auth.currentUser;
      if (u == null) return;
      final recovery = decodeRecoveryKey(text);
      final doc = await cloud.getKeyDoc(u.uid).timeout(cloudTimeout);
      if (doc == null) {
        _error = 'У хмарі немає ключа цього акаунта. Створи акаунт заново.';
        return;
      }
      final env = Envelope.fromJson(Map<String, dynamic>.from(doc['env'] as Map));
      final dataKey = await crypto.unwrapDataKey(env, recovery);
      await keys.writeDataKey(u.uid, dataKey);
      await _enterReady(u, dataKey);
    });
  }

  /// «Почати знову»: видалити хмарні дані й створити нові ключі.
  Future<void> startOver() {
    return _run(() async {
      final u = auth.currentUser;
      if (u == null) return;
      await sync.stop();
      await cloud.deleteUserData(u.uid).timeout(cloudTimeout);
      await keys.deleteDataKey(u.uid);
      _beginNewKey();
    });
  }

  // ── Вихід, видалення, режим без акаунта ───────────────────

  /// Вийти з акаунта. [wipeLocal] — також стерти дані на цьому телефоні.
  Future<void> signOut({bool wipeLocal = false}) {
    return _run(() async {
      await sync.stop();
      if (wipeLocal) state.resetAllData();
      await auth.signOut();
      await _onUser(null);
    });
  }

  /// Видалити акаунт разом із хмарними даними (дані на телефоні лишаються).
  Future<void> deleteAccount(String password) {
    return _run(() async {
      final u = auth.currentUser;
      if (u == null) return;
      await auth.reauthenticate(password); // неправильний пароль — зупиняємось
      await sync.stop();
      await cloud.deleteUserData(u.uid).timeout(cloudTimeout);
      await keys.deleteDataKey(u.uid);
      await auth.deleteAccount();
      await _onUser(null);
    });
  }

  Future<void> continueWithoutAccount() async {
    await prefs.setBool(kLocalModeKey, true);
    _setStage(AccountStage.localOnly);
  }

  /// З режиму «без акаунта» повернутися до входу (з налаштувань).
  Future<void> leaveLocalMode() async {
    await prefs.setBool(kLocalModeKey, false);
    await _onUser(auth.currentUser);
  }
}
