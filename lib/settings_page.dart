// Екран «Налаштування».

import 'package:flutter/material.dart';

import 'account/account_settings.dart';
import 'app_state.dart';
import 'dialogs.dart';
import 'logic.dart';
import 'services.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder перемальовує екран, коли state змінюється
    // (наприклад, після перемикача).
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Налаштування')),
          body: ListView(
            children: [
              SwitchListTile(
                title: const Text('Показувати залишок годин'),
                subtitle: const Text(
                  'Скільки ще лишилось на сьогодні й на тиждень: '
                      'у верхній картці та у виглядах «Тиждень» і «День»',
                ),
                value: state.showRemaining,
                onChanged: state.setShowRemaining,
              ),
              ListTile(
                title: const Text('Тема'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Системна'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Світла'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Темна'),
                      ),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (set) => state.setThemeMode(set.first),
                  ),
                ),
              ),
              ListTile(
                key: const Key('default-shift-tile'),
                title: const Text('Стандартна тривалість виходу'),
                subtitle: Text(fmtHours(state.defaultShiftMinutes)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final result = await showShiftSheet(
                    context,
                    title: 'Стандартна тривалість',
                    hint: 'Підставляється, коли додаєш новий вихід.',
                    initialMinutes: state.defaultShiftMinutes,
                    saveLabel: 'Зберегти',
                  );
                  final minutes = result?.minutes;
                  if (minutes != null) state.setDefaultShiftMinutes(minutes);
                },
              ),
              const Divider(),
              // Акаунт, оновлення, звіти про проблеми (якщо підключена хмара).
              const CloudSettingsSection(),
              const Divider(),
              const ListTile(
                title: Text('Норма місяця'),
                subtitle: Text(
                  'Будні × 8 год. Ручні зміни виходів норму не змінюють.',
                ),
              ),
              ListTile(
                title: const Text('Версія'),
                subtitle: Text(
                  AppServicesScope.of(context).currentVersion.isEmpty
                      ? '0.5.0 — етап 5 (хмара, оновлення, звіти)'
                      : AppServicesScope.of(context).currentVersion,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
