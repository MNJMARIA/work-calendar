// Вибір тривалості «колесами»: окремо години і хвилини.
//
// Як користуватися: затисни пальцем число години чи хвилин і веди вгору або
// вниз — колесо прокручується. Знизу є швидкі варіанти (6, 8, 10, 12 год).

import 'package:flutter/material.dart';

import 'logic.dart';

/// Найбільша тривалість, яку можна вибрати: 23 год 59 хв.
const int kMaxPickMinutes = 24 * 60 - 1;

/// Обмежити хвилини діапазоном 0 … 23:59.
int clampPickMinutes(int minutes) {
  if (minutes < 0) return 0;
  if (minutes > kMaxPickMinutes) return kMaxPickMinutes;
  return minutes;
}

class DurationPicker extends StatefulWidget {
  const DurationPicker({
    super.key,
    required this.initialMinutes,
    required this.onChanged,
    this.presetHours = const [6, 8, 10, 12],
  });

  /// З чого починається вибір (у хвилинах).
  final int initialMinutes;

  /// Викликається щоразу, коли змінилися години чи хвилини.
  final ValueChanged<int> onChanged;

  /// Швидкі варіанти під колесами.
  final List<int> presetHours;

  @override
  State<DurationPicker> createState() => _DurationPickerState();
}

class _DurationPickerState extends State<DurationPicker> {
  late int _hours;
  late int _minutes;
  late final FixedExtentScrollController _hoursController;
  late final FixedExtentScrollController _minutesController;

  @override
  void initState() {
    super.initState();
    final total = clampPickMinutes(widget.initialMinutes);
    _hours = total ~/ 60;
    _minutes = total % 60;
    _hoursController = FixedExtentScrollController(initialItem: _hours);
    _minutesController = FixedExtentScrollController(initialItem: _minutes);
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged(_hours * 60 + _minutes);

  /// Швидкий варіант: ставимо рівні години й нуль хвилин.
  void _applyPreset(int hours) {
    _hours = hours;
    _minutes = 0;
    _hoursController.jumpToItem(hours);
    _minutesController.jumpToItem(0);
    _notify();
  }

  Widget _wheel({
    required Key wheelKey,
    required FixedExtentScrollController controller,
    required int count,
    required ValueChanged<int> onSelected,
  }) {
    final color = Theme.of(context).colorScheme.onSurface;
    return ListWheelScrollView.useDelegate(
      key: wheelKey,
      controller: controller,
      itemExtent: 52,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.8,
      perspective: 0.003,
      overAndUnderCenterOpacity: 0.35,
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          return Center(
            child: Text(
              pad2(index),
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unitStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(color: scheme.onSurfaceVariant);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Світла смужка під вибраним числом.
              IgnorePointer(
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _wheel(
                      wheelKey: const Key('wheel-hours'),
                      controller: _hoursController,
                      count: 24,
                      onSelected: (index) {
                        if (index == _hours) return;
                        _hours = index;
                        _notify();
                      },
                    ),
                  ),
                  Text('год', style: unitStyle),
                  Expanded(
                    child: _wheel(
                      wheelKey: const Key('wheel-minutes'),
                      controller: _minutesController,
                      count: 60,
                      onSelected: (index) {
                        if (index == _minutes) return;
                        _minutes = index;
                        _notify();
                      },
                    ),
                  ),
                  Text('хв', style: unitStyle),
                  const SizedBox(width: 24),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final h in widget.presetHours)
              ActionChip(
                label: Text('$h год'),
                onPressed: () => _applyPreset(h),
              ),
          ],
        ),
      ],
    );
  }
}
