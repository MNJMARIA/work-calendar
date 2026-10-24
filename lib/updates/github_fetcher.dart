// Запит останнього релізу до GitHub API (без токена, репозиторій публічний).
// Використовує лише стандартну бібліотеку Dart, без додаткових пакетів.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'update_service.dart';

/// Створює функцію, яка повертає JSON `releases/latest` для репозиторію
/// `owner/repo`. Якщо зв'язку немає або реліз не знайдено — повертає null.
ReleaseFetcher githubLatestRelease(String owner, String repo) {
  return () async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'))
          .timeout(const Duration(seconds: 10));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'work-calendar-app');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } finally {
      client.close(force: true);
    }
  };
}
