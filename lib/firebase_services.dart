// Усе, що торкається Firebase, зібрано в цьому одному файлі.
// Його імпортує лише main.dart, тому тести (які імпортують app.dart)
// працюють без Firebase.
//
// Що тут є:
//  • FirebaseAuthService — вхід і реєстрація (пошта + пароль);
//  • FirestoreCloudStore — зашифровані дані в хмарі (Cloud Firestore);
//  • SecureKeyStore — ключ даних у захищеному сховищі Android (Keystore);
//  • FirestoreReportService — звіти про проблеми від користувачів;
//  • FirebaseCrashControl — автоматичні звіти про збої (Crashlytics);
//  • createCloudServices — збирає все докупи при запуску.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account/account_controller.dart';
import 'account/auth_service.dart';
import 'account/key_store.dart';
import 'app_config.dart';
import 'app_state.dart';
import 'diagnostics.dart';
import 'reports/report_service.dart';
import 'services.dart';
import 'sync/cloud_store.dart';
import 'sync/sync_service.dart';
import 'updates/github_fetcher.dart';
import 'updates/ota_installer.dart';
import 'updates/update_service.dart';

// ─────────────────────────────────────────────────────────────
// Вхід і реєстрація
// ─────────────────────────────────────────────────────────────

class FirebaseAuthService implements AuthService {
  FirebaseAuthService([fb.FirebaseAuth? auth]) : _auth = auth ?? fb.FirebaseAuth.instance {
    // Листи від Firebase приходитимуть українською.
    _auth.setLanguageCode('uk');
  }

  final fb.FirebaseAuth _auth;

  AuthUser? _map(fb.User? u) {
    if (u == null) return null;
    return AuthUser(
      uid: u.uid,
      email: u.email,
      name: u.displayName,
      emailVerified: u.emailVerified,
    );
  }

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> get userChanges => _auth.userChanges().map(_map);

  @override
  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      await cred.user?.reload();
      return _map(_auth.currentUser)!;
    } on fb.FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<AuthUser> signIn({required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return _map(cred.user)!;
    } on fb.FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendVerificationEmail() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } on fb.FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<AuthUser?> reload() async {
    try {
      await _auth.currentUser?.reload();
      // Правила Firestore перевіряють підтвердження пошти за «перепусткою»
      // (токеном). Оновлюємо її, щоб одразу після підтвердження все працювало.
      await _auth.currentUser?.getIdToken(true);
    } on fb.FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
    return _map(_auth.currentUser);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on fb.FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> reauthenticate(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw AuthException('no-user', 'Ти не ввійшов(ла) в акаунт.');
    }
    try {
      await user.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: password),
      );
    } on fb.FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
    } on fb.FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  /// Переклад кодів помилок Firebase на зрозумілу українську.
  AuthException _friendly(fb.FirebaseAuthException e) {
    final String text;
    switch (e.code) {
      case 'invalid-email':
        text = 'Пошту введено неправильно.';
      case 'user-disabled':
        text = 'Цей акаунт вимкнено.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        text = 'Неправильна пошта або пароль.';
      case 'email-already-in-use':
        text = 'Акаунт із такою поштою вже існує. Спробуй увійти.';
      case 'weak-password':
        text = 'Пароль надто простий. Використай щонайменше 8 символів.';
      case 'network-request-failed':
        text = 'Немає зв\'язку із сервером. Перевір інтернет.';
      case 'too-many-requests':
        text = 'Забагато спроб. Зачекай кілька хвилин і спробуй знову.';
      case 'requires-recent-login':
        text = 'Для цієї дії треба увійти знову.';
      case 'operation-not-allowed':
        text = 'Вхід за поштою вимкнено в налаштуваннях Firebase.';
      default:
        text = 'Не вдалося виконати дію (${e.code}).';
    }
    return AuthException(e.code, text);
  }
}

// ─────────────────────────────────────────────────────────────
// Хмарне сховище
// ─────────────────────────────────────────────────────────────

class FirestoreCloudStore implements CloudStore {
  FirestoreCloudStore([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _keyRef(String uid) =>
      _db.collection('users').doc(uid).collection('keys').doc('primary');

  CollectionReference<Map<String, dynamic>> _months(String uid) =>
      _db.collection('users').doc(uid).collection('months');

  @override
  Future<Map<String, dynamic>?> getKeyDoc(String uid) async {
    final snap = await _keyRef(uid).get();
    return snap.exists ? snap.data() : null;
  }

  @override
  Future<void> putKeyDoc(String uid, Map<String, dynamic> doc) => _keyRef(uid).set(doc);

  @override
  Future<void> putMonth(String uid, String month, Map<String, dynamic> doc) =>
      _months(uid).doc(month).set(doc);

  @override
  Stream<CloudEvent> watchMonths(String uid) {
    return _months(uid).snapshots(includeMetadataChanges: true).map((snap) {
      final changed = <String, Map<String, dynamic>>{};
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final doc = change.doc;
        // Власні записи, що ще не дійшли до сервера, повторно не зливаємо.
        if (doc.metadata.hasPendingWrites) continue;
        final data = doc.data();
        if (data != null) changed[doc.id] = data;
      }
      return CloudEvent(months: changed, fromCache: snap.metadata.isFromCache);
    });
  }

  @override
  Future<void> deleteUserData(String uid) async {
    final months = await _months(uid).get(const GetOptions(source: Source.server));
    var batch = _db.batch();
    var count = 0;
    for (final doc in months.docs) {
      batch.delete(doc.reference);
      count++;
      if (count == 400) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    batch.delete(_keyRef(uid));
    await batch.commit();
  }
}

// ─────────────────────────────────────────────────────────────
// Ключ даних на телефоні
// ─────────────────────────────────────────────────────────────

class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _name(String uid) => 'data_key_$uid';

  @override
  Future<Uint8List?> readDataKey(String uid) async {
    final text = await _storage.read(key: _name(uid));
    if (text == null) return null;
    try {
      final bytes = base64Decode(text);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeDataKey(String uid, Uint8List key) =>
      _storage.write(key: _name(uid), value: base64Encode(key));

  @override
  Future<void> deleteDataKey(String uid) => _storage.delete(key: _name(uid));
}

// ─────────────────────────────────────────────────────────────
// Звіти про проблеми
// ─────────────────────────────────────────────────────────────

class FirestoreReportService implements ReportService {
  FirestoreReportService({
    required this.appVersion,
    required this.device,
    FirebaseFirestore? db,
    fb.FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? fb.FirebaseAuth.instance;

  final String appVersion;
  final String device;
  final FirebaseFirestore _db;
  final fb.FirebaseAuth _auth;

  @override
  Future<void> send(ReportDraft draft) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Щоб надіслати звіт, потрібно ввійти в акаунт');
    }
    final payload = buildReportPayload(
      draft: draft,
      appVersion: appVersion,
      device: device,
      email: user.email ?? '',
      uid: user.uid,
      logLines: AppLog.tail(40),
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await _db.collection('reports').doc().set(payload).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // Немає зв'язку: Firestore збереже звіт у черзі й надішле, щойно з'явиться інтернет.
      AppLog.add('report: звіт у черзі (немає зв\'язку)');
    }
  }

  @override
  Stream<List<ReportEntry>> watchAll() {
    return _db
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) {
      return [
        for (final doc in snap.docs)
          ReportEntry(
            id: doc.id,
            category: '${doc.data()['category'] ?? 'other'}',
            text: '${doc.data()['text'] ?? ''}',
            appVersion: '${doc.data()['appVersion'] ?? ''}',
            device: '${doc.data()['device'] ?? ''}',
            email: '${doc.data()['email'] ?? ''}',
            log: '${doc.data()['log'] ?? ''}',
            createdAt: _toDate(doc.data()['createdAt']),
          ),
      ];
    });
  }

  DateTime? _toDate(Object? v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  @override
  Future<void> delete(String id) => _db.collection('reports').doc(id).delete();
}

// ─────────────────────────────────────────────────────────────
// Автоматичні звіти про збої
// ─────────────────────────────────────────────────────────────

const String kCrashEnabledKey = 'crash_reports_enabled_v1';

class FirebaseCrashControl implements CrashControl {
  FirebaseCrashControl(this._prefs);

  final SharedPreferences _prefs;

  @override
  bool get enabled => _prefs.getBool(kCrashEnabledKey) ?? true;

  @override
  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(kCrashEnabledKey, value);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(value);
  }
}

// ─────────────────────────────────────────────────────────────
// Збірка всіх сервісів
// ─────────────────────────────────────────────────────────────

/// Запускає Firebase й збирає сервіси. Якщо Firebase не налаштовано
/// (немає google-services.json), кидає виняток — тоді main.dart запустить
/// додаток у локальному режимі.
Future<AppServices> createCloudServices(SharedPreferences prefs, AppState state) async {
  await Firebase.initializeApp();

  // Автоматичні звіти про збої: ловимо помилки Flutter і помилки поза ним.
  // Якщо Crashlytics не запустився, це не повинно ламати вхід в акаунт.
  final crash = FirebaseCrashControl(prefs);
  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(crash.enabled);
    FlutterError.onError = (details) {
      AppLog.add('flutter: ${details.exceptionAsString()}');
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.add('error: $error');
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    AppLog.add('crashlytics: не запустився: $e');
  }

  var appVersion = '';
  var build = 0;
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
    build = int.tryParse(info.buildNumber) ?? 0;
  } catch (e) {
    AppLog.add('версія: не вдалося прочитати: $e');
  }
  final versionText = '$appVersion ($build)';
  final device = await _deviceDescription();

  final cloud = FirestoreCloudStore();
  final sync = SyncService(state: state, cloud: cloud);
  final account = AccountController(
    auth: FirebaseAuthService(),
    cloud: cloud,
    keys: SecureKeyStore(),
    sync: sync,
    state: state,
    prefs: prefs,
  );
  final updates = UpdateService(
    currentBuild: build,
    currentVersion: appVersion,
    fetcher: githubLatestRelease(kGithubOwner, kGithubRepo),
    installer: OtaApkInstaller(),
  );

  final services = AppServices(
    account: account,
    sync: sync,
    updates: updates,
    reports: FirestoreReportService(appVersion: versionText, device: device),
    crash: crash,
    adminUid: kAdminUid,
    currentVersion: versionText,
    openUrl: (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    justUpdatedFrom: detectJustUpdated(prefs, build),
  );

  unawaited(account.init());
  unawaited(updates.check());
  unawaited(_setupPush(services));
  AppLog.add('start: версія $versionText, $device');
  return services;
}

Future<String> _deviceDescription() async {
  try {
    final a = await DeviceInfoPlugin().androidInfo;
    return '${a.manufacturer} ${a.model}, Android ${a.version.release} (SDK ${a.version.sdkInt})';
  } catch (_) {
    return 'невідомий пристрій';
  }
}

/// Сповіщення про оновлення: підписка на тему, обробка натискань.
Future<void> _setupPush(AppServices services) async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    await messaging.subscribeToTopic(kUpdatesTopic);

    // Додаток було закрито, і його відкрили натиском на сповіщення.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _onPush(services);

    // Додаток був у фоні, і його відкрили натиском на сповіщення.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _onPush(services));

    // Додаток відкритий саме зараз: просто перевіряємо оновлення.
    FirebaseMessaging.onMessage.listen((_) => services.updates?.check());
  } catch (e) {
    AppLog.add('push: не вдалося налаштувати сповіщення: $e');
  }
}

void _onPush(AppServices services) {
  services.updates?.check();
  services.openUpdateSignal.request();
}
