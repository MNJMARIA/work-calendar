// Імітації «зовнішнього світу» для тестів: вхід, хмара, сховище ключів,
// інсталятор оновлень, звіти. Так тести не потребують Firebase чи інтернету.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_calendar/account/account_controller.dart';
import 'package:work_calendar/account/auth_service.dart';
import 'package:work_calendar/account/key_store.dart';
import 'package:work_calendar/app_state.dart';
import 'package:work_calendar/reports/report_service.dart';
import 'package:work_calendar/services.dart';
import 'package:work_calendar/sync/cloud_store.dart';
import 'package:work_calendar/sync/sync_service.dart';
import 'package:work_calendar/updates/update_service.dart';

/// Дати спливають у тестах швидко: даємо подіям час «відпрацювати».
Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

// ── Вхід ────────────────────────────────────────────────────

class _Account {
  _Account(this.uid, this.email, this.password, this.name, this.verified);

  final String uid;
  final String email;
  final String password;
  final String name;
  bool verified;
}

class FakeAuthService implements AuthService {
  final Map<String, _Account> _accounts = {};
  final StreamController<AuthUser?> _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  int _counter = 0;

  int verificationsSent = 0;
  int resetsSent = 0;

  AuthUser _toUser(_Account a) =>
      AuthUser(uid: a.uid, email: a.email, name: a.name, emailVerified: a.verified);

  _Account? get _current {
    final u = _user;
    if (u == null) return null;
    for (final a in _accounts.values) {
      if (a.uid == u.uid) return a;
    }
    return null;
  }

  /// Створити акаунт «заздалегідь» (без входу).
  String addAccount({
    String email = 'olena@example.com',
    String password = 'password123',
    String name = 'Олена',
    bool verified = true,
  }) {
    final uid = 'uid-${++_counter}';
    _accounts[email.toLowerCase()] = _Account(uid, email.toLowerCase(), password, name, verified);
    return uid;
  }

  /// Користувач натиснув посилання в листі.
  void markVerified() => _current?.verified = true;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get userChanges => _changes.stream;

  void _publish(AuthUser? u) {
    _user = u;
    _changes.add(u);
  }

  @override
  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final key = email.toLowerCase();
    if (_accounts.containsKey(key)) {
      throw AuthException('email-already-in-use', 'Акаунт із такою поштою вже існує. Спробуй увійти.');
    }
    addAccount(email: key, password: password, name: name, verified: false);
    final user = _toUser(_accounts[key]!);
    _publish(user);
    return user;
  }

  @override
  Future<AuthUser> signIn({required String email, required String password}) async {
    final a = _accounts[email.toLowerCase()];
    if (a == null || a.password != password) {
      throw AuthException('invalid-credential', 'Неправильна пошта або пароль.');
    }
    final user = _toUser(a);
    _publish(user);
    return user;
  }

  @override
  Future<void> signOut() async => _publish(null);

  @override
  Future<void> sendVerificationEmail() async => verificationsSent++;

  @override
  Future<AuthUser?> reload() async {
    final a = _current;
    if (a == null) return null;
    final user = _toUser(a);
    _publish(user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async => resetsSent++;

  @override
  Future<void> reauthenticate(String password) async {
    final a = _current;
    if (a == null || a.password != password) {
      throw AuthException('wrong-password', 'Неправильна пошта або пароль.');
    }
  }

  @override
  Future<void> deleteAccount() async {
    final a = _current;
    if (a != null) _accounts.remove(a.email);
    _publish(null);
  }
}

// ── Хмара ───────────────────────────────────────────────────

class MemoryCloudStore implements CloudStore {
  final Map<String, Map<String, dynamic>> keyDocs = {};
  final Map<String, Map<String, Map<String, dynamic>>> months = {};
  final Map<String, List<StreamController<CloudEvent>>> _watchers = {};

  /// Імітація «немає зв'язку»: читання ключа кидає помилку.
  bool failKeyReads = false;

  /// Запис місяця кидає помилку.
  bool failPuts = false;

  /// Запис місяця «зависає» (як без інтернету).
  bool hangPuts = false;

  int putCount = 0;

  @override
  Future<Map<String, dynamic>?> getKeyDoc(String uid) async {
    if (failKeyReads) throw Exception('offline');
    return keyDocs[uid];
  }

  @override
  Future<void> putKeyDoc(String uid, Map<String, dynamic> doc) async {
    keyDocs[uid] = Map<String, dynamic>.from(doc);
  }

  @override
  Future<void> putMonth(String uid, String month, Map<String, dynamic> doc) async {
    if (hangPuts) return Completer<void>().future;
    if (failPuts) throw Exception('write failed');
    putCount++;
    final copy = Map<String, dynamic>.from(doc);
    months.putIfAbsent(uid, () => {})[month] = copy;
    for (final c in List.of(_watchers[uid] ?? const <StreamController<CloudEvent>>[])) {
      c.add(CloudEvent(months: {month: copy}, fromCache: false));
    }
  }

  @override
  Stream<CloudEvent> watchMonths(String uid) {
    late StreamController<CloudEvent> c;
    c = StreamController<CloudEvent>(
      onListen: () {
        _watchers.putIfAbsent(uid, () => []).add(c);
        c.add(CloudEvent(months: Map.of(months[uid] ?? {}), fromCache: false));
      },
      onCancel: () {
        _watchers[uid]?.remove(c);
      },
    );
    return c.stream;
  }

  @override
  Future<void> deleteUserData(String uid) async {
    months.remove(uid);
    keyDocs.remove(uid);
  }
}

// ── Оновлення ───────────────────────────────────────────────

class FakeInstaller implements ApkInstaller {
  FakeInstaller(this.events);

  final List<InstallProgress> events;
  String? lastUrl;
  String? lastSha;

  @override
  Stream<InstallProgress> install(String url, {String? sha256}) {
    lastUrl = url;
    lastSha = sha256;
    return Stream.fromIterable(events);
  }
}

/// JSON релізу у форматі GitHub API.
Map<String, dynamic> releaseJson({
  int build = 12,
  String version = '0.5.0',
  String notes = 'Додано таймер',
  String? sha =
  'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789',
}) {
  return {
    'tag_name': 'b$build',
    'name': 'Версія $version ($build)',
    'html_url': 'https://github.com/o/r/releases/tag/b$build',
    'body': sha == null ? notes : '$notes\nSHA-256: $sha',
    'assets': [
      {
        'name': 'work-calendar.apk',
        'browser_download_url': 'https://github.com/o/r/releases/download/b$build/work-calendar.apk',
      },
    ],
  };
}

// ── Звіти ───────────────────────────────────────────────────

class FakeReportService implements ReportService {
  final List<ReportDraft> sent = [];
  final List<ReportEntry> entries = [];
  final List<String> deleted = [];
  bool fail = false;

  @override
  Future<void> send(ReportDraft draft) async {
    if (fail) throw StateError('offline');
    sent.add(draft);
  }

  @override
  Stream<List<ReportEntry>> watchAll() => Stream.value(List.of(entries));

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

class FakeCrash implements CrashControl {
  FakeCrash([this._enabled = true]);

  bool _enabled;

  @override
  bool get enabled => _enabled;

  @override
  Future<void> setEnabled(bool value) async => _enabled = value;
}

// ── Збірка «телефона» ───────────────────────────────────────

/// Один «телефон»: стан, синхронізація й акаунт на спільних імітаціях.
class Phone {
  Phone._();

  late final SharedPreferences prefs;
  late final AppState state;
  late final SyncService sync;
  late final AccountController account;
  late FakeAuthService auth;
  late MemoryCloudStore cloud;
  late MemoryKeyStore keys;
  DateTime clockTime = DateTime(2026, 10, 24, 10);

  static Future<Phone> create({
    FakeAuthService? auth,
    MemoryCloudStore? cloud,
    MemoryKeyStore? keys,
    Map<String, Object> prefsData = const {},
  }) async {
    final p = Phone._();
    SharedPreferences.setMockInitialValues(prefsData);
    p.prefs = await SharedPreferences.getInstance();
    p.auth = auth ?? FakeAuthService();
    p.cloud = cloud ?? MemoryCloudStore();
    p.keys = keys ?? MemoryKeyStore();
    p.state = AppState(p.prefs, clock: () => p.clockTime);
    p.sync = SyncService(
      state: p.state,
      cloud: p.cloud,
      debounce: const Duration(milliseconds: 5),
      putTimeout: const Duration(milliseconds: 50),
    );
    p.account = AccountController(
      auth: p.auth,
      cloud: p.cloud,
      keys: p.keys,
      sync: p.sync,
      state: p.state,
      prefs: p.prefs,
    );
    return p;
  }

  /// Пройти реєстрацію до кінця: акаунт, пошта підтверджена, ключ збережено.
  /// Повертає текст ключа відновлення.
  Future<String> registerAndFinish({
    String email = 'olena@example.com',
    String password = 'password123',
    Future<void> Function()? settleFn,
  }) async {
    await account.register('Олена', email, password);
    auth.markVerified();
    await account.checkVerified();
    final recovery = account.pendingRecoveryText!;
    await account.confirmKeySaved();
    await (settleFn ?? settle)();
    return recovery;
  }
}
