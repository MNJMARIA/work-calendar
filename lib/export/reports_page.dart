// Вкладка «Звіти»: кнопки створення звіту й архів збережених звітів
// (місяць, дата формування, ім'я, розмір). Звіт з архіву можна відкрити,
// переслати, надрукувати або видалити.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../diagnostics.dart';
import '../logic.dart';
import '../services.dart';
import 'month_report.dart';
import 'month_report_page.dart';
import 'report_archive.dart';

/// 25.10.2026 о 16:12
String fmtDateTime(DateTime d) => '${fmtDate(d)} о ${pad2(d.hour)}:${pad2(d.minute)}';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.state});

  final AppState state;

  void _openNew(BuildContext context, DateTime month) {
    final services = AppServicesScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MonthReportPage(
          state: state,
          initialMonth: month,
          suggestedName: services.account?.user?.name ?? '',
          archive: services.archive,
        ),
      ),
    );
  }

  void _openArchived(BuildContext context, ReportArchive archive, ArchivedReport item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArchivedReportPage(archive: archive, item: item),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ReportArchive archive, ArchivedReport item) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Видалити звіт?'),
        content: Text(
          '${kMonthsNominative[item.month - 1]} ${item.year}, сформовано ${fmtDateTime(item.createdAt)}. '
              'Скасувати це не вийде.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            key: const Key('archive-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (sure == true) await archive.remove(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    final archive = services.archive;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1);

    return Scaffold(
      appBar: AppBar(title: const Text('Звіти')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Звіт про відпрацьований час',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Офіційний документ PDF: підсумок за місяць, тижні, щоденний облік і місця для підписів.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          key: const Key('reports-current'),
                          onPressed: () => _openNew(context, now),
                          child: Text('Цей місяць'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('reports-previous'),
                          onPressed: () => _openNew(context, previous),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
                          child: const Text('Минулий місяць'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Архів звітів', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          if (archive == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Архів недоступний на цьому пристрої. Звіти все одно можна формувати й пересилати.',
                key: const Key('archive-unavailable'),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ListenableBuilder(
              listenable: archive,
              builder: (context, _) {
                final items = archive.items;
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Поки порожньо. Сформуй звіт і натисни «В архів»: він збережеться тут з датою й часом формування.',
                      key: const Key('archive-empty'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        key: Key('archive-item-${item.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text('${kMonthsNominative[item.month - 1]} ${item.year}'),
                        subtitle: Text(
                          'Сформовано ${fmtDateTime(item.createdAt)}\n'
                              '${item.employee.isEmpty ? 'без імені' : item.employee} · ${fmtSize(item.sizeBytes)}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          key: Key('archive-delete-${item.id}'),
                          tooltip: 'Видалити',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(context, archive, item),
                        ),
                        onTap: () => _openArchived(context, archive, item),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Перегляд збереженого звіту: PDF, «Поділитись», «Друк».
class ArchivedReportPage extends StatefulWidget {
  const ArchivedReportPage({
    super.key,
    required this.archive,
    required this.item,
    this.previewBuilder,
    this.onShare,
  });

  final ReportArchive archive;
  final ArchivedReport item;

  /// Для тестів.
  final Widget Function(BuildContext context, Uint8List pdf, String fileName)? previewBuilder;
  final Future<void> Function(Uint8List pdf, String fileName)? onShare;

  @override
  State<ArchivedReportPage> createState() => _ArchivedReportPageState();
}

class _ArchivedReportPageState extends State<ArchivedReportPage> {
  Uint8List? _pdf;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.archive.read(widget.item.id);
      if (!mounted) return;
      setState(() {
        _pdf = bytes;
        _missing = bytes == null;
      });
    } catch (e) {
      AppLog.add('архів: не вдалося прочитати звіт: $e');
      if (mounted) setState(() => _missing = true);
    }
  }

  Future<void> _share() async {
    final pdf = _pdf;
    if (pdf == null) return;
    final action = widget.onShare ??
            (Uint8List bytes, String name) => Printing.sharePdf(bytes: bytes, filename: name);
    await action(pdf, widget.item.fileName);
  }

  Future<void> _print() async {
    final pdf = _pdf;
    if (pdf == null) return;
    await Printing.layoutPdf(onLayout: (_) async => pdf, name: widget.item.fileName);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final pdf = _pdf;
    final Widget body;
    if (_missing) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Файл цього звіту не знайдено. Видали запис і сформуй звіт заново.',
            key: Key('archived-missing'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (pdf == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (widget.previewBuilder != null) {
      body = widget.previewBuilder!(context, pdf, item.fileName);
    } else {
      body = PdfPreview(
        build: (_) => pdf,
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: item.fileName,
        maxPageWidth: 700,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${kMonthsNominative[item.month - 1]} ${item.year}'),
        actions: [
          IconButton(
            key: const Key('archived-share'),
            tooltip: 'Поділитись або зберегти',
            onPressed: pdf == null ? null : _share,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            key: const Key('archived-print'),
            tooltip: 'Друк',
            onPressed: pdf == null ? null : _print,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Сформовано ${fmtDateTime(item.createdAt)}'
                    '${item.employee.isEmpty ? '' : ' · ${item.employee}'}',
                key: const Key('archived-info'),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
