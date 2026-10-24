// Спільні елементи інтерфейсу: картка, картка норми, сітка місяця,
// клітинка дня, коротке повідомлення (тост).
// Їх використовують і «Календар», і «Планування».

import 'dart:async';

import 'package:flutter/material.dart';

import 'logic.dart';

// ─────────────────────────────────────────────────────────────
// Картка
// ─────────────────────────────────────────────────────────────

/// Велика закруглена картка з тонкою рамкою.
/// [glow] додає м'яке акцентне сяйво в кутку (як на референсах).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.fromLTRB(12, 6, 12, 6),
    this.color,
    this.glow = false,
    this.borderColor,
    this.borderWidth = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final bool glow;

  /// Колір рамки (за замовчуванням — тонка сіра рамка).
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = color ?? scheme.surfaceContainer;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: glow ? null : base,
        gradient: glow
            ? LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color.alphaBlend(scheme.primary.withAlpha(dark ? 60 : 40), base),
            base,
          ],
          stops: const [0.0, 0.65],
        )
            : null,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: borderColor ?? scheme.outlineVariant,
          width: borderWidth,
        ),
      ),
      // ClipRRect + прозорий Material потрібні, щоб ListTile усередині
      // картки красиво підсвічувався при натисканні.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Рядок «підпис — значення» для карток зі статистикою.
class StatLine extends StatelessWidget {
  const StatLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Маленька «пігулка» з іконкою й текстом.
class InfoChip extends StatelessWidget {
  const InfoChip(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Велика картка: кільце прогресу, години, залишок і додаткові «пігулки».
class NormCard extends StatelessWidget {
  const NormCard({
    super.key,
    required this.title,
    required this.worked,
    required this.norm,
    this.note,
    this.chips = const [],
  });

  final String title;
  final int worked;
  final int norm;
  final String? note;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final percent = (worked * 100 / norm).round();
    final progress = (worked / norm).clamp(0.0, 1.0);
    final done = worked >= norm;

    return AppCard(
      glow: true,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        color: scheme.primary,
                        backgroundColor: scheme.outlineVariant,
                      ),
                    ),
                    Text(
                      '$percent %',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fmtHours(worked)} з ${fmtHours(norm)}',
                      style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done
                          ? 'Норму виконано. Переробка: ${fmtHours(worked - norm)}'
                          : 'Лишилось: ${fmtHours(norm - worked)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                note!,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: chips),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Сітка місяця
// ─────────────────────────────────────────────────────────────

/// Клітинка одного дня в сітці місяця.
class DayCellBox extends StatelessWidget {
  const DayCellBox({
    super.key,
    required this.day,
    required this.background,
    required this.foreground,
    this.minutes,
    this.isToday = false,
    this.outline = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final int day;
  final Color background;
  final Color foreground;
  final int? minutes;
  final bool isToday;

  /// Рамка (для запланованих виходів).
  final bool outline;

  /// День вибрано (режим вибору кількох днів).
  final bool selected;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = minutes;

    var side = BorderSide.none;
    if (outline) side = BorderSide(color: scheme.primary, width: 1.5);
    if (isToday) side = BorderSide(color: scheme.primary, width: 2.5);
    if (selected) side = BorderSide(color: scheme.tertiary, width: 3);

    // Сьогодні без виходу — яскрава акцентна клітинка (як «кружечок» на референсі).
    final todayAccent = isToday && m == null;
    final bg = todayAccent ? scheme.primary : background;
    final fg = todayAccent ? scheme.onPrimary : foreground;

    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: side,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Center(
              // FittedBox стискає вміст, якщо клітинка на вузькому екрані
              // трохи менша за текст, — нічого не вилазить за межі.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        height: 1.1,
                        fontWeight: (isToday || m != null)
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                    if (m != null)
                      Text(
                        shortHours(m),
                        style: TextStyle(color: fg, fontSize: 11, height: 1.1),
                      ),
                  ],
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: 2,
                right: 2,
                child: Icon(Icons.check_circle, size: 16, color: scheme.tertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Сітка місяця: рядок «Пн…Нд» і клітинки днів.
/// Вміст клітинки дає [cellBuilder].
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.cellBuilder,
    this.bottomPadding = 96,
  });

  final int year;
  final int month;
  final Widget Function(DateTime date) cellBuilder;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    // Скільки порожніх клітинок перед 1-м числом (понеділок = 0).
    final offset = DateTime(year, month, 1).weekday - 1;
    final days = daysInMonth(year, month);

    // Сітка не прокручується сама: її прокручує вся сторінка (ListView),
    // тому на низьких екранах нічого не стискається й не вилазить.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (final name in kWeekdaysShort)
                Expanded(
                  child: Center(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.85,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: offset + days,
          itemBuilder: (context, index) {
            if (index < offset) return const SizedBox.shrink();
            final date = DateTime(year, month, index - offset + 1);
            return cellBuilder(date);
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Тост
// ─────────────────────────────────────────────────────────────

/// Останнє показане повідомлення (щоб таймер не закрив чуже).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _lastToast;

/// Коротке повідомлення знизу. Зникає САМЕ через 2 секунди.
/// Якщо передано [onAction], з'являється кнопка (наприклад, «Скасувати»).
void showToast(
    BuildContext context,
    String text, {
      String actionLabel = 'Скасувати',
      VoidCallback? onAction,
      double bottomMargin = 88,
    }) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
      duration: const Duration(seconds: 2),
      content: Text(text),
      action: onAction == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction),
    ),
  );
  _lastToast = controller;
  // Страховка: повідомлення з кнопкою в новіших версіях Flutter
  // саме не зникає, тому закриваємо його вручну.
  Timer(const Duration(seconds: 2), () {
    if (identical(_lastToast, controller)) {
      messenger.hideCurrentSnackBar();
    }
  });
}
