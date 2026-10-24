// Логіка оновлень (чистий Dart, без Flutter): розбір відповіді GitHub API.
//
// Кожен реліз у GitHub має тег «b<номер збірки>» (наприклад b12), назву
// «Версія 0.5.0 (12)», APK як вкладення й у описі рядок «SHA-256: <хеш>».

class ReleaseInfo {
  const ReleaseInfo({
    required this.build,
    required this.versionName,
    required this.notes,
    required this.apkUrl,
    required this.pageUrl,
    this.sha256,
  });

  /// Номер збірки (зростає з кожним пушем).
  final int build;

  /// Людська версія, наприклад «0.5.0».
  final String versionName;

  /// Опис змін (текст коміту).
  final String notes;

  /// Пряме посилання на APK.
  final String apkUrl;

  /// Сторінка релізу (запасний шлях: відкрити в браузері).
  final String pageUrl;

  /// Контрольна сума APK (може бути відсутня).
  final String? sha256;
}

final RegExp _tagRe = RegExp(r'^b(\d+)$');
final RegExp _versionRe = RegExp(r'Версія\s+(\S+)');
final RegExp _shaRe = RegExp(r'SHA-256:\s*([0-9a-fA-F]{64})');

/// Розібрати відповідь `releases/latest`. Повертає null, якщо це не наш реліз
/// (інший тег, немає APK тощо).
ReleaseInfo? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String) return null;
  final match = _tagRe.firstMatch(tag);
  if (match == null) return null;
  final build = int.parse(match.group(1)!);

  final assets = json['assets'];
  String? apkUrl;
  if (assets is List) {
    for (final asset in assets) {
      if (asset is Map && '${asset['name']}'.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }
  }
  if (apkUrl == null) return null;

  final name = (json['name'] as String?) ?? '';
  final versionName = _versionRe.firstMatch(name)?.group(1) ?? tag;

  final body = (json['body'] as String?) ?? '';
  final sha = _shaRe.firstMatch(body)?.group(1)?.toLowerCase();
  final notes = body
      .split('\n')
      .where((line) => !_shaRe.hasMatch(line))
      .join('\n')
      .trim();

  return ReleaseInfo(
    build: build,
    versionName: versionName,
    notes: notes,
    apkUrl: apkUrl,
    pageUrl: (json['html_url'] as String?) ?? '',
    sha256: sha,
  );
}

/// Чи новіша збірка в релізі, ніж встановлена.
bool isNewerBuild({required int current, required int latest}) => latest > current;

/// Зібрати номер збірки з тексту `1.2.0+15` (версія з pubspec) → 15.
int? buildNumberFromVersion(String version) {
  final plus = version.indexOf('+');
  if (plus < 0) return null;
  return int.tryParse(version.substring(plus + 1));
}
