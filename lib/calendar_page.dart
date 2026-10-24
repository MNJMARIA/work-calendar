// Вкладка «Календар»: місяць / тиждень / день, таймер, вибір кількох днів.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'dialogs.dart';
import 'logic.dart';
import 'settings_page.dart';
import 'sync/sync_indicator.dart';
import 'widgets.dart';

/// Вигляд календаря.
enum ViewMode { month, week, day }

/// Що користувач обрав у вікні завершення таймера.
enum _FinishChoice { save, keepGoing, discard }

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.state});

  final AppState state;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  ViewMode _mode = ViewMode.month;

  /// Дата, на якій «стоїть» календар (без часу).
  late DateTime _focus;

  /// Яка дата була «сьогодні» під час останнього оновлення.
  late DateTime _lastDay;

  /// Щосекундний годинник: оновлює екран, поки йде таймер,
  /// і коли настає нова доба.
  Timer? _ticker;

  /// Вибрані дні (режим вибору кількох днів).
  final Set<DateTime> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _focus = dateOnly(DateTime.now());
    _lastDay = _focus;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final day = dateOnly(DateTime.now());
      if (_state.timerRunning || day != _lastDay) {
        _lastDay = day;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ── Навігація ─────────────────────────────────────────────

  /// Крок назад (-1) або вперед (+1): місяць, тиждень чи день.
  void _step(int delta) {
    setState(() {
      if (_mode == ViewMode.month) {
        final target = DateTime(_focus.year, _focus.month + delta, 1);
        final today = dateOnly(DateTime.now());
        final isCurrent =
            target.year == today.year && target.month == today.month;
        _focus = isCurrent ? today : target;
      } else if (_mode == ViewMode.week) {
        _focus = addDays(_focus, 7 * delta);
      } else {
        _focus = addDays(_focus, delta);
      }
    });
  }

  void _goToToday() {
    setState(() => _focus = dateOnly(DateTime.now()));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(state: _state)),
    );
  }

  /// Заголовок між стрілками.
  String _navTitle() {
    if (_mode == ViewMode.month) {
      return '${kMonthsNominative[_focus.month - 1]} ${_focus.year}';
    }
    if (_mode == ViewMode.week) {
      final a = mondayOf(_focus);
      final b = addDays(a, 6);
      return '${a.day}.${pad2(a.month)} – ${b.day}.${pad2(b.month)}.${b.year}';
    }
    return '${_focus.day} ${kMonthsGenitive[_focus.month - 1]}, '
        '${kWeekdaysFull[_focus.weekday - 1]}';
  }

  // ── Вибір кількох днів ────────────────────────────────────

  void _toggle(DateTime date) {
    setState(() {
      if (!_selected.remove(date)) _selected.add(date);
    });
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  /// Вибрати всі дні місяця (або тижня, якщо відкрито «Тиждень»).
  void _selectAll() {
    final DateTime from;
    final DateTime to;
    if (_mode == ViewMode.week) {
      from = mondayOf(_focus);
      to = addDays(from, 6);
    } else {
      from = DateTime(_focus.year, _focus.month, 1);
      to = DateTime(_focus.year, _focus.month, daysInMonth(_focus.year, _focus.month));
    }
    setState(() {
      var d = from;
      while (!d.isAfter(to)) {
        _selected.add(d);
        d = addDays(d, 1);
      }
    });
  }

  /// Один тап по дню: у режимі вибору — відмітити, інакше — редагувати.
  void _onDayTap(DateTime date, DateTime today) {
    if (_selecting) {
      _toggle(date);
    } else {
      _editDay(date, today);
    }
  }

  /// Масове редагування вибраних днів.
  Future<void> _bulkEdit() async {
    final dates = _selected.toList()..sort();
    final result = await showShiftSheet(
      context,
      title: 'Вибрано днів: ${dates.length}',
      hint: 'Усім вибраним дням буде встановлено однакову тривалість. '
          'Минулі дні теж змінюються. Зміну можна скасувати.',
      initialMinutes: _state.defaultShiftMinutes,
      saveLabel: 'Застосувати до ${dates.length} дн.',
      removeLabel: 'Прибрати виходи у вибраних днях',
    );
    if (result == null || !mounted) return;
    _applyWithUndo(dates, result.minutes);
    _clearSelection();
  }

  void _bulkRemove() {
    final dates = _selected.toList()..sort();
    _applyWithUndo(dates, null);
    _clearSelection();
  }

  /// Змінити виходи й показати повідомлення з кнопкою «Скасувати».
  void _applyWithUndo(List<DateTime> dates, int? minutes) {
    final previous = _state.setShifts(dates, minutes);
    showToast(
      context,
      minutes == null
          ? 'Виходи прибрано: ${dates.length}'
          : 'Збережено: ${dates.length} дн. по ${fmtHours(minutes)}',
      onAction: () => _state.restoreShifts(previous),
    );
  }

  // ── Редагування одного дня ────────────────────────────────

  Future<void> _editDay(DateTime date, DateTime today) async {
    final existing = _state.shifts[dayKey(date)];
    final isFuture = date.isAfter(today);

    final String hint;
    if (_state.isTimerDay(date)) {
      hint = 'Зараз іде таймер. Після його завершення час збережеться в цей день.';
    } else if (isFuture) {
      hint = 'Майбутній вихід — це план. У «відпрацьовано» він не рахується.';
    } else {
      hint = 'Скільки годин тривав вихід на роботу?';
    }

    final result = await showShiftSheet(
      context,
      title: '${date.day} ${kMonthsGenitive[date.month - 1]}, '
          '${kWeekdaysFull[date.weekday - 1]}',
      hint: hint,
      initialMinutes: existing ?? _state.defaultShiftMinutes,
      saveLabel: existing == null ? 'Додати вихід на роботу' : 'Зберегти зміни',
      removeLabel: existing != null ? 'Прибрати вихід' : null,
      // Для сьогодні: можна не вводити години, а запустити відлік.
      offerTimer: date == today && !_state.timerRunning,
    );
    if (result == null || !mounted) return;
    if (result.startTimer) {
      await _startTimer();
      return;
    }
    _applyWithUndo([date], result.minutes);
  }

  // ── Таймер ────────────────────────────────────────────────

  Future<void> _startTimer() async {
    final start = await showStartWorkDialog(context);
    if (start == null || !mounted) return;
    _state.startTimer(start);
    setState(() => _focus = dateOnly(DateTime.now()));

    showToast(
      context,
      'Відлік іде з ${pad2(start.hour)}:${pad2(start.minute)}',
    );
  }

  /// Змінити час початку вже запущеного таймера.
  Future<void> _editTimerStart() async {
    final start = _state.timerStart;
    if (start == null) return;
    final picked = await pickTime24(
      context,
      TimeOfDay(hour: start.hour, minute: start.minute),
    );
    if (picked == null || !mounted) return;
    _state.setTimerStart(
      resolveStartTime(DateTime.now(), picked.hour, picked.minute),
    );
  }

  Future<void> _finishTimer() async {
    final start = _state.timerStart;
    if (start == null) return;

    final minutes = _state.elapsedSeconds(DateTime.now()) ~/ 60;
    final shown = minutes < 1 ? 1 : minutes;

    final choice = await showDialog<_FinishChoice>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Завершити роботу?'),
          content: Text(
            'Зберегти ${fmtHours(shown)} за '
                '${start.day} ${kMonthsGenitive[start.month - 1]}?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FinishChoice.discard),
              child: const Text('Скасувати таймер'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FinishChoice.keepGoing),
              child: const Text('Продовжити'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, _FinishChoice.save),
              child: const Text('Зберегти'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (choice == _FinishChoice.save) {
      _state.finishTimer(DateTime.now());
    } else if (choice == _FinishChoice.discard) {
      _state.discardTimer();
    }
    // keepGoing або закрили вікно — нічого не робимо, таймер іде далі.
  }

  // ── Побудова екрана ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final now = DateTime.now();
        final today = dateOnly(now);
        final running = _state.timerRunning;

        return PopScope(
          // Кнопка «Назад» у режимі вибору лише знімає вибір.
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _clearSelection();
          },
          child: Scaffold(
            appBar: _selecting ? _buildSelectionBar() : _buildNormalBar(),
            floatingActionButton: _selecting
                ? null
                : (running
                ? FloatingActionButton.extended(
              onPressed: _finishTimer,
              icon: const Icon(Icons.stop),
              label: const Text('Завершив роботу'),
            )
                : FloatingActionButton.extended(
              onPressed: _startTimer,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Вийшов на роботу'),
            )),
            // ListView: вся сторінка прокручується, тож на низькому екрані
            // нічого не стискається (раніше сітка могла «вилізти» за межі).
            body: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSummary(today, now),
                _buildModeSwitch(),
                _buildNavRow(),
                if (running) _buildTimerCard(now),
                _buildContent(today, now),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _buildNormalBar() {
    return AppBar(
      title: const Text('Робочий календар'),
      actions: [
        const SyncIndicator(),
        IconButton(
          tooltip: 'Сьогодні',
          onPressed: _goToToday,
          icon: const Icon(Icons.today),
        ),
        IconButton(
          tooltip: 'Налаштування',
          onPressed: _openSettings,
          icon: const Icon(Icons.settings),
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
          tooltip: 'Вибрати всі',
          onPressed: _selectAll,
          icon: const Icon(Icons.select_all),
        ),
        IconButton(
          tooltip: 'Змінити години',
          onPressed: _bulkEdit,
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          tooltip: 'Прибрати виходи',
          onPressed: _bulkRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  /// Верхня картка: норма місяця, прогрес, залишок і план.
  /// Видно завжди, в будь-якому вигляді календаря.
  Widget _buildSummary(DateTime today, DateTime now) {
    final year = _focus.year;
    final month = _focus.month;
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month, daysInMonth(year, month));

    final norm = monthNormMinutes(year, month);
    final worked = _state.workedBetween(first, last, today, now);
    // У плані — майбутні виходи цього місяця.
    final planned = sumRange(_state.shifts, first, last) -
        sumRange(_state.shifts, first, last, until: today);

    // «Пігулки» із залишком показуємо лише якщо це не вимкнено в налаштуваннях.
    final chips = <Widget>[];
    if (_state.showRemaining) {
      final target = _state.dayTarget(today);
      final dayLeft = _state.dayLeft(today, today, now);
      final String dayText;
      if (target == 0) {
        dayText = 'Сьогодні вихідний';
      } else if (dayLeft == 0) {
        dayText = 'Сьогодні: план виконано';
      } else {
        dayText = 'Сьогодні ще ${fmtHours(dayLeft)}';
      }
      chips.add(InfoChip(Icons.today, dayText));
      chips.add(
        InfoChip(
          Icons.date_range,
          'Тиждень: ще ${fmtHours(_state.weekLeft(today, today, now))}',
        ),
      );
    }

    return NormCard(
      title: '${kMonthsNominative[month - 1]} $year · норма ${fmtHours(norm)}',
      worked: worked,
      norm: norm,
      note: planned > 0
          ? 'У плані ще ${fmtHours(planned)} — майбутні виходи не рахуються'
          : null,
      chips: chips,
    );
  }

  /// Перемикач «Місяць / Тиждень / День».
  Widget _buildModeSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ViewMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ViewMode.month, label: Text('Місяць')),
            ButtonSegment(value: ViewMode.week, label: Text('Тиждень')),
            ButtonSegment(value: ViewMode.day, label: Text('День')),
          ],
          selected: {_mode},
          onSelectionChanged: (set) {
            setState(() {
              _mode = set.first;
              if (_mode == ViewMode.day) _selected.clear();
            });
          },
        ),
      ),
    );
  }

  /// Стрілки «назад / вперед» із заголовком посередині.
  Widget _buildNavRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Назад',
            onPressed: () => _step(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              _navTitle(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Вперед',
            onPressed: () => _step(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  /// Картка з годинником, поки йде робота. Натиснути — змінити час початку.
  Widget _buildTimerCard(DateTime now) {
    final start = _state.timerStart!;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: _editTimerStart,
        leading: Icon(Icons.timer, color: scheme.onPrimaryContainer),
        title: Text(
          'Йде робота',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        subtitle: Text(
          'Початок о ${pad2(start.hour)}:${pad2(start.minute)} · натисни, щоб змінити',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        trailing: Text(
          fmtClock(_state.elapsedSeconds(now)),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(DateTime today, DateTime now) {
    return switch (_mode) {
      ViewMode.month => _buildMonth(today, now),
      ViewMode.week => _buildWeek(today, now),
      ViewMode.day => _buildDay(today, now),
    };
  }

  // ── Вигляд «Місяць» ───────────────────────────────────────

  Widget _buildMonth(DateTime today, DateTime now) {
    return MonthGrid(
      year: _focus.year,
      month: _focus.month,
      cellBuilder: (date) => _buildDayCell(date, today, now),
    );
  }

  /// Одна клітинка дня.
  Widget _buildDayCell(DateTime date, DateTime today, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final timerDay = _state.isTimerDay(date);
    // У день із таймером показуємо, скільки вже набігло.
    final int? minutes = timerDay
        ? _state.elapsedSeconds(now) ~/ 60
        : _state.shifts[dayKey(date)];
    final isFuture = date.isAfter(today);
    final isWeekend = date.weekday >= DateTime.saturday;

    // Колір залежить від стану дня:
    //  • вихід у минулому/сьогодні (факт) — залита клітинка;
    //  • вихід у майбутньому (план) — клітинка з рамкою;
    //  • звичайний день — світла клітинка.
    Color background = scheme.surfaceContainerLow;
    Color foreground = isWeekend ? scheme.error : scheme.onSurface;
    var outline = false;

    if (minutes != null && !isFuture) {
      background = scheme.primaryContainer;
      foreground = scheme.onPrimaryContainer;
    } else if (minutes != null) {
      background = scheme.surface;
      foreground = scheme.onSurface;
      outline = true;
    }

    return DayCellBox(
      day: date.day,
      background: background,
      foreground: foreground,
      minutes: minutes,
      isToday: date == today,
      outline: outline,
      selected: _selected.contains(date),
      onTap: () => _onDayTap(date, today),
      onLongPress: () => _toggle(date),
    );
  }

  // ── Вигляд «Тиждень» ──────────────────────────────────────

  Widget _buildWeek(DateTime today, DateTime now) {
    final monday = mondayOf(_focus);
    final sunday = addDays(monday, 6);
    final worked = _state.workedBetween(monday, sunday, today, now);
    final left = kWeekNormMinutes > worked ? kWeekNormMinutes - worked : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
      child: Column(
        children: [
          AppCard(
            margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Column(
              children: [
                StatLine('Відпрацьовано за тиждень', fmtHours(worked)),
                if (_state.showRemaining)
                  StatLine('Лишилось до ${fmtHours(kWeekNormMinutes)}', fmtHours(left)),
              ],
            ),
          ),
          _buildWeekLegend(),
          for (var i = 0; i < 7; i++) _buildWeekRow(addDays(monday, i), today, now),
        ],
      ),
    );
  }

  /// Кольори днів у вигляді «Тиждень»: підказка, що означає кожен колір.
  Widget _buildWeekLegend() {
    final scheme = Theme.of(context).colorScheme;
    Widget dot(Color color, String label, {Color? border}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: border == null ? null : Border.all(color: border, width: 2),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          dot(scheme.surfaceContainer, 'Сьогодні', border: scheme.primary),
          dot(scheme.primaryContainer, 'Відпрацьовано'),
          dot(scheme.tertiaryContainer, 'У плані'),
          dot(_pastOffColor(scheme), 'Минулий вихідний'),
        ],
      ),
    );
  }

  /// Колір минулого вихідного: звичайний фон із легким червонуватим відтінком.
  Color _pastOffColor(ColorScheme scheme) =>
      Color.alphaBlend(scheme.error.withAlpha(40), scheme.surfaceContainer);

  Widget _buildWeekRow(DateTime date, DateTime today, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final timerDay = _state.isTimerDay(date);
    final minutes = _state.shifts[dayKey(date)];
    final isToday = date == today;
    final isFuture = date.isAfter(today);
    final isWeekend = date.weekday >= DateTime.saturday;
    final isSelected = _selected.contains(date);

    // Скільки годин показати справа і який підпис під назвою дня.
    int? shown;
    String subtitle;
    if (timerDay) {
      shown = _state.elapsedSeconds(now) ~/ 60;
      subtitle = 'Йде робота';
    } else if (minutes != null) {
      shown = minutes;
      subtitle = isFuture ? 'У плані' : 'Відпрацьовано';
    } else {
      shown = null;
      subtitle = isWeekend ? 'Вихідний' : 'Немає виходу';
    }

    // Колір рядка за видом дня (логіка dayKind перевірена тестами).
    final kind = dayKind(date, today, hasShift: timerDay || minutes != null);
    final Color rowColor;
    final Color rowText;
    switch (kind) {
      case DayKind.worked:
        rowColor = scheme.primaryContainer;
        rowText = scheme.onPrimaryContainer;
      case DayKind.planned:
        rowColor = scheme.tertiaryContainer;
        rowText = scheme.onTertiaryContainer;
      case DayKind.pastOff:
        rowColor = _pastOffColor(scheme);
        rowText = scheme.onSurface;
      case DayKind.today:
      case DayKind.none:
        rowColor = scheme.surfaceContainer;
        rowText = scheme.onSurface;
    }

    return AppCard(
      key: Key('week-row-${dayKey(date)}'),
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      padding: EdgeInsets.zero,
      color: isSelected ? scheme.tertiaryContainer : rowColor,
      // Сьогодні — яскрава акцентна рамка.
      borderColor: isToday ? scheme.primary : null,
      borderWidth: isToday ? 2.5 : 1,
      child: ListTile(
        textColor: isSelected ? scheme.onTertiaryContainer : rowText,
        onTap: () => _onDayTap(date, today),
        onLongPress: () => _toggle(date),
        leading: CircleAvatar(
          // Сьогодні — акцентний кружечок.
          backgroundColor: isToday ? scheme.primary : scheme.surfaceContainerHighest,
          foregroundColor: isToday ? scheme.onPrimary : scheme.onSurface,
          child: isSelected ? const Icon(Icons.check) : Text('${date.day}'),
        ),
        title: Text(capitalize(kWeekdaysFull[date.weekday - 1])),
        subtitle: Text(subtitle),
        trailing: shown != null
            ? Text(fmtHours(shown), style: Theme.of(context).textTheme.titleMedium)
            : const Icon(Icons.add),
      ),
    );
  }

  // ── Вигляд «День» ─────────────────────────────────────────

  Widget _buildDay(DateTime today, DateTime now) {
    final date = _focus;
    final minutes = _state.shifts[dayKey(date)];
    final isFuture = date.isAfter(today);
    final isToday = date == today;
    final timerDay = _state.isTimerDay(date);

    final worked = _state.dayWorked(date, today, now);
    final left = _state.dayLeft(date, today, now);

    final String status;
    if (timerDay) {
      status = 'Йде робота';
    } else if (minutes != null && isFuture) {
      status = 'Вихід у плані';
    } else if (minutes != null) {
      status = 'Вихід відпрацьовано';
    } else {
      status = 'Виходу немає';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      child: Column(
        children: [
          AppCard(
            glow: true,
            margin: const EdgeInsets.fromLTRB(0, 4, 0, 4),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                StatLine('Відпрацьовано', fmtHours(worked)),
                if (minutes != null && isFuture)
                  StatLine('У плані', fmtHours(minutes)),
                if (_state.showRemaining && isToday)
                  StatLine('Лишилось до плану дня', fmtHours(left)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _editDay(date, today),
                    child: Text(
                      minutes == null ? 'Додати вихід на роботу' : 'Змінити вихід',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
