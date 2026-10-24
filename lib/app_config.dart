// Налаштування, які треба змінити під себе ОДИН раз.
// Тут немає паролів і секретів: цей файл спокійно лежить у відкритому GitHub.

/// Твій логін на GitHub (той, що в адресі github.com/ЛОГІН/work-calendar).
const String kGithubOwner = 'MNJMARIA';   // той самий, що в адресі github.com/MNJMARIA

/// Назва репозиторію на GitHub.
const String kGithubRepo = 'work-calendar';

/// Твій ідентифікатор користувача (UID) у Firebase. Бачить екран
/// «Звіти користувачів». Де його взяти — у інструкції (крок «Адмін-доступ»).
/// Це не пароль: без правил Firestore він нічого не дає.
const String kAdminUid = '';

/// Назва теми сповіщень про оновлення (та сама, що в notify.py).
const String kUpdatesTopic = 'updates';


