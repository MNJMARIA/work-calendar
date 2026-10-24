// Інтерфейс входу й реєстрації. У додатку працює Firebase Auth
// (firebase_services.dart), у тестах — проста імітація.

class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.name,
    this.emailVerified = false,
  });

  final String uid;
  final String? email;
  final String? name;
  final bool emailVerified;
}

/// Помилка входу/реєстрації з готовим текстом для користувача.
class AuthException implements Exception {
  AuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AuthException($code): $message';
}

abstract class AuthService {
  /// Поточний користувач (null — не ввійшов).
  AuthUser? get currentUser;

  /// Змінюється при вході, виході й оновленні даних користувача.
  Stream<AuthUser?> get userChanges;

  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
  });

  Future<AuthUser> signIn({required String email, required String password});

  Future<void> signOut();

  /// Надіслати лист для підтвердження пошти.
  Future<void> sendVerificationEmail();

  /// Оновити дані користувача з сервера (чи підтверджено пошту).
  Future<AuthUser?> reload();

  Future<void> sendPasswordReset(String email);

  /// Перевірити пароль перед небезпечною дією (видалення акаунта).
  Future<void> reauthenticate(String password);

  /// Видалити акаунт (спершу треба [reauthenticate]).
  Future<void> deleteAccount();
}
