// Шифрування даних (наскрізне): окремий модуль без мережі й без Flutter.
//
// Схема з ТЗ (розділ 9):
//  • на телефоні є випадковий «ключ даних» (32 байти);
//  • користувач отримує «ключ відновлення» (32 байти у вигляді тексту);
//  • хмара зберігає лише ключ даних, зашифрований ключем відновлення,
//    і зашифровані місяці. Без ключа відновлення їх не прочитати нікому.
// Алгоритм: AES-256-GCM (бібліотека `cryptography`, власних алгоритмів немає).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Версія формату зашифрованого запису. Збільшується, якщо формат зміниться.
const int kFormatVersion = 1;

/// Помилка шифрування (неправильний ключ, пошкоджені дані, нова версія формату).
class CryptoException implements Exception {
  CryptoException(this.message);

  final String message;

  @override
  String toString() => 'CryptoException: $message';
}

/// Зашифрований «конверт»: версія + одноразове число + шифротекст + мітка.
class Envelope {
  const Envelope({
    required this.version,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final int version;
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  Map<String, dynamic> toJson() => {
    'v': version,
    'n': base64Encode(nonce),
    'c': base64Encode(cipherText),
    'm': base64Encode(mac),
  };

  factory Envelope.fromJson(Map<String, dynamic> json) {
    try {
      return Envelope(
        version: json['v'] as int,
        nonce: base64Decode(json['n'] as String),
        cipherText: base64Decode(json['c'] as String),
        mac: base64Decode(json['m'] as String),
      );
    } catch (_) {
      throw CryptoException('Пошкоджений конверт даних');
    }
  }
}

/// Абетка Crockford (без I, L, O, U): зручна для ручного введення.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

class CryptoService {
  CryptoService({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final AesGcm _algo = AesGcm.with256bits();

  // ── Випадкові байти й ключі ───────────────────────────────

  Uint8List randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  /// Новий випадковий ключ (32 байти = 256 біт).
  Uint8List newKey() => randomBytes(32);

  // ── Шифрування й розшифрування ────────────────────────────

  /// Зашифрувати [plain] ключем [key]. [aad] — «прив'язка» до місця
  /// (шлях запису), щоб зашифрований запис не можна було підмінити іншим.
  Future<Envelope> encrypt(
      List<int> plain,
      Uint8List key, {
        List<int> aad = const [],
      }) async {
    _checkKey(key);
    final nonce = randomBytes(12);
    final box = await _algo.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Envelope(
      version: kFormatVersion,
      nonce: nonce,
      cipherText: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> decrypt(
      Envelope envelope,
      Uint8List key, {
        List<int> aad = const [],
      }) async {
    _checkKey(key);
    if (envelope.version != kFormatVersion) {
      throw CryptoException('Невідома версія формату: ${envelope.version}');
    }
    try {
      final clear = await _algo.decrypt(
        SecretBox(
          envelope.cipherText,
          nonce: envelope.nonce,
          mac: Mac(envelope.mac),
        ),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } catch (_) {
      throw CryptoException('Неправильний ключ або дані пошкоджено');
    }
  }

  Future<Envelope> encryptJson(
      Map<String, dynamic> data,
      Uint8List key, {
        List<int> aad = const [],
      }) {
    return encrypt(utf8.encode(jsonEncode(data)), key, aad: aad);
  }

  Future<Map<String, dynamic>> decryptJson(
      Envelope envelope,
      Uint8List key, {
        List<int> aad = const [],
      }) async {
    final bytes = await decrypt(envelope, key, aad: aad);
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw CryptoException('Дані розшифровано, але формат неправильний');
    }
  }

  void _checkKey(Uint8List key) {
    if (key.length != 32) {
      throw CryptoException('Ключ має бути 32 байти, а не ${key.length}');
    }
  }

  // ── Ключ даних, захищений ключем відновлення ──────────────

  static final List<int> _wrapAad = utf8.encode('data-key');

  /// Зашифрувати ключ даних ключем відновлення (це кладеться в хмару).
  Future<Envelope> wrapDataKey(Uint8List dataKey, Uint8List recoveryKey) {
    return encrypt(dataKey, recoveryKey, aad: _wrapAad);
  }

  /// Дістати ключ даних, знаючи ключ відновлення.
  Future<Uint8List> unwrapDataKey(Envelope wrapped, Uint8List recoveryKey) {
    return decrypt(wrapped, recoveryKey, aad: _wrapAad);
  }

  // ── Місяць ────────────────────────────────────────────────

  /// Прив'язка запису місяця до користувача й місяця.
  static List<int> monthAad(String uid, String month) =>
      utf8.encode('$uid/$month');

  Future<Envelope> encryptMonth(
      String uid,
      String month,
      Map<String, dynamic> payload,
      Uint8List dataKey,
      ) {
    return encryptJson(payload, dataKey, aad: monthAad(uid, month));
  }

  Future<Map<String, dynamic>> decryptMonth(
      String uid,
      String month,
      Envelope envelope,
      Uint8List dataKey,
      ) {
    return decryptJson(envelope, dataKey, aad: monthAad(uid, month));
  }
}

// ─────────────────────────────────────────────────────────────
// Ключ відновлення у вигляді тексту
// ─────────────────────────────────────────────────────────────

/// 32 байти → 52 символи абетки Crockford + 4 символи контрольної суми,
/// записані групами по 4: «XXXX-XXXX-…» (14 груп).
String encodeRecoveryKey(Uint8List key) {
  if (key.length != 32) {
    throw CryptoException('Ключ відновлення має бути 32 байти');
  }
  final data = _base32Encode(key); // 52 символи
  final check = _checkChars(key); // 4 символи
  final all = data + check;
  final groups = <String>[
    for (var i = 0; i < all.length; i += 4) all.substring(i, i + 4),
  ];
  return groups.join('-');
}

/// Прочитати ключ відновлення з тексту. Пробіли, дефіси й регістр не важливі;
/// O читається як 0, I і L — як 1 (типові помилки при переписуванні).
Uint8List decodeRecoveryKey(String text) {
  final cleaned = text
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-]'), '')
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');
  if (cleaned.length != 56) {
    throw CryptoException('Ключ має містити 56 символів (зараз ${cleaned.length})');
  }
  for (final ch in cleaned.split('')) {
    if (!_alphabet.contains(ch)) {
      throw CryptoException('У ключі є недопустимий символ «$ch»');
    }
  }
  final bytes = _base32Decode(cleaned.substring(0, 52));
  if (_checkChars(bytes) != cleaned.substring(52)) {
    throw CryptoException('Ключ введено з помилкою: контрольна сума не збігається');
  }
  return bytes;
}

/// Розбити ключ на групи (для екрана підтвердження).
List<String> recoveryKeyGroups(String encoded) => encoded.split('-');

String _base32Encode(Uint8List bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) {
    out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  }
  return out.toString();
}

Uint8List _base32Decode(String text) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in text.split('')) {
    buffer = (buffer << 5) | _alphabet.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 255);
      bits -= 8;
    }
    buffer &= (1 << bits) - 1;
  }
  return Uint8List.fromList(out);
}

/// Контрольні 4 символи (20 біт) на основі суми Adler-32: ловить помилки
/// при переписуванні ключа.
String _checkChars(Uint8List bytes) {
  var a = 1;
  var b = 0;
  for (final byte in bytes) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final value = (b << 16) | a;
  final v20 = (value ^ (value >> 12)) & 0xFFFFF;
  final out = StringBuffer();
  for (var shift = 15; shift >= 0; shift -= 5) {
    out.write(_alphabet[(v20 >> shift) & 31]);
  }
  return out.toString();
}
