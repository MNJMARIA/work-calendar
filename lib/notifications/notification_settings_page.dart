// Екран «Сповіщення»: нагадування про зміни, сповіщення про оновлення, пробне сповіщення.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services.dart';
import 'reminder_plan.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key, required this.state});

  final AppState state;

  Future<void> _pickTime(
      BuildContext context,
      int initialMinutes,
      void Function(int minutes) onPicked,
      ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialMinutes ~/ 60, minute: initialMinutes % 60),
      helpText: 'Час нагадування',
    );
    if (picked != null) onPicked(picked.hour * 60 + picked.minute);
  }

  Future<void> _toggle(
      BuildContext context,
      AppServices services,
      bool value,
      void Function(bool v) apply,
      ) async {
    apply(value);
    if (value) {
      // Android 13+ вимагає дозволу на сповіщення: просимо його, коли користувач
      // вмикає перше нагадування.
      final granted = await services.reminders?.requestPermission() ?? true;
      if (!granted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Сповіщення вимкнені для додатка. Дозволь їх у налаштуваннях телефона.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Сповіщення')),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Нагадування про зміни',
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              SwitchListTile(
                key: const Key('remind-start'),
                title: const Text('Нагадувати про початок зміни'),
                subtitle: const Text('У дні, коли в календарі є вихід'),
                value: state.remindStart,
                onChanged: (v) => _toggle(context, services, v, state.setRemindStart),
              ),
              ListTile(
                key: const Key('remind-start-time'),
                enabled: state.remindStart,
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: const Text('Час нагадування'),
                trailing: Text(
                  fmtClockMinutes(state.remindStartMinutes),
                  style: theme.textTheme.titleMedium,
                ),
                onTap: () => _pickTime(context, state.remindStartMinutes, state.setRemindStartMinutes),
              ),
              SwitchListTile(
                key: const Key('remind-end'),
                title: const Text('Нагадувати про кінець зміни'),
                subtitle: const Text('Щоб не забути закінчити зміну й перевірити години'),
                value: state.remindEnd,
                onChanged: (v) => _toggle(context, services, v, state.setRemindEnd),
              ),
              ListTile(
                key: const Key('remind-end-time'),
                enabled: state.remindEnd,
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: const Text('Час нагадування'),
                trailing: Text(
                  fmtClockMinutes(state.remindEndMinutes),
                  style: theme.textTheme.titleMedium,
                ),
                onTap: () => _pickTime(context, state.remindEndMinutes, state.setRemindEndMinutes),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Нагадування ставляться на 30 днів уперед за виходами з календаря. '
                      'Коли ти змінюєш виходи, вони оновлюються самі.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const Divider(),
              if (services.setUpdatePush != null)
                SwitchListTile(
                  key: const Key('push-updates'),
                  title: const Text('Сповіщення про оновлення'),
                  subtitle: const Text('Повідомляти, коли вийшла нова версія додатка'),
                  value: state.pushUpdates,
                  onChanged: (v) {
                    state.setPushUpdates(v);
                    services.setUpdatePush!(v);
                  },
                ),
              if (services.reminders != null)
                ListTile(
                  key: const Key('notif-test'),
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Надіслати пробне сповіщення'),
                  subtitle: const Text('Перевірити, що сповіщення доходять'),
                  onTap: () async {
                    final reminders = services.reminders!;
                    final granted = await reminders.requestPermission();
                    if (!granted) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Сповіщення вимкнені. Дозволь їх у налаштуваннях телефона.'),
                          ),
                        );
                      }
                      return;
                    }
                    await reminders.sendTest();
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Text(
                  'Якщо сповіщення не приходять (особливо на OPPO, Xiaomi, Samsung): '
                      'Налаштування телефона → Додатки → Робочий календар → Батарея → '
                      '«Без обмежень», і ввімкни «Автозапуск». Інакше система вимикає додаток у фоні.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
