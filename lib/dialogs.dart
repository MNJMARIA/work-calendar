// Спільні вікна: вибір тривалості виходу і початок роботи.

import 'package:flutter/material.dart';

import 'duration_picker.dart';
import 'logic.dart';

/// Результат нижнього вікна: [minutes] = null означає «прибрати вихід».
class SheetResult {
  const SheetResult(this.minutes) : startTimer = false;

  /// Користувач натиснув «Почати відлік»: треба запустити таймер.
  const SheetResult.timer()
      : minutes = null,
        startTimer = true;

  final int? minutes;
  final bool startTimer;
}

/// Нижнє вікно вибору тривалості: окремі колеса для годин і хвилин.
/// Повертає null, якщо користувач закрив вікно без вибору.
Future<SheetResult?> showShiftSheet(
    BuildContext context, {
      required String title,
      required String hint,
      required int initialMinutes,
      required String saveLabel,
      String? removeLabel,
      bool offerTimer = false,
    }) {
  var minutes = clampPickMinutes(initialMinutes);

  return showModalBottomSheet<SheetResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      // StatefulBuilder оновлює лише це вікно (підсумок і кнопку «Зберегти»).
      return StatefulBuilder(
        builder: (context, setSheet) {
          final scheme = Theme.of(context).colorScheme;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (offerTimer) ...[
                    const SizedBox(height: 12),
                    // Для сьогоднішнього дня: почати відлік зараз
                    // або з вибраного часу.
                    FilledButton.tonalIcon(
                      key: const Key('start-timer-button'),
                      onPressed: () =>
                          Navigator.pop(sheetContext, const SheetResult.timer()),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Почати відлік (зараз або з часу)'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Або вкажи тривалість вручну:',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Підсумок великими цифрами.
                  Center(
                    child: Text(
                      minutes == 0 ? '0 хв' : fmtHours(minutes),
                      key: const Key('shift-total'),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DurationPicker(
                    initialMinutes: minutes,
                    onChanged: (value) => setSheet(() => minutes = value),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    // 0 хвилин зберегти не можна — для цього є «Прибрати».
                    onPressed: minutes < 1
                        ? null
                        : () => Navigator.pop(sheetContext, SheetResult(minutes)),
                    child: Text(saveLabel),
                  ),
                  if (removeLabel != null)
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(sheetContext, const SheetResult(null)),
                      child: Text(removeLabel),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Вибір часу у 24-годинному форматі.
Future<TimeOfDay?> pickTime24(BuildContext context, TimeOfDay initial) {
  return showTimePicker(
    context: context,
    initialTime: initial,
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      );
    },
  );
}

/// Вікно «Початок роботи»: або почати відлік зараз, або вказати час початку.
/// Повертає момент початку або null, якщо користувач скасував.
Future<DateTime?> showStartWorkDialog(BuildContext context) {
  var startNow = true;
  var time = const TimeOfDay(hour: 8, minute: 0);

  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialog) {
          final now = DateTime.now();
          final chosen = resolveStartTime(now, time.hour, time.minute);
          final dayWord = dayKey(chosen) == dayKey(now) ? 'сьогодні' : 'вчора';

          return AlertDialog(
            title: const Text('Початок роботи'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: startNow,
                  onChanged: (v) => setDialog(() => startNow = v ?? true),
                  title: const Text('Почати відлік зараз'),
                ),
                if (!startNow) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text('Час початку: ${pad2(time.hour)}:${pad2(time.minute)}'),
                    onPressed: () async {
                      final picked = await pickTime24(dialogContext, time);
                      if (picked != null) setDialog(() => time = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Відлік піде з $dayWord о '
                        '${pad2(chosen.hour)}:${pad2(chosen.minute)}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Скасувати'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  startNow ? DateTime.now() : chosen,
                ),
                child: const Text('Почати'),
              ),
            ],
          );
        },
      );
    },
  );
}
