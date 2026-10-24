// Тести синхронізації: два «телефони» і спільна «хмара» в пам'яті.
// Запуск: flutter test test/sync_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_calendar/crypto/crypto_service.dart';
import 'package:work_calendar/sync/records.dart';
import 'package:work_calendar/sync/sync_service.dart';

import 'fakes.dart';

void main() {
  final crypto = CryptoService();
  final day = DateTime(2026, 10, 20);

  /// Дати телефонам час обмінятися змінами (пауза надсилання дуже мала).
  Future<void> converge() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await settle();
  }

  /// Телефон, на якому вже запущена синхронізація.
  Future<Phone> started(MemoryCloudStore cloud, Uint8List key, {String uid = 'u1'}) async {
    final p = await Phone.create(cloud: cloud);
    addTearDown(p.sync.stop);
    await p.sync.start(uid, key);
    await settle();
    return p;
  }

  test('після start статус «все збережено»', () async {
    final key = crypto.newKey();
    final p = await started(MemoryCloudStore(), key);
    expect(p.sync.running, isTrue);
    expect(p.sync.status, SyncStatus.idle);
  });

  test('зміна потрапляє в хмару зашифрованою', () async {
    final cloud = MemoryCloudStore();
    final key = crypto.newKey();
    final p = await started(cloud, key);
    p.state.setShifts([day], 720);
    await p.sync.syncNow();

    final doc = cloud.months['u1']!['2026-10']!;
    expect(doc['v'], kFormatVersion);
    final text = jsonEncode(doc);
    expect(text, isNot(contains('2026-10-20')));

    final env = Envelope.fromJson(Map<String, dynamic>.from(doc['env'] as Map));
    final payload = await crypto.decryptMonth('u1', '2026-10', env, key);
    final days = parseMonthPayload(payload);
    expect(days['2026-10-20']!.minutes, 720);
  });

  test('автоматичне надсилання через паузу після зміни', () async {
    final cloud = MemoryCloudStore();
    final p = await started(cloud, crypto.newKey());
    p.state.setShifts([day], 720);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await settle();
    expect(cloud.months['u1']?['2026-10'], isNotNull);
  });

  test('незмінений місяць повторно не надсилається', () async {
    final cloud = MemoryCloudStore();
    final p = await started(cloud, crypto.newKey());
    p.state.setShifts([day], 720);
    await p.sync.syncNow();
    final before = cloud.putCount;
    await p.sync.syncNow();
    expect(cloud.putCount, before);
  });

  test('другий телефон отримує дані першого', () async {
    final cloud = MemoryCloudStore();
    final key = crypto.newKey();
    final a = await started(cloud, key);
    a.state.setShifts([day, DateTime(2026, 10, 21)], 720);
    await a.sync.syncNow();

    final b = await started(cloud, key);
    expect(b.state.shifts, {'2026-10-20': 720, '2026-10-21': 720});
  });

  test('зміни доходять до працюючого телефона наживо', () async {
    final cloud = MemoryCloudStore();
    final key = crypto.newKey();
    final a = await started(cloud, key);
    final b = await started(cloud, key);

    a.state.setShifts([day], 480);
    await a.sync.syncNow();
    await settle();
    expect(b.state.shifts['2026-10-20'], 480);
  });

  test('видалення доходить до іншого телефона', () async {
    final cloud = MemoryCloudStore();
    final key = crypto.newKey();
    final a = await started(cloud, key);
    final b = await started(cloud, key);

    a.state.setShifts([day], 480);
    await a.sync.syncNow();
    await settle();
    expect(b.state.shifts, isNotEmpty);

    a.clockTime = DateTime(2026, 10, 24, 11);
    a.state.setShifts([day], null);
    await a.sync.syncNow();
    await settle();
    expect(b.state.shifts, isEmpty);
  });

  test('старіша правка з іншого телефона не перезаписує новішу', () async {
    final cloud = MemoryCloudStore();
    final key = crypto.newKey();
    final a = await started(cloud, key);
    final b = await started(cloud, key);

    a.clockTime = DateTime(2026, 10, 24, 12);
    a.state.setShifts([day], 720);
    await a.sync.syncNow();
    await settle();

    // B правив той самий день раніше (годинник відстає).
    b.clockTime = DateTime(2026, 10, 24, 9);
    b.state.setShifts([day], 480);
    await b.sync.syncNow();
    await converge();

    expect(a.state.shifts['2026-10-20'], 720);
    expect(b.state.shifts['2026-10-20'], 720);
  });

  test('неправильний ключ: дані не псуються, статус «помилка»', () async {
    final cloud = MemoryCloudStore();
    final a = await started(cloud, crypto.newKey());
    a.state.setShifts([day], 720);
    await a.sync.syncNow();
    final before = jsonEncode(cloud.months['u1']);

    final wrong = await started(cloud, crypto.newKey());
    expect(wrong.sync.status, SyncStatus.error);

    wrong.state.setShifts([DateTime(2026, 10, 21)], 480);
    await wrong.sync.syncNow();
    await settle();
    expect(jsonEncode(cloud.months['u1']), before);
    expect(wrong.state.shifts, {'2026-10-21': 480});
  });

  test('чужий місяць, підкинутий в інший, не розшифровується', () async {
    final cloud = MemoryCloudStore();
    final key = crypto.newKey();
    final a = await started(cloud, key);
    a.state.setShifts([day], 720);
    await a.sync.syncNow();

    // Підміна: документ жовтня видається за листопад.
    cloud.months['u1']!['2026-11'] = Map.of(cloud.months['u1']!['2026-10']!);
    final b = await started(cloud, key);
    expect(b.sync.status, SyncStatus.error);
    expect(b.state.shifts.containsKey('2026-11-20'), isFalse);
  });

  test('помилка запису → статус «помилка», дані на телефоні цілі', () async {
    final cloud = MemoryCloudStore()..failPuts = true;
    final p = await started(cloud, crypto.newKey());
    p.state.setShifts([day], 720);
    await p.sync.syncNow();
    expect(p.sync.status, SyncStatus.error);
    expect(p.state.shifts['2026-10-20'], 720);

    // Зв'язок повернувся: наступна спроба проходить.
    cloud.failPuts = false;
    await p.sync.syncNow();
    expect(cloud.months['u1']?['2026-10'], isNotNull);
  });

  test('запис «завис» (немає зв\'язку) → статус «офлайн»', () async {
    final cloud = MemoryCloudStore()..hangPuts = true;
    final p = await started(cloud, crypto.newKey());
    p.state.setShifts([day], 720);
    await p.sync.syncNow();
    expect(p.sync.status, SyncStatus.offline);
    expect(p.state.shifts['2026-10-20'], 720);
  });

  test('після stop зміни в хмару не йдуть', () async {
    final cloud = MemoryCloudStore();
    final p = await started(cloud, crypto.newKey());
    await p.sync.stop();
    expect(p.sync.running, isFalse);
    expect(p.sync.status, SyncStatus.off);
    p.state.setShifts([day], 720);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await p.sync.syncNow();
    expect(cloud.months['u1'], isNull);
  });

  test('дні різних місяців — окремі документи', () async {
    final cloud = MemoryCloudStore();
    final p = await started(cloud, crypto.newKey());
    p.state.setShifts([DateTime(2026, 10, 31), DateTime(2026, 11, 1)], 480);
    await p.sync.syncNow();
    expect(cloud.months['u1']!.keys.toSet(), {'2026-10', '2026-11'});
  });
}
