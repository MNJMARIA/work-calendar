// Екрани оновлення: смужка «Доступне оновлення», сторінка з кнопкою «Оновити»
// і вікно «Додаток оновлено».

import 'package:flutter/material.dart';

import '../services.dart';
import 'update_service.dart';

/// Смужка над нижнім меню: з'являється, лише коли є нова версія.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = AppServicesScope.of(context).updates;
    if (updates == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final release = updates.available;
        if (release == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.primaryContainer,
          child: InkWell(
            key: const Key('update-banner'),
            onTap: () => openUpdatePage(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.system_update, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Доступне оновлення ${release.versionName}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Оновити',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

void openUpdatePage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const UpdatePage()),
  );
}

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      // Одразу перевіряємо, чи є нова версія. Робимо це ПІСЛЯ малювання екрана:
      // перевірка одразу повідомляє слухачів (смужку оновлення), а під час
      // побудови екрана це заборонено.
      final updates = AppServicesScope.of(context).updates;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) updates?.check();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    final updates = services.updates;
    return Scaffold(
      appBar: AppBar(title: const Text('Оновлення')),
      body: updates == null
          ? const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Оновлення недоступні в цій збірці.'),
      )
          : ListenableBuilder(
        listenable: updates,
        builder: (context, _) => _body(context, services, updates),
      ),
    );
  }

  Widget _body(BuildContext context, AppServices services, UpdateService updates) {
    final theme = Theme.of(context);
    final release = updates.available;
    final status = updates.status;
    final busy = status == UpdateStatus.downloading || status == UpdateStatus.installing;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Встановлена версія: ${services.currentVersion.isEmpty ? updates.currentVersion : services.currentVersion}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (status == UpdateStatus.checking && release == null)
          const Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(width: 12),
              Text('Перевіряю оновлення…'),
            ],
          )
        else if (release != null) ...[
          Text(
            'Доступна нова версія ${release.versionName}',
            key: const Key('update-available-title'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Що нового:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(release.notes),
          ],
          const SizedBox(height: 20),
          if (status == UpdateStatus.downloading) ...[
            LinearProgressIndicator(value: updates.percent > 0 ? updates.percent / 100 : null),
            const SizedBox(height: 8),
            Text('Завантаження… ${updates.percent}%'),
          ] else if (status == UpdateStatus.installing)
            const Text(
              'Підтверди встановлення у вікні телефона. Після цього додаток '
                  'перезапуститься вже в новій версії.',
            )
          else
            FilledButton.icon(
              key: const Key('update-install'),
              onPressed: updates.install,
              icon: const Icon(Icons.download),
              label: const Text('Оновити'),
            ),
          if (updates.error != null) ...[
            const SizedBox(height: 12),
            Text(updates.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (!busy && services.openUrl != null && release.pageUrl.isNotEmpty)
            TextButton(
              onPressed: () => services.openUrl!(release.pageUrl),
              child: const Text('Відкрити сторінку завантаження'),
            ),
        ] else ...[
          Row(
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(child: Text('У тебе остання версія додатка.')),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('update-check'),
            onPressed: updates.check,
            child: const Text('Перевірити ще раз'),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Оновлення завантажується з GitHub. Дані календаря під час оновлення '
              'не видаляються.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Вікно «Додаток оновлено» після першого запуску нової версії.
Future<void> showJustUpdatedDialog(BuildContext context, String version) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.celebration),
      title: const Text('Додаток оновлено'),
      content: Text(version.isEmpty ? 'Тепер у тебе нова версія.' : 'Тепер у тебе версія $version.'),
      actions: [
        FilledButton(
          key: const Key('updated-ok'),
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Чудово'),
        ),
      ],
    ),
  );
}
