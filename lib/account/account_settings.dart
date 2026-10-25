// Розділи налаштувань, пов'язані з хмарою: акаунт, оновлення, підтримка.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../reports/report_pages.dart';
import 'account_controller.dart';
import '../services.dart';
import '../sync/sync_service.dart';
import '../updates/update_pages.dart';
import '../updates/update_service.dart';

class CloudSettingsSection extends StatelessWidget {
  const CloudSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    return Column(
      children: [
        if (services.account != null) _AccountTiles(services: services),
        if (services.account == null && services.cloudError != null)
          _CloudErrorTile(error: services.cloudError!),
        if (services.updates != null) _UpdateTile(services: services),
        _SupportTiles(services: services),
      ],
    );
  }
}

/// Хмара не запустилась: показуємо причину (її можна скопіювати й надіслати розробниці).
class _CloudErrorTile extends StatelessWidget {
  const _CloudErrorTile({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: const Key('cloud-error'),
      leading: Icon(Icons.cloud_off, color: scheme.error),
      title: const Text('Хмара не підключилась'),
      subtitle: Text(
        'Календар працює, але без акаунта й синхронізації. '
            'Торкнись, щоб скопіювати текст помилки.\n\n$error',
      ),
      isThreeLine: true,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: error));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Текст помилки скопійовано')),
          );
        }
      },
    );
  }
}

String _syncText(SyncService sync) {
  switch (sync.status) {
    case SyncStatus.off:
      return 'Вимкнено';
    case SyncStatus.idle:
      final t = sync.lastSync;
      if (t == null) return 'Усе збережено в хмарі';
      String two(int v) => v.toString().padLeft(2, '0');
      return 'Усе збережено в хмарі (${two(t.hour)}:${two(t.minute)})';
    case SyncStatus.syncing:
      return 'Синхронізація…';
    case SyncStatus.offline:
      return 'Немає зв\'язку: дані збережено на телефоні й підуть у хмару пізніше';
    case SyncStatus.error:
      return 'Помилка: ${sync.lastError ?? 'невідома'}';
  }
}

class _AccountTiles extends StatelessWidget {
  const _AccountTiles({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final account = services.account!;
    return ListenableBuilder(
      listenable: Listenable.merge([account, if (services.sync != null) services.sync!]),
      builder: (context, _) {
        final user = account.user;
        final signedIn = account.stage == AccountStage.ready;
        if (!signedIn || user == null) {
          return ListTile(
            key: const Key('account-signin'),
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Увійти або створити акаунт'),
            subtitle: const Text('Щоб дані зберігалися в хмарі й були на всіх телефонах'),
            onTap: () async {
              Navigator.of(context).popUntil((r) => r.isFirst);
              await account.leaveLocalMode();
            },
          );
        }
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text(user.name?.isNotEmpty == true ? user.name! : 'Акаунт'),
              subtitle: Text(user.email ?? ''),
            ),
            if (services.sync != null)
              ListTile(
                key: const Key('sync-now'),
                leading: const Icon(Icons.sync),
                title: const Text('Синхронізувати зараз'),
                subtitle: Text(_syncText(services.sync!)),
                onTap: services.sync!.syncNow,
              ),
            ListTile(
              key: const Key('new-recovery-key'),
              leading: const Icon(Icons.key),
              title: const Text('Новий ключ відновлення'),
              subtitle: const Text('Якщо старий ключ загубився або став відомий комусь'),
              onTap: () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await account.beginRegenerateKey();
              },
            ),
            ListTile(
              key: const Key('sign-out'),
              leading: const Icon(Icons.logout),
              title: const Text('Вийти з акаунта'),
              onTap: () => _signOut(context, account),
            ),
            ListTile(
              key: const Key('delete-account'),
              leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
              title: Text(
                'Видалити акаунт',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('Хмарні дані буде видалено назавжди'),
              onTap: () => _deleteAccount(context, account),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context, AccountController account) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Вийти з акаунта?'),
        content: const Text(
          'Дані в хмарі лишаються. Можна також стерти дані з цього телефона '
              '(наприклад, якщо ти віддаєш його іншій людині).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Скасувати'),
          ),
          TextButton(
            key: const Key('signout-wipe'),
            onPressed: () => Navigator.pop(dialogContext, 'wipe'),
            child: const Text('Вийти й стерти дані'),
          ),
          FilledButton(
            key: const Key('signout-keep'),
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: const Text('Вийти'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await account.signOut(wipeLocal: choice == 'wipe');
  }

  Future<void> _deleteAccount(BuildContext context, AccountController account) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || password.isEmpty || !context.mounted) return;
    await account.deleteAccount(password);
    if (!context.mounted) return;
    if (account.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(account.error!)));
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }
}

/// Вікно підтвердження видалення: поле пароля живе всередині вікна,
/// тому його не можна випадково прибрати, поки вікно ще закривається.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Видалити акаунт?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Усі дані в хмарі буде видалено без можливості відновлення. '
                'Дані на цьому телефоні лишаться. Введи пароль, щоб підтвердити.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('delete-password'),
            controller: _controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Пароль',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Видалити'),
        ),
      ],
    );
  }
}

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final updates = services.updates!;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final release = updates.available;
        return ListTile(
          key: const Key('updates-tile'),
          leading: Icon(release != null ? Icons.system_update : Icons.verified_outlined),
          title: const Text('Оновлення'),
          subtitle: Text(
            release != null
                ? 'Доступна версія ${release.versionName}'
                : updates.status == UpdateStatus.checking
                ? 'Перевіряю…'
                : 'Перевірити, чи є нова версія',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openUpdatePage(context),
        );
      },
    );
  }
}

class _SupportTiles extends StatefulWidget {
  const _SupportTiles({required this.services});

  final AppServices services;

  @override
  State<_SupportTiles> createState() => _SupportTilesState();
}

class _SupportTilesState extends State<_SupportTiles> {
  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final crash = services.crash;
    return Column(
      children: [
        if (services.cloudEnabled)
          ListTile(
            key: const Key('report-tile'),
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Повідомити про проблему'),
            subtitle: const Text('Напиши, що пішло не так'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReportPage()),
            ),
          ),
        if (crash != null)
          SwitchListTile(
            key: const Key('crash-switch'),
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('Автоматичні звіти про збої'),
            subtitle: const Text(
              'Якщо додаток впаде, розробниця отримає технічний звіт без твоїх даних',
            ),
            value: crash.enabled,
            onChanged: (v) async {
              await crash.setEnabled(v);
              if (mounted) setState(() {});
            },
          ),
        if (services.isAdmin)
          ListTile(
            key: const Key('admin-tile'),
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('Звіти користувачів'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AdminReportsPage()),
            ),
          ),
      ],
    );
  }
}
