// Інтерфейс хмарного сховища. Решта коду не залежить від Firebase:
// у додатку працює FirestoreCloudStore, у тестах — проста імітація в пам'яті.

/// Зміни, що прийшли з хмари.
class CloudEvent {
  const CloudEvent({required this.months, required this.fromCache});

  /// Змінені записи місяців: «2026-10» → документ ({v, env, updatedAt}).
  final Map<String, Map<String, dynamic>> months;

  /// true, якщо дані прийшли з локального кешу (зв'язку з сервером немає).
  final bool fromCache;
}

abstract class CloudStore {
  /// Документ із зашифрованим ключем даних (або null, якщо ще немає).
  Future<Map<String, dynamic>?> getKeyDoc(String uid);

  /// Зберегти (замінити) документ із зашифрованим ключем даних.
  Future<void> putKeyDoc(String uid, Map<String, dynamic> doc);

  /// Зберегти зашифрований місяць.
  Future<void> putMonth(String uid, String month, Map<String, dynamic> doc);

  /// Стежити за місяцями: перша подія містить усе, далі — лише зміни.
  Stream<CloudEvent> watchMonths(String uid);

  /// Видалити всі хмарні дані користувача (місяці й ключ).
  Future<void> deleteUserData(String uid);
}
