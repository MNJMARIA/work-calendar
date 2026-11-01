// Екран «Звіт»: вибір періоду (день, тиждень, місяць) і імені, перегляд PDF,
// кнопки «Поділитись або зберегти», «В архів» і «Друк».

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../diagnostics.dart';
import '../logic.dart';
import 'month_report.dart';
import 'report_archive.dart';

/// Шрифти для PDF (звичайний і жирний).
class ReportFonts {
  const ReportFonts(this.regular, this.bold);

  final Uint8List regular;
  final Uint8List bold;
}

/// Читає шрифти з ресурсів додатка (assets/fonts).
Future<ReportFonts> loadAssetReportFonts() async {
  Uint8List bytes(ByteData d) => d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  final regular = await rootBundle.load('assets/fonts/LiberationSerif-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/LiberationSerif-Bold.ttf');
  return ReportFonts(bytes(regular), bytes(bold));
}

class MonthReportPage extends StatefulWidget {
  const MonthReportPage({
    super.key,
    required this.state,
    required this.initialMonth,
    this.initialKind = ReportKind.month,
    this.suggestedName = '',
    this.archive,
    this.pdfBuilder,
    this.clock,
    this.previewBuilder,
    this.onShare,
    this.onPrint,
  });

  final AppState state;

  /// Будь-яка дата потрібного періоду (для місяця — його перший день або будь-який інший).
  final DateTime initialMonth;

  /// За який період відкрити звіт спочатку.
  final ReportKind initialKind;

  /// Ім'я, яке підставити, якщо користувач ще не вводив своє (ім'я з акаунта).
  final String suggestedName;

  /// Архів, куди можна зберегти звіт (null — кнопки архіву немає).
  final ReportArchive? archive;

  /// Для тестів: власне складання PDF, годинник, перегляд і кнопки.
  final Future<Uint8List> Function(
      MonthReport report,
      String employee,
      DateTime generatedAt,
      bool onlyShiftDays,
      double textScale,
      )? pdfBuilder;
  final DateTime Function()? clock;
  final Widget Function(BuildContext context, Uint8List pdf, String fileName)? previewBuilder;
  final Future<void> Function(Uint8List pdf, String fileName)? onShare;
  final Future<void> Function(Uint8List pdf, String fileName)? onPrint;

  @override
  State<MonthReportPage> createState() => _MonthReportPageState();
}

class _MonthReportPageState extends State<MonthReportPage> {
  late DateTime _anchor;
  late ReportKind _kind;
  final TextEditingController _name = TextEditingController();
  bool _onlyShiftDays = false;
  Uint8List? _pdf;
  String? _error;
  Timer? _debounce;
  int _serial = 0;
  bool _archiving = false;

  double get _scale => kReportTextScales[widget.state.reportTextSize.clamp(0, 2)];

  DateTime _now() => (widget.clock ?? DateTime.now)();

  ({DateTime from, DateTime to}) get _range => reportRange(_kind, _anchor);

  String get _fileName => reportFileNameFor(_kind, _range.from, _range.to);

  String get _title => reportPeriodTitle(_kind, _range.from, _range.to);

  MonthReport _makeReport(DateTime now) => MonthReport.forKind(
    _kind,
    _anchor,
    shifts: widget.state.shifts,
    today: now,
  );

  @override
  void initState() {
    super.initState();
    _anchor = dateOnly(widget.initialMonth);
    _kind = widget.initialKind;
    final saved = widget.state.employeeName;
    _name.text = saved.isNotEmpty ? saved : widget.suggestedName;
    _build();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final serial = ++_serial;
    setState(() => _error = null);
    try {
      final now = _now();
      final report = _makeReport(now);
      final custom = widget.pdfBuilder;
      final Uint8List bytes;
      if (custom != null) {
        bytes = await custom(report, _name.text.trim(), now, _onlyShiftDays, _scale);
      } else {
        final fonts = await loadAssetReportFonts();
        bytes = await buildMonthReportPdf(
          report,
          employee: _name.text.trim(),
          generatedAt: now,
          regularFont: fonts.regular,
          boldFont: fonts.bold,
          onlyShiftDays: _onlyShiftDays,
          textScale: _scale,
        );
      }
      if (!mounted || serial != _serial) return;
      setState(() => _pdf = bytes);
    } catch (e) {
      AppLog.add('звіт: не вдалося сформувати PDF: $e');
      if (!mounted || serial != _serial) return;
      setState(() => _error = 'Не вдалося сформувати звіт. $e');
    }
  }

  void _shiftPeriod(int delta) {
    setState(() {
      switch (_kind) {
        case ReportKind.month:
          _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
        case ReportKind.week:
          _anchor = addDays(_anchor, 7 * delta);
        case ReportKind.day:
          _anchor = addDays(_anchor, delta);
      }
      _pdf = null;
    });
    _build();
  }

  void _changeKind(ReportKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _pdf = null;
    });
    _build();
  }

  void _nameChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      widget.state.setEmployeeName(_name.text);
      _build();
    });
  }

  Future<void> _share() async {
    final pdf = _pdf;
    if (pdf == null) return;
    try {
      final action = widget.onShare ??
              (Uint8List bytes, String name) => Printing.sharePdf(bytes: bytes, filename: name);
      await action(pdf, _fileName);
    } catch (e) {
      AppLog.add('звіт: не вдалося поділитись: $e');
      _toast('Не вдалося поділитись звітом.');
    }
  }

  Future<void> _print() async {
    final pdf = _pdf;
    if (pdf == null) return;
    try {
      final action = widget.onPrint ??
              (Uint8List bytes, String name) async {
            await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
          };
      await action(pdf, _fileName);
    } catch (e) {
      AppLog.add('звіт: не вдалося відкрити друк: $e');
      _toast('Не вдалося відкрити вікно друку.');
    }
  }

  Future<void> _saveToArchive() async {
    final pdf = _pdf;
    final archive = widget.archive;
    if (pdf == null || archive == null || _archiving) return;
    setState(() => _archiving = true);
    try {
      final range = _range;
      await archive.add(
        year: range.from.year,
        month: range.from.month,
        kind: _kind,
        from: range.from,
        to: range.to,
        employee: _name.text.trim(),
        createdAt: _now(),
        onlyShiftDays: _onlyShiftDays,
        pdf: pdf,
      );
      _toast('Звіт збережено в архіві (вкладка «Звіти»).');
    } catch (e) {
      AppLog.add('звіт: не вдалося зберегти в архів: $e');
      _toast('Не вдалося зберегти звіт в архів.');
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _preview(BuildContext context) {
    final pdf = _pdf;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            key: const Key('report-error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (pdf == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final custom = widget.previewBuilder;
    if (custom != null) return custom(context, pdf, _fileName);
    return PdfPreview(
      key: ValueKey('$_title-${pdf.length}-${pdf.hashCode}'),
      build: (_) => pdf,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      pdfFileName: _fileName,
      maxPageWidth: 700,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _pdf != null && _error == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Звіт'),
        actions: [
          IconButton(
            key: const Key('report-print'),
            tooltip: 'Друк',
            onPressed: ready ? _print : null,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ReportKind>(
                      key: const Key('report-kind'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [
                        for (final k in ReportKind.values)
                          ButtonSegment<ReportKind>(
                            value: k,
                            label: Text(kReportKindLabels[k.index], key: Key('report-kind-${k.name}')),
                          ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (values) => _changeKind(values.first),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        key: const Key('report-prev'),
                        tooltip: 'Попередній період',
                        onPressed: () => _shiftPeriod(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _title,
                            key: const Key('report-title'),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('report-next'),
                        tooltip: 'Наступний період',
                        onPressed: () => _shiftPeriod(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  TextField(
                    key: const Key('report-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    onChanged: _nameChanged,
                    decoration: const InputDecoration(
                      labelText: 'Працівник (ПІБ для звіту)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Розмір тексту у звіті', style: theme.textTheme.labelLarge),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      key: const Key('report-text-size'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
                      ),
                      segments: [
                        for (var i = 0; i < kReportTextLabels.length; i++)
                          ButtonSegment<int>(
                            value: i,
                            label: Text(
                              kReportTextLabels[i],
                              key: Key('report-text-size-$i'),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      selected: {widget.state.reportTextSize.clamp(0, 2)},
                      onSelectionChanged: (values) {
                        widget.state.setReportTextSize(values.first);
                        setState(() => _pdf = null);
                        _build();
                      },
                    ),
                  ),
                  if (_kind != ReportKind.day)
                    SwitchListTile(
                      key: const Key('report-only-shifts'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Лише дні з виходами'),
                      value: _onlyShiftDays,
                      onChanged: (v) {
                        setState(() {
                          _onlyShiftDays = v;
                          _pdf = null;
                        });
                        _build();
                      },
                    ),
                ],
              ),
            ),
            Expanded(child: _preview(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('report-share'),
                      onPressed: ready ? _share : null,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Поділитись або зберегти'),
                    ),
                  ),
                  if (widget.archive != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      key: const Key('report-archive'),
                      onPressed: (ready && !_archiving) ? _saveToArchive : null,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('В архів'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
