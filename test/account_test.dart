// Тести акаунта: реєстрація, пошта, ключ відновлення, новий телефон,
// «почати знову», видалення. Усе на імітаціях (без Firebase).
// Запуск: flutter test test/account_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/account/account_controller.dart';
import 'package:work_calendar/crypto/crypto_service.dart';

import 'fakes.dart';

void main() {
  final crypto = CryptoService();
  final day = DateTime(2026, 10, 20);

  /// Новий «телефон» із запущеним акаунтом. [autoDispose] = false, якщо
  /// тест сам вимкне його (щоб контролер не слухав вхід на іншому телефоні).
  Future<Phone> fresh({
    Map<String, Object> prefsData = const {},
    bool autoDispose = true,
  }) async {
    final p = await Phone.create(prefsData: prefsData);
    if (autoDispose) {
      addTearDown(() async {
        await p.sync.stop();
        p.account.dispose();
      });
    }
    await p.account.init();
    return p;
  }

  group('Запуск', () {
    test('без акаунта показується вхід', () async {
      final p = await fresh();
      expect(p.account.stage, AccountStage.welcome);
      expect(p.account.signedIn, isFalse);
    });

    test('режим «без акаунта» запам\'ятовується', () async {
      final p = await fresh(prefsData: {kLocalModeKey: true});
      expect(p.account.stage, AccountStage.localOnly);
    });

    test('«Продовжити без акаунта» зберігає вибір', () async {
      final p = await fresh();
      await p.account.continueWithoutAccount();
      expect(p.account.stage, AccountStage.localOnly);
      expect(p.prefs.getBool(kLocalModeKey), isTrue);
    });

    test('з режиму «без акаунта» можна повернутися до входу', () async {
      final p = await fresh(prefsData: {kLocalModeKey: true});
      await p.account.leaveLocalMode();
      expect(p.account.stage, AccountStage.welcome);
      expect(p.prefs.getBool(kLocalModeKey), isFalse);
    });
  });

  group('Реєстрація й пошта', () {
    test('після реєстрації треба підтвердити пошту', () async {
      final p = await fresh();
      await p.account.register('Олена', 'olena@example.com', 'password123');
      await settle();
      expect(p.account.stage, AccountStage.needVerify);
      expect(p.auth.verificationsSent, 1);
      expect(p.account.user?.email, 'olena@example.com');
      expect(p.account.error, isNull);
      expect(p.account.busy, isFalse);
    });

    test('пошта вже зайнята → зрозуміла помилка', () async {
      final p = await fresh();
      p.auth.addAccount(email: 'olena@example.com');
      await p.account.register('Олена', 'olena@example.com', 'password123');
      expect(p.account.stage, AccountStage.welcome);
      expect(p.account.error, contains('вже існує'));
    });

    test('неправильний пароль → зрозуміла помилка', () async {
      final p = await fresh();
      p.auth.addAccount();
      await p.account.signIn('olena@example.com', 'wrong-password');
      expect(p.account.stage, AccountStage.welcome);
      expect(p.account.error, 'Неправильна пошта або пароль.');
    });

    test('помилку можна прибрати', () async {
      final p = await fresh();
      await p.account.signIn('nobody@example.com', 'x');
      expect(p.account.error, isNotNull);
      p.account.clearError();
      expect(p.account.error, isNull);
    });

    test('поки пошту не підтверджено — лишаємось на очікуванні', () async {
      final p = await fresh();
      await p.account.register('Олена', 'olena@example.com', 'password123');
      await p.account.checkVerified();
      expect(p.account.stage, AccountStage.needVerify);
      expect(p.account.error, contains('ще не підтверджено'));
    });

    test('лист можна надіслати ще раз', () async {
      final p = await fresh();
      await p.account.register('Олена', 'olena@example.com', 'password123');
      await p.account.resendVerification();
      expect(p.auth.verificationsSent, 2);
    });

    test('лист для відновлення пароля', () async {
      final p = await fresh();
      await p.account.sendPasswordReset('olena@example.com');
      expect(p.auth.resetsSent, 1);
      expect(p.account.error, isNull);
    });
  });

  group('Ключ відновлення (перший вхід)', () {
    test('після підтвердження пошти показується новий ключ', () async {
      final p = await fresh();
      await p.account.register('Олена', 'olena@example.com', 'password123');
      p.auth.markVerified();
      await p.account.checkVerified();
      expect(p.account.stage, AccountStage.newKey);
      expect(p.account.regenerating, isFalse);
      final text = p.account.pendingRecoveryText!;
      expect(decodeRecoveryKey(text).length, 32);
      // Ключ даних ще не збережено: спершу користувач має зберегти ключ відновлення.
      expect(await p.keys.readDataKey(p.account.user!.uid), isNull);
      expect(p.cloud.keyDocs, isEmpty);
    });

    test('підтвердження ключа завершує реєстрацію', () async {
      final p = await fresh();
      final recovery = await p.registerAndFinish();
      final uid = p.account.user!.uid;
      expect(p.account.stage, AccountStage.ready);
      expect(p.account.signedIn, isTrue);
      expect(p.account.pendingRecoveryText, isNull);
      expect(p.sync.running, isTrue);

      final dataKey = (await p.keys.readDataKey(uid))!;
      expect(dataKey.length, 32);

      // У хмарі лежить ключ даних, зашифрований ключем відновлення.
      final env = Envelope.fromJson(Map<String, dynamic>.from(p.cloud.keyDocs[uid]!['env'] as Map));
      expect(await crypto.unwrapDataKey(env, decodeRecoveryKey(recovery)), dataKey);
    });

    test('якщо хмара не прийняла ключ, він не вважається збереженим', () async {
      final p = await Phone.create(cloud: _FailingKeyCloud());
      addTearDown(() async {
        await p.sync.stop();
        p.account.dispose();
      });
      await p.account.init();
      await p.account.register('Олена', 'olena@example.com', 'password123');
      p.auth.markVerified();
      await p.account.checkVerified();
      expect(p.account.stage, AccountStage.newKey);

      await p.account.confirmKeySaved();
      expect(p.account.stage, AccountStage.newKey);
      expect(p.account.error, isNotNull);
      expect(await p.keys.readDataKey(p.account.user!.uid), isNull);
      expect(p.sync.running, isFalse);
    });
  });

  group('Повторний вхід і вихід', () {
    test('вихід зупиняє синхронізацію', () async {
      final p = await fresh();
      await p.registerAndFinish();
      await p.account.signOut();
      await settle();
      expect(p.account.stage, AccountStage.welcome);
      expect(p.sync.running, isFalse);
    });

    test('повторний вхід на тому ж телефоні не просить ключ', () async {
      final p = await fresh();
      await p.registerAndFinish();
      await p.account.signOut();
      await p.account.signIn('olena@example.com', 'password123');
      await settle();
      expect(p.account.stage, AccountStage.ready);
      expect(p.sync.running, isTrue);
    });

    test('вихід зі стиранням видаляє дані з телефона', () async {
      final p = await fresh();
      await p.registerAndFinish();
      p.state.setShifts([day], 720);
      await p.account.signOut(wipeLocal: true);
      expect(p.state.shifts, isEmpty);
    });

    test('вихід без стирання лишає дані', () async {
      final p = await fresh();
      await p.registerAndFinish();
      p.state.setShifts([day], 720);
      await p.account.signOut();
      expect(p.state.shifts, {'2026-10-20': 720});
    });

    test('вихід, зроблений ззовні, теж зупиняє синхронізацію', () async {
      final p = await fresh();
      await p.registerAndFinish();
      await p.auth.signOut();
      await settle();
      expect(p.account.stage, AccountStage.welcome);
      expect(p.sync.running, isFalse);
    });

    test('запуск додатка з уже ввійденим користувачем одразу готовий', () async {
      final first = await fresh(autoDispose: false);
      await first.registerAndFinish();
      first.state.setShifts([day], 720);
      await first.sync.syncNow();

      // «Перезапуск»: той самий акаунт, ключ і хмара, новий контролер.
      final again = await Phone.create(auth: first.auth, cloud: first.cloud, keys: first.keys);
      addTearDown(() async {
        await again.sync.stop();
        again.account.dispose();
      });
      await first.sync.stop();
      first.account.dispose();
      await again.account.init();
      await settle();
      expect(again.account.stage, AccountStage.ready);
      expect(again.state.shifts['2026-10-20'], 720);
    });
  });

  group('Новий телефон', () {
    late Phone first;
    late String recovery;

    setUp(() async {
      first = await fresh(autoDispose: false);
      recovery = await first.registerAndFinish();
      first.state.setShifts([day], 720);
      await first.sync.syncNow();
      await first.account.signOut();
      first.account.dispose();
    });

    Future<Phone> secondPhone() async {
      final p = await Phone.create(auth: first.auth, cloud: first.cloud);
      addTearDown(() async {
        await p.sync.stop();
        p.account.dispose();
      });
      await p.account.init();
      return p;
    }

    test('без ключа на телефоні просить ключ відновлення', () async {
      final p = await secondPhone();
      await p.account.signIn('olena@example.com', 'password123');
      await settle();
      expect(p.account.stage, AccountStage.needRecoveryKey);
    });

    test('правильний ключ повертає дані', () async {
      final p = await secondPhone();
      await p.account.signIn('olena@example.com', 'password123');
      await p.account.enterRecoveryKey(recovery);
      await settle();
      expect(p.account.stage, AccountStage.ready);
      expect(p.state.shifts['2026-10-20'], 720);
      expect(await p.keys.readDataKey(p.account.user!.uid), isNotNull);
    });

    test('ключ можна ввести у вільному записі', () async {
      final p = await secondPhone();
      await p.account.signIn('olena@example.com', 'password123');
      await p.account.enterRecoveryKey(recovery.toLowerCase().replaceAll('-', ' '));
      expect(p.account.stage, AccountStage.ready);
    });

    test('чужий ключ — зрозуміла помилка, дані не відкриваються', () async {
      final p = await secondPhone();
      await p.account.signIn('olena@example.com', 'password123');
      await p.account.enterRecoveryKey(encodeRecoveryKey(crypto.newKey()));
      expect(p.account.stage, AccountStage.needRecoveryKey);
      expect(p.account.error, 'Неправильний ключ або дані пошкоджено');
      expect(p.state.shifts, isEmpty);
    });

    test('ключ із помилкою друку — помилка контрольної суми', () async {
      final p = await secondPhone();
      await p.account.signIn('olena@example.com', 'password123');
      await p.account.enterRecoveryKey('ABCD-EFGH');
      expect(p.account.stage, AccountStage.needRecoveryKey);
      expect(p.account.error, contains('56'));
    });

    test('«Почати знову» видаляє хмарні дані й створює новий ключ', () async {
      final p = await secondPhone();
      await p.account.signIn('olena@example.com', 'password123');
      await p.account.startOver();
      expect(p.account.stage, AccountStage.newKey);
      expect(p.cloud.months, isEmpty);
      expect(p.cloud.keyDocs, isEmpty);

      await p.account.confirmKeySaved();
      await settle();
      expect(p.account.stage, AccountStage.ready);
      expect(p.cloud.keyDocs, isNotEmpty);
      expect(p.state.shifts, isEmpty);
    });

    test('без зв\'язку: окремий екран і повторна спроба', () async {
      final p = await secondPhone();
      p.cloud.failKeyReads = true;
      await p.account.signIn('olena@example.com', 'password123');
      await settle();
      expect(p.account.stage, AccountStage.keyCheckFailed);

      p.cloud.failKeyReads = false;
      await p.account.retryKeyCheck();
      await settle();
      expect(p.account.stage, AccountStage.needRecoveryKey);
    });
  });

  group('Новий ключ відновлення з налаштувань', () {
    test('старий ключ перестає працювати, новий працює', () async {
      final p = await fresh();
      final oldKey = await p.registerAndFinish();
      final uid = p.account.user!.uid;
      final dataKey = (await p.keys.readDataKey(uid))!;

      await p.account.beginRegenerateKey();
      expect(p.account.stage, AccountStage.newKey);
      expect(p.account.regenerating, isTrue);
      final newKey = p.account.pendingRecoveryText!;
      expect(newKey, isNot(oldKey));

      await p.account.confirmKeySaved();
      await settle();
      expect(p.account.stage, AccountStage.ready);

      final env = Envelope.fromJson(Map<String, dynamic>.from(p.cloud.keyDocs[uid]!['env'] as Map));
      expect(await crypto.unwrapDataKey(env, decodeRecoveryKey(newKey)), dataKey);
      expect(
            () => crypto.unwrapDataKey(env, decodeRecoveryKey(oldKey)),
        throwsA(isA<CryptoException>()),
      );
    });

    test('скасування лишає старий ключ', () async {
      final p = await fresh();
      final oldKey = await p.registerAndFinish();
      final uid = p.account.user!.uid;
      final before = Map.of(p.cloud.keyDocs[uid]!);

      await p.account.beginRegenerateKey();
      p.account.cancelRegenerate();
      expect(p.account.stage, AccountStage.ready);
      expect(p.account.pendingRecoveryText, isNull);
      expect(p.cloud.keyDocs[uid], before);

      final env = Envelope.fromJson(Map<String, dynamic>.from(before['env'] as Map));
      expect(await crypto.unwrapDataKey(env, decodeRecoveryKey(oldKey)), isNotNull);
    });
  });

  group('Видалення акаунта', () {
    test('неправильний пароль нічого не видаляє', () async {
      final p = await fresh();
      await p.registerAndFinish();
      final uid = p.account.user!.uid;
      await p.account.deleteAccount('wrong');
      expect(p.account.error, isNotNull);
      expect(p.account.stage, AccountStage.ready);
      expect(p.cloud.keyDocs[uid], isNotNull);
    });

    test('правильний пароль видаляє хмарні дані, ключ і акаунт', () async {
      final p = await fresh();
      await p.registerAndFinish();
      final uid = p.account.user!.uid;
      p.state.setShifts([day], 720);
      await p.sync.syncNow();

      await p.account.deleteAccount('password123');
      await settle();
      expect(p.account.stage, AccountStage.welcome);
      expect(p.cloud.keyDocs, isEmpty);
      expect(p.cloud.months, isEmpty);
      expect(await p.keys.readDataKey(uid), isNull);
      // Дані на телефоні лишаються.
      expect(p.state.shifts['2026-10-20'], 720);

      await p.account.signIn('olena@example.com', 'password123');
      expect(p.account.error, 'Неправильна пошта або пароль.');
    });
  });
}

/// Хмара, яка не дає записати ключ (як без інтернету).
class _FailingKeyCloud extends MemoryCloudStore {
  @override
  Future<void> putKeyDoc(String uid, Map<String, dynamic> doc) async {
    throw Exception('offline');
  }
}
