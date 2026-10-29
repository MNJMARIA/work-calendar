// Місячний звіт про відпрацьований робочий час: розрахунки та PDF.
//
// Розрахунки (MonthReport) — чистий Dart, їх перевіряють тести.
// PDF збирається пакетом `pdf` у діловому стилі: заголовок, підсумок, таблиця
// по тижнях, щоденний облік, місця для підписів.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic.dart';

// ─────────────────────────────────────────────────────────────
// Розрахунки
// ─────────────────────────────────────────────────────────────

/// Один день у звіті.
class ReportDay {
  const ReportDay({
    required this.date,
    required this.minutes,
    required this.future,
  });

  final DateTime date;

  /// Тривалість виходу в хвилинах (0 — виходу немає).
  final int minutes;

  /// День після «сьогодні»: вихід лише запланований.
  final bool future;

  bool get weekend => date.weekday >= DateTime.saturday;
  bool get hasShift => minutes > 0;
}

/// Підсумок за тиждень (частина тижня, що потрапила в місяць).
class ReportWeek {
  const ReportWeek({
    required this.from,
    required this.to,
    required this.shifts,
    required this.minutes,
    required this.normMinutes,
  });

  final DateTime from;
  final DateTime to;
  final int shifts;
  final int minutes;
  final int normMinutes;
}

class MonthReport {
  MonthReport({
    required this.year,
    required this.month,
    required Map<String, int> shifts,
    required DateTime today,
  })  : today = dateOnly(today),
        days = _buildDays(year, month, shifts, dateOnly(today)) {
    normMinutes = monthNormMinutes(year, month);
    normWorkdays = workdaysInMonth(year, month);
    for (final d in days) {
      if (!d.hasShift) continue;
      if (d.future) {
        plannedMinutes += d.minutes;
        plannedShifts++;
      } else {
        workedMinutes += d.minutes;
        workedShifts++;
        if (d.minutes > longestMinutes) longestMinutes = d.minutes;
      }
    }
    weeks = _buildWeeks();
  }

  final int year;
  final int month;
  final DateTime today;
  final List<ReportDay> days;

  late final int normMinutes;
  late final int normWorkdays;
  int workedMinutes = 0;
  int workedShifts = 0;
  int plannedMinutes = 0;
  int plannedShifts = 0;
  int longestMinutes = 0;
  late final List<ReportWeek> weeks;

  DateTime get firstDay => DateTime(year, month, 1);
  DateTime get lastDay => DateTime(year, month, daysInMonth(year, month));

  /// Місяць уже закінчився (сьогодні пізніше за його останній день).
  bool get finished => today.isAfter(lastDay);

  /// Різниця з нормою: плюс — понаднормово, мінус — не вистачає.
  int get diffMinutes => workedMinutes - normMinutes;

  /// Середня тривалість виходу (0, якщо виходів не було).
  int get averageMinutes => workedShifts == 0 ? 0 : (workedMinutes / workedShifts).round();

  static List<ReportDay> _buildDays(
      int year,
      int month,
      Map<String, int> shifts,
      DateTime today,
      ) {
    final result = <ReportDay>[];
    for (var day = 1; day <= daysInMonth(year, month); day++) {
      final date = DateTime(year, month, day);
      result.add(
        ReportDay(
          date: date,
          minutes: shifts[dayKey(date)] ?? 0,
          future: date.isAfter(today),
        ),
      );
    }
    return result;
  }

  List<ReportWeek> _buildWeeks() {
    final result = <ReportWeek>[];
    var start = firstDay;
    while (!start.isAfter(lastDay)) {
      var end = addDays(mondayOf(start), 6);
      if (end.isAfter(lastDay)) end = lastDay;
      var minutes = 0;
      var count = 0;
      var workdays = 0;
      for (final d in days) {
        if (d.date.isBefore(start) || d.date.isAfter(end)) continue;
        if (d.date.weekday <= DateTime.friday) workdays++;
        if (d.hasShift && !d.future) {
          minutes += d.minutes;
          count++;
        }
      }
      result.add(
        ReportWeek(
          from: start,
          to: end,
          shifts: count,
          minutes: minutes,
          normMinutes: workdays * kDayNormMinutes,
        ),
      );
      start = addDays(end, 1);
    }
    return result;
  }
}

// ─────────────────────────────────────────────────────────────
// Текст
// ─────────────────────────────────────────────────────────────

/// 05.10.2026
String fmtDate(DateTime d) => '${pad2(d.day)}.${pad2(d.month)}.${d.year}';

/// Година з хвилинами, наприклад «176 год» або «12 год 30 хв»; нуль — «0 год».
String fmtDuration(int minutes) => fmtHours(minutes);

/// Різниця зі знаком: «+4 год», «−8 год 30 хв», «0 год».
String fmtSigned(int minutes) {
  if (minutes == 0) return '0 год';
  final sign = minutes > 0 ? '+' : '−';
  return '$sign${fmtHours(minutes.abs())}';
}

/// Назва файлу звіту: Zvit_2026-10.pdf
String reportFileName(int year, int month) => 'Zvit_$year-${pad2(month)}.pdf';

// ─────────────────────────────────────────────────────────────
// PDF
// ─────────────────────────────────────────────────────────────

final PdfColor _ink = PdfColor.fromInt(0xFF1B2433);
final PdfColor _accent = PdfColor.fromInt(0xFF1F3A5F);
final PdfColor _line = PdfColor.fromInt(0xFF8A93A3);
final PdfColor _band = PdfColor.fromInt(0xFFEEF1F6);
final PdfColor _weekend = PdfColor.fromInt(0xFFF6F7F9);
final PdfColor _muted = PdfColor.fromInt(0xFF5B6475);

ByteData _bytesOf(Uint8List list) =>
    ByteData.view(list.buffer, list.offsetInBytes, list.lengthInBytes);

/// Збирає PDF-звіт. [regularFont] і [boldFont] — файли шрифту з українськими
/// літерами (у додатку лежать у assets/fonts). Повертає готовий PDF-файл.
/// Розміри тексту звіту: звичайний, великий, дуже великий.
const List<double> kReportTextScales = [1.0, 1.25, 1.5];
const List<String> kReportTextLabels = ['Звичайний', 'Великий', 'Дуже великий'];

Future<Uint8List> buildMonthReportPdf(
    MonthReport report, {
      required String employee,
      required DateTime generatedAt,
      required Uint8List regularFont,
      required Uint8List boldFont,
      bool onlyShiftDays = false,
      double textScale = 1.0,
    }) async {
  final base = pw.Font.ttf(_bytesOf(regularFont));
  final bold = pw.Font.ttf(_bytesOf(boldFont));
  final monthTitle = '${kMonthsNominative[report.month - 1]} ${report.year}';

  final doc = pw.Document(
    title: 'Звіт про відпрацьований робочий час, $monthTitle',
    author: employee.isEmpty ? 'Робочий календар' : employee,
    creator: 'Робочий календар',
    theme: pw.ThemeData.withFont(base: base, bold: bold, italic: base, boldItalic: bold),
  );

  pw.TextStyle style({double size = 10.5, bool strong = false, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size * textScale,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? _ink,
    );
  }

  pw.Widget cell(
      String text, {
        pw.Alignment alignment = pw.Alignment.centerLeft,
        bool strong = false,
        double size = 10,
        PdfColor? color,
      }) {
    return pw.Container(
      alignment: alignment,
      padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(text, style: style(size: size, strong: strong, color: color)),
    );
  }

  pw.Widget heading(String text) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: 16, bottom: 6),
      child: pw.Text(text, style: style(size: 12.5, strong: true, color: _accent)),
    );
  }

  pw.TableRow headerRow(List<String> titles, {List<pw.Alignment>? aligns}) {
    return pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: _band),
      children: [
        for (var i = 0; i < titles.length; i++)
          cell(
            titles[i],
            strong: true,
            size: 9.5,
            alignment: aligns == null ? pw.Alignment.centerLeft : aligns[i],
          ),
      ],
    );
  }

  final border = pw.TableBorder.all(color: _line, width: 0.5);

  // ── Підсумок ──
  final summaryRows = <List<String>>[
    [
      'Норма робочого часу за місяць',
      '${fmtDuration(report.normMinutes)} (${report.normWorkdays} робочих днів × 8 год)',
    ],
    ['Відпрацьовано (по сьогодні)', fmtDuration(report.workedMinutes)],
    ['Кількість виходів', '${report.workedShifts}'],
    [
      'Середня тривалість виходу',
      report.workedShifts == 0 ? '—' : fmtDuration(report.averageMinutes),
    ],
    [
      'Найдовший вихід',
      report.workedShifts == 0 ? '—' : fmtDuration(report.longestMinutes),
    ],
    if (report.finished)
      [
        report.diffMinutes >= 0 ? 'Понад норму' : 'Не вистачає до норми',
        fmtDuration(report.diffMinutes.abs()),
      ]
    else
      [
        'Лишилось до норми',
        fmtDuration(report.diffMinutes >= 0 ? 0 : -report.diffMinutes),
      ],
    if (report.plannedShifts > 0)
      [
        'Заплановано до кінця місяця',
        '${fmtDuration(report.plannedMinutes)} (${report.plannedShifts} виходів)',
      ],
  ];

  // ── Дні ──
  final shownDays = onlyShiftDays
      ? report.days.where((d) => d.hasShift).toList()
      : report.days;

  String note(ReportDay d) {
    if (d.hasShift) return d.future ? 'Заплановано' : 'Відпрацьовано';
    return d.weekend ? 'Вихідний' : '';
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(44, 44, 44, 52),
      footer: (context) => pw.Container(
        padding: pw.EdgeInsets.only(top: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Сформовано в додатку «Робочий календар»',
              style: style(size: 8.5, color: _muted),
            ),
            pw.Text(
              'Сторінка ${context.pageNumber} з ${context.pagesCount}',
              style: style(size: 8.5, color: _muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Center(
          child: pw.Text('ЗВІТ', style: style(size: 22, strong: true, color: _accent)),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'про відпрацьований робочий час',
            style: style(size: 14, strong: true),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'за ${kMonthsNominative[report.month - 1].toLowerCase()} ${report.year} року',
            style: style(size: 12.5),
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 1.5, color: _accent),
        pw.SizedBox(height: 12),
        pw.Table(
          columnWidths: {
            0: pw.FixedColumnWidth(120 * textScale),
            1: pw.FlexColumnWidth(),
          },
          children: [
            for (final row in [
              ['Працівник:', employee.isEmpty ? '________________________________' : employee],
              ['Звітний період:', '${fmtDate(report.firstDay)} – ${fmtDate(report.lastDay)}'],
              ['Дата формування:', fmtDate(generatedAt)],
            ])
              pw.TableRow(
                children: [
                  cell(row[0], strong: true, size: 11),
                  cell(row[1], size: 11),
                ],
              ),
          ],
        ),
        heading('1. Підсумок за місяць'),
        pw.Table(
          border: border,
          columnWidths: {
            0: pw.FlexColumnWidth(5),
            1: pw.FlexColumnWidth(6),
          },
          children: [
            for (final row in summaryRows)
              pw.TableRow(
                children: [
                  cell(row[0]),
                  cell(row[1], strong: true),
                ],
              ),
          ],
        ),
        heading('2. Розподіл за тижнями'),
        pw.Table(
          border: border,
          columnWidths: {
            0: pw.FixedColumnWidth(24 * textScale),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1.6),
            3: pw.FlexColumnWidth(2),
            4: pw.FlexColumnWidth(2),
            5: pw.FlexColumnWidth(2),
          },
          children: [
            headerRow(
              ['№', 'Період', 'Виходів', 'Відпрацьовано', 'Норма', 'Різниця'],
              aligns: [
                pw.Alignment.center,
                pw.Alignment.centerLeft,
                pw.Alignment.center,
                pw.Alignment.centerRight,
                pw.Alignment.centerRight,
                pw.Alignment.centerRight,
              ],
            ),
            for (var i = 0; i < report.weeks.length; i++)
              pw.TableRow(
                children: [
                  cell('${i + 1}', alignment: pw.Alignment.center),
                  cell('${fmtDate(report.weeks[i].from)} – ${fmtDate(report.weeks[i].to)}'),
                  cell('${report.weeks[i].shifts}', alignment: pw.Alignment.center),
                  cell(fmtDuration(report.weeks[i].minutes), alignment: pw.Alignment.centerRight),
                  cell(fmtDuration(report.weeks[i].normMinutes), alignment: pw.Alignment.centerRight),
                  cell(
                    fmtSigned(report.weeks[i].minutes - report.weeks[i].normMinutes),
                    alignment: pw.Alignment.centerRight,
                  ),
                ],
              ),
          ],
        ),
        heading('3. Щоденний облік'),
        pw.Table(
          border: border,
          columnWidths: {
            0: pw.FixedColumnWidth(24 * textScale),
            1: pw.FlexColumnWidth(2.2),
            2: pw.FlexColumnWidth(2.2),
            3: pw.FlexColumnWidth(2.2),
            4: pw.FlexColumnWidth(2.6),
          },
          children: [
            headerRow(
              ['№', 'Дата', 'День тижня', 'Тривалість', 'Примітка'],
              aligns: [
                pw.Alignment.center,
                pw.Alignment.centerLeft,
                pw.Alignment.centerLeft,
                pw.Alignment.centerRight,
                pw.Alignment.centerLeft,
              ],
            ),
            if (shownDays.isEmpty)
              pw.TableRow(
                children: [
                  cell(''),
                  cell('Виходів немає'),
                  cell(''),
                  cell(''),
                  cell(''),
                ],
              ),
            for (final d in shownDays)
              pw.TableRow(
                decoration: pw.BoxDecoration(color: d.weekend ? _weekend : null),
                children: [
                  cell('${d.date.day}', alignment: pw.Alignment.center, size: 9.5),
                  cell(fmtDate(d.date), size: 9.5),
                  cell(capitalize(kWeekdaysFull[d.date.weekday - 1]), size: 9.5),
                  cell(
                    d.hasShift ? fmtDuration(d.minutes) : '—',
                    alignment: pw.Alignment.centerRight,
                    strong: d.hasShift,
                    size: 9.5,
                  ),
                  cell(note(d), size: 9.5, color: d.future ? _muted : _ink),
                ],
              ),
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _band),
              children: [
                cell(''),
                cell('Разом', strong: true, size: 10),
                cell(''),
                cell(
                  fmtDuration(report.workedMinutes),
                  alignment: pw.Alignment.centerRight,
                  strong: true,
                  size: 10,
                ),
                cell('відпрацьовано', size: 9.5),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 28),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Працівник', style: style(size: 11)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: pw.Container(height: 0.8, color: _ink)),
            pw.SizedBox(width: 12),
            pw.Text('Дата', style: style(size: 11)),
            pw.SizedBox(width: 12),
            pw.SizedBox(width: 90 * textScale, child: pw.Container(height: 0.8, color: _ink)),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Padding(
          padding: pw.EdgeInsets.only(left: 64 * textScale),
          child: pw.Text('(підпис)', style: style(size: 8.5, color: _muted)),
        ),
        pw.SizedBox(height: 22),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Керівник', style: style(size: 11)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: pw.Container(height: 0.8, color: _ink)),
            pw.SizedBox(width: 12),
            pw.Text('Дата', style: style(size: 11)),
            pw.SizedBox(width: 12),
            pw.SizedBox(width: 90 * textScale, child: pw.Container(height: 0.8, color: _ink)),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Padding(
          padding: pw.EdgeInsets.only(left: 64 * textScale),
          child: pw.Text('(підпис)', style: style(size: 8.5, color: _muted)),
        ),
      ],
    ),
  );

  return doc.save();
}
