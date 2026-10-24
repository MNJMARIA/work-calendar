// Вкладка «Планування»: окремий календар-чернетка.
//
// Тут можна «наклацати» майбутні робочі дні й години та одразу побачити,
// чи закривається місячна норма. Чернетка НЕ змінює справжній календар.

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'dialogs.dart';
import 'logic.dart';
import 'widgets.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key, required this.state});

  final AppState state;

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  /// Місяць, який планується (завжди 1-ше число).
  late DateTime _month;

  /// Вибрані дні (довге натискання).
  final Set<DateTime> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  DateTime get _lastDayOfMonth =>
      DateTime(_month.year, _month.month, daysInMonth(_month.year, _month.month));

  // ── Навігація та вибір ────────────────────────────────────

  void _step(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _selected.clear();
    });
  }

  void _toggle(DateTime date) {
    setState(() {
      if (!_selected.remove(date)) _selected.add(date);
    });
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  void _onDayTap(DateTime date, DateTime today) {
    if (!date.isAfter(today)) {
      _toast('Минулі дні та сьогодні змінюються у вкладці «Календар».');
      return;
    }
    if (_selecting) {
      _toggle(date);
    } else {
      _editPlanDay(date);
    }
  }

  void _onDayLongPress(DateTime date, DateTime today) {
    if (!date.isAfter(today)) return;
    _toggle(date);
  }

  void _toast(String text) => showToast(context, text, bottomMargin: 16);

  /// Повідомлення з кнопкою «Скасувати» (зникає за 2 секунди).
  void _toastUndo(String text, Map<String, int?> previous) {
    showToast(
      context,
      text,
      bottomMargin: 16,
      onAction: () => _state.restorePlan(previous),
    );
  }

  // ── Дії з чернеткою ───────────────────────────────────────

  Future<void> _editPlanDay(DateTime date) async {
    final existing = _state.plan[dayKey(date)];
    final result = await showShiftSheet(
      context,
      title: '${date.day} ${kMonthsGenitive[date.month - 1]}, '
          '${kWeekdaysFull[date.weekday - 1]}',
      hint: 'Це чернетка. Вона не змінює справжній календар.',
      initialMinutes: existing ?? _state.defaultShiftMinutes,
      saveLabel: existing == null ? 'Додати в план' : 'Зберегти зміни',
      removeLabel: existing != null ? 'Прибрати з плану' : null,
    );
    if (result == null || !mounted) return;
    _applyPlan([date], result.minutes);
  }

  Future<void> _bulkEdit() async {
    final dates = _selected.toList()..sort();
    final result = await showShiftSheet(
      context,
      title: 'Вибрано днів: ${dates.length}',
      hint: 'Усім вибраним дням у чернетці буде встановлено однакову тривалість.',
      initialMinutes: _state.defaultShiftMinutes,
      saveLabel: 'Застосувати до ${dates.length} дн.',
      removeLabel: 'Прибрати вибрані дні з плану',
    );
    if (result == null || !mounted) return;
    _applyPlan(dates, result.minutes);
    _clearSelection();
  }

  void _bulkRemove() {
    final dates = _selected.toList()..sort();
    _applyPlan(dates, null);
    _clearSelection();
  }

  void _applyPlan(List<DateTime> dates, int? minutes) {
    final previous = _state.setPlan(dates, minutes);
    _toastUndo(
      minutes == null
          ? 'З плану прибрано днів: ${dates.length}'
          : 'У плані: ${dates.length} дн. по ${fmtHours(minutes)}',
      previous,
    );
  }

  /// Скопіювати майбутні виходи з календаря у чернетку.
  void _copyFromCalendar() {
    final today = dateOnly(DateTime.now());
    final previous = _state.copyShiftsToPlan(_month, _lastDayOfMonth, today);
    if (previous.isEmpty) {
      _toast('У календарі немає майбутніх виходів цього місяця.');
    } else {
      _toastUndo('Скопійовано з календаря днів: ${previous.length}', previous);
    }
  }

  Future<void> _clearPlan() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Очистити чернетку?'),
          content: Text(
            'Усі дні плану за ${kMonthsNominative[_month.month - 1].toLowerCase()} '
                '${_month.year} буде прибрано. Справжній календар не зміниться.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Скасувати'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Очистити'),
            ),
          ],
        );
      },
    );
    if (sure != true || !mounted) return;
    final previous = _state.clearPlanBetween(_month, _lastDayOfMonth);
    if (previous.isNotEmpty) {
      _toastUndo('Чернетку очищено', previous);
    }
  }

  // ── Побудова екрана ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final now = DateTime.now();
        final today = dateOnly(now);

        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _clearSelection();
          },
          child: Scaffold(
            appBar: _selecting ? _buildSelectionBar() : _buildNormalBar(),
            // ListView: сторінка прокручується, нічого не стискається.
            body: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSummary(today, now),
                _buildNavRow(),
                _buildLegend(),
                MonthGrid(
                  year: _month.year,
                  month: _month.month,
                  bottomPadding: 16,
                  cellBuilder: (date) => _buildCell(date, today, now),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _buildNormalBar() {
    return AppBar(
      title: const Text('Планування'),
      actions: [
        IconButton(
          tooltip: 'Взяти майбутні виходи з календаря',
          onPressed: _copyFromCalendar,
          icon: const Icon(Icons.content_copy),
        ),
        IconButton(
          tooltip: 'Очистити чернетку місяця',
          onPressed: _clearPlan,
          icon: const Icon(Icons.delete_sweep),
        ),
      ],
    );
  }

  AppBar _buildSelectionBar() {
    return AppBar(
      leading: IconButton(
        tooltip: 'Скасувати вибір',
        onPressed: _clearSelection,
        icon: const Icon(Icons.close),
      ),
      title: Text('Вибрано: ${_selected.length}'),
      actions: [
        IconButton(
          tooltip: 'Змінити години',
          onPressed: _bulkEdit,
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          tooltip: 'Прибрати з плану',
          onPressed: _bulkRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  /// Картка прогнозу: факт + чернетка проти норми місяця.
  Widget _buildSummary(DateTime today, DateTime now) {
    final year = _month.year;
    final month = _month.month;
    final last = _lastDayOfMonth;

    final norm = monthNormMinutes(year, month);
    final fact = _state.workedBetween(_month, last, today, now);

    // Чернетка рахується лише для днів ПІСЛЯ сьогодні.
    final planFrom = _month.isAfter(today) ? _month : addDays(today, 1);
    final draft = sumRange(_state.plan, planFrom, last);
    final total = fact + draft;
    final missing = norm > total ? norm - total : 0;

    // Скільки майбутніх днів місяця ще вільні (без плану).
    var freeDays = 0;
    for (var d = planFrom; !d.isAfter(last); d = addDays(d, 1)) {
      if (!_state.plan.containsKey(dayKey(d))) freeDays++;
    }

    final chips = <Widget>[];
    if (missing > 0) {
      final shifts = ceilDiv(missing, _state.defaultShiftMinutes);
      chips.add(InfoChip(Icons.hourglass_bottom, 'Не вистачає ${fmtHours(missing)}'));
      chips.add(
        InfoChip(
          Icons.add_task,
          '≈ $shifts вих. по ${fmtHours(_state.defaultShiftMinutes)}',
        ),
      );
    } else {
      chips.add(const InfoChip(Icons.check_circle, 'Норму закрито'));
    }
    chips.add(InfoChip(Icons.event_available, 'Вільних днів: $freeDays'));

    return NormCard(
      title: 'Прогноз: ${kMonthsNominative[month - 1]} $year',
      worked: total,
      norm: norm,
      note: 'Факт ${fmtHours(fact)} + чернетка ${fmtHours(draft)}. '
          'Чернетка не змінює справжній календар.',
      chips: chips,
    );
  }

  Widget _buildNavRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Попередній місяць',
            onPressed: () => _step(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${kMonthsNominative[_month.month - 1]} ${_month.year}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Наступний місяць',
            onPressed: () => _step(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  /// Підпис кольорів: факт і чернетка.
  Widget _buildLegend() {
    final scheme = Theme.of(context).colorScheme;
    Widget dot(Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 16,
        children: [
          dot(scheme.secondaryContainer, 'Факт (з календаря)'),
          dot(scheme.tertiaryContainer, 'Чернетка'),
        ],
      ),
    );
  }

  /// Клітинка дня: минулі — факт (лише перегляд), майбутні — чернетка.
  Widget _buildCell(DateTime date, DateTime today, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final isPast = !date.isAfter(today);

    if (isPast) {
      final timerDay = _state.isTimerDay(date);
      final int? minutes = timerDay
          ? _state.elapsedSeconds(now) ~/ 60
          : _state.shifts[dayKey(date)];
      return DayCellBox(
        day: date.day,
        background: minutes != null
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        foreground: minutes != null
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant,
        minutes: minutes,
        isToday: date == today,
        onTap: () => _onDayTap(date, today),
      );
    }

    final minutes = _state.plan[dayKey(date)];
    final isWeekend = date.weekday >= DateTime.saturday;
    return DayCellBox(
      day: date.day,
      background: minutes != null
          ? scheme.tertiaryContainer
          : scheme.surfaceContainerLow,
      foreground: minutes != null
          ? scheme.onTertiaryContainer
          : (isWeekend ? scheme.error : scheme.onSurface),
      minutes: minutes,
      selected: _selected.contains(date),
      onTap: () => _onDayTap(date, today),
      onLongPress: () => _onDayLongPress(date, today),
    );
  }
}
