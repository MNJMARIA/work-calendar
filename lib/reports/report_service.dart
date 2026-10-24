// Звіти про проблеми: користувач пише вручну, додаток додає технічні дані
// (версія, модель телефона, короткий журнал подій) і надсилає розробниці.
// Автоматичні звіти про збої збирає Firebase Crashlytics окремо.
//
// ВАЖЛИВО: у звіт не потрапляють години, дати виходів чи ключі.

class ReportDraft {
  const ReportDraft({
    required this.category,
    required this.text,
    this.attachLog = true,
  });

  /// «bug» — щось не працює, «idea» — пропозиція, «other» — інше.
  final String category;
  final String text;

  /// Додати короткий журнал подій додатка.
  final bool attachLog;
}

/// Звіт, який бачить розробниця в екрані «Звіти користувачів».
class ReportEntry {
  const ReportEntry({
    required this.id,
    required this.category,
    required this.text,
    required this.appVersion,
    required this.device,
    required this.email,
    required this.createdAt,
    required this.log,
  });

  final String id;
  final String category;
  final String text;
  final String appVersion;
  final String device;
  final String email;
  final DateTime? createdAt;
  final String log;
}

const int kReportMaxText = 2000;
const int kReportMaxLog = 6000;
const Set<String> kReportCategories = {'bug', 'idea', 'other'};

/// Зібрати вміст звіту для хмари: обрізає надто довгі тексти.
Map<String, dynamic> buildReportPayload({
  required ReportDraft draft,
  required String appVersion,
  required String device,
  required String email,
  required String uid,
  required List<String> logLines,
  required int nowMillis,
}) {
  var text = draft.text.trim();
  if (text.length > kReportMaxText) text = text.substring(0, kReportMaxText);

  var log = '';
  if (draft.attachLog) {
    log = logLines.map((l) => l.length > 200 ? l.substring(0, 200) : l).join('\n');
    if (log.length > kReportMaxLog) {
      log = log.substring(log.length - kReportMaxLog);
    }
  }

  return {
    'category': kReportCategories.contains(draft.category) ? draft.category : 'other',
    'text': text,
    'appVersion': appVersion,
    'device': device,
    'email': email,
    'uid': uid,
    'log': log,
    'createdAt': nowMillis,
  };
}

abstract class ReportService {
  /// Надіслати звіт. Кидає виняток, якщо не вдалося.
  Future<void> send(ReportDraft draft);

  /// Лише для адмінки: потік усіх звітів (новіші першими).
  Stream<List<ReportEntry>> watchAll();

  /// Лише для адмінки: видалити звіт.
  Future<void> delete(String id);
}

/// Заглушка: коли хмара не підключена, звіти надіслати не можна.
class OfflineReportService implements ReportService {
  @override
  Future<void> send(ReportDraft draft) {
    throw StateError('Надсилання звітів недоступне без підключення до хмари');
  }

  @override
  Stream<List<ReportEntry>> watchAll() => const Stream.empty();

  @override
  Future<void> delete(String id) async {}
}
