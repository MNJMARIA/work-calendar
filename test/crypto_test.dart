// Тести шифрування: ключі, конверти, ключ відновлення.
// Запуск: flutter test test/crypto_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/crypto/crypto_service.dart';

void main() {
  final crypto = CryptoService();

  group('Ключі', () {
    test('новий ключ має 32 байти і щоразу інший', () {
      final a = crypto.newKey();
      final b = crypto.newKey();
      expect(a.length, 32);
      expect(a, isNot(equals(b)));
    });
  });

  group('Шифрування', () {
    test('розшифрування повертає те саме', () async {
      final key = crypto.newKey();
      final env = await crypto.encryptJson({'a': 1, 'текст': 'привіт'}, key);
      final back = await crypto.decryptJson(env, key);
      expect(back, {'a': 1, 'текст': 'привіт'});
    });

    test('шифротекст не містить відкритого тексту', () async {
      final key = crypto.newKey();
      final env = await crypto.encrypt(utf8.encode('СЕКРЕТНИЙ-ТЕКСТ'), key);
      expect(utf8.decode(env.cipherText, allowMalformed: true), isNot(contains('СЕКРЕТНИЙ')));
    });

    test('щоразу різне одноразове число', () async {
      final key = crypto.newKey();
      final a = await crypto.encrypt([1, 2, 3], key);
      final b = await crypto.encrypt([1, 2, 3], key);
      expect(a.nonce, isNot(equals(b.nonce)));
    });

    test('неправильний ключ → CryptoException', () async {
      final env = await crypto.encrypt([1, 2, 3], crypto.newKey());
      expect(
            () => crypto.decrypt(env, crypto.newKey()),
        throwsA(isA<CryptoException>()),
      );
    });

    test('змінений шифротекст виявляється', () async {
      final key = crypto.newKey();
      final env = await crypto.encrypt(utf8.encode('дані'), key);
      final tampered = Uint8List.fromList(env.cipherText)..[0] ^= 0xFF;
      final bad = Envelope(
        version: env.version,
        nonce: env.nonce,
        cipherText: tampered,
        mac: env.mac,
      );
      expect(() => crypto.decrypt(bad, key), throwsA(isA<CryptoException>()));
    });

    test('інша версія формату відхиляється', () async {
      final key = crypto.newKey();
      final env = await crypto.encrypt([1], key);
      final future = Envelope(
        version: 99,
        nonce: env.nonce,
        cipherText: env.cipherText,
        mac: env.mac,
      );
      expect(() => crypto.decrypt(future, key), throwsA(isA<CryptoException>()));
    });

    test('ключ неправильної довжини відхиляється', () async {
      expect(
            () => crypto.encrypt([1], Uint8List(16)),
        throwsA(isA<CryptoException>()),
      );
    });

    test('конверт проходить через JSON', () async {
      final key = crypto.newKey();
      final env = await crypto.encryptJson({'x': 5}, key);
      final restored = Envelope.fromJson(jsonDecode(jsonEncode(env.toJson())) as Map<String, dynamic>);
      expect(await crypto.decryptJson(restored, key), {'x': 5});
    });

    test('пошкоджений JSON конверта → CryptoException', () {
      expect(() => Envelope.fromJson({'v': 1}), throwsA(isA<CryptoException>()));
    });
  });

  group('Прив\'язка місяця', () {
    test('місяць не можна підмінити іншим місяцем', () async {
      final key = crypto.newKey();
      final env = await crypto.encryptMonth('u1', '2026-10', {'days': {}}, key);
      expect(await crypto.decryptMonth('u1', '2026-10', env, key), {'days': {}});
      expect(
            () => crypto.decryptMonth('u1', '2026-11', env, key),
        throwsA(isA<CryptoException>()),
      );
    });

    test('місяць іншого користувача не розшифровується', () async {
      final key = crypto.newKey();
      final env = await crypto.encryptMonth('u1', '2026-10', {'days': {}}, key);
      expect(
            () => crypto.decryptMonth('u2', '2026-10', env, key),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  group('Ключ даних під ключем відновлення', () {
    test('загортання й розгортання', () async {
      final dataKey = crypto.newKey();
      final recovery = crypto.newKey();
      final wrapped = await crypto.wrapDataKey(dataKey, recovery);
      expect(await crypto.unwrapDataKey(wrapped, recovery), dataKey);
    });

    test('з чужим ключем відновлення не відкривається', () async {
      final wrapped = await crypto.wrapDataKey(crypto.newKey(), crypto.newKey());
      expect(
            () => crypto.unwrapDataKey(wrapped, crypto.newKey()),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  group('Ключ відновлення текстом', () {
    test('нульовий ключ має відомий вигляд', () {
      expect(
        encodeRecoveryKey(Uint8List(32)),
        '0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-00G1',
      );
    });

    test('ключ 0..31 має відомий вигляд', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(
        encodeRecoveryKey(key),
        '000G-40R4-0M30-E209-185G-R38E-1W81-24GK-2GAH-C5RR-34D1-P70X-3RFG-2NQH',
      );
    });

    test('кругова перевірка на випадкових ключах', () {
      for (var i = 0; i < 20; i++) {
        final key = crypto.newKey();
        expect(decodeRecoveryKey(encodeRecoveryKey(key)), key);
      }
    });

    test('14 груп по 4 символи', () {
      final groups = recoveryKeyGroups(encodeRecoveryKey(crypto.newKey()));
      expect(groups.length, 14);
      expect(groups.every((g) => g.length == 4), isTrue);
    });

    test('регістр, пробіли й дефіси не важливі', () {
      final key = crypto.newKey();
      final text = encodeRecoveryKey(key).toLowerCase().replaceAll('-', '  ');
      expect(decodeRecoveryKey(text), key);
    });

    test('O читається як 0, I і L як 1', () {
      final key = Uint8List(32);
      final text = encodeRecoveryKey(key).replaceAll('0', 'O').replaceAll('G1', 'GL');
      expect(decodeRecoveryKey(text), key);
    });

    test('помилка в одному символі виявляється контрольною сумою', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final text = encodeRecoveryKey(key); // починається з «0»
      final broken = 'A${text.substring(1)}';
      expect(() => decodeRecoveryKey(broken), throwsA(isA<CryptoException>()));
    });

    test('занадто короткий ключ відхиляється', () {
      expect(() => decodeRecoveryKey('ABCD-EFGH'), throwsA(isA<CryptoException>()));
    });

    test('недопустимий символ відхиляється', () {
      final text = encodeRecoveryKey(Uint8List(32));
      final broken = '!' + text.substring(1);
      expect(() => decodeRecoveryKey(broken), throwsA(isA<CryptoException>()));
    });

    test('ключ не 32 байти не кодується', () {
      expect(() => encodeRecoveryKey(Uint8List(10)), throwsA(isA<CryptoException>()));
    });
  });
}
