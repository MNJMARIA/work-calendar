// Налаштування, які треба змінити під себе ОДИН раз.
// Тут немає паролів і секретів: цей файл спокійно лежить у відкритому GitHub.

/// Твій логін на GitHub (той, що в адресі github.com/ЛОГІН/work-calendar).
const String kGithubOwner = 'MNJMARIA';

/// Назва репозиторію на GitHub.
const String kGithubRepo = 'work-calendar';

/// Твій ідентифікатор користувача (UID) у Firebase. Бачить екран
/// «Звіти користувачів». Де його взяти — у інструкції (крок «Адмін-доступ»).
/// Це не пароль: без правил Firestore він нічого не дає.
const String kAdminUid = '';

/// Назва теми сповіщень про оновлення (та сама, що в notify.py).
const String kUpdatesTopic = 'updates';

/// Назва додатка та розробниця (показуються в «Про додаток»).
const String kAppName = 'Робочий календар';
const String kDeveloperName = 'Mariia Stepanova';

/// Що показувати, якщо номер версії з телефона прочитати не вдалось.
const String kAppVersionFallback = '0.5.0';
