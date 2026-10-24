// Де на телефоні лежить ключ даних. У додатку це захищене сховище Android
// (Keystore), у тестах — пам'ять.

import 'dart:typed_data';

abstract class KeyStore {
  Future<Uint8List?> readDataKey(String uid);

  Future<void> writeDataKey(String uid, Uint8List key);

  Future<void> deleteDataKey(String uid);
}

/// Сховище в пам'яті (для тестів і режиму без Firebase).
class MemoryKeyStore implements KeyStore {
  final Map<String, Uint8List> _keys = {};

  @override
  Future<Uint8List?> readDataKey(String uid) async => _keys[uid];

  @override
  Future<void> writeDataKey(String uid, Uint8List key) async => _keys[uid] = key;

  @override
  Future<void> deleteDataKey(String uid) async => _keys.remove(uid);
}
