// Екрани звітів: «Повідомити про проблему» (для всіх) і
// «Звіти користувачів» (лише для розробниці).

import 'package:flutter/material.dart';

import '../services.dart';
import 'report_service.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _text = TextEditingController();
  String _category = 'bug';
  bool _attachLog = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(AppServices services) async {
    final text = _text.text.trim();
    if (text.length < 5) {
      setState(() => _error = 'Опиши проблему хоча б кількома словами.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await services.reports.send(
        ReportDraft(category: _category, text: text, attachLog: _attachLog),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Дякуємо! Звіт надіслано.'),
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Не вдалося надіслати звіт. Перевір інтернет і спробуй ще раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.of(context);
    final signedIn = services.account?.user != null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Повідомити про проблему')),
      body: !signedIn
          ? const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Щоб надіслати звіт, увійди в акаунт (Налаштування → Акаунт). '
              'Автоматичні звіти про збої надсилаються й без акаунта, '
              'якщо вони не вимкнені в налаштуваннях.',
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Що сталося?'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'bug', label: Text('Помилка')),
              ButtonSegment(value: 'idea', label: Text('Ідея')),
              ButtonSegment(value: 'other', label: Text('Інше')),
            ],
            selected: {_category},
            onSelectionChanged: (s) => setState(() => _category = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('report-text'),
            controller: _text,
            minLines: 5,
            maxLines: 10,
            maxLength: kReportMaxText,
            decoration: const InputDecoration(
              labelText: 'Опиши, що пішло не так',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _attachLog,
            onChanged: (v) => setState(() => _attachLog = v ?? true),
            title: const Text('Додати технічний журнал'),
            subtitle: const Text(
              'Версія додатка, модель телефона, останні події. '
                  'Години й дати виходів у звіт не потрапляють.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('report-send'),
            onPressed: _sending ? null : () => _send(services),
            child: _sending
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
                : const Text('Надіслати'),
          ),
        ],
      ),
    );
  }
}

String _categoryLabel(String c) {
  switch (c) {
    case 'bug':
      return 'Помилка';
    case 'idea':
      return 'Ідея';
    default:
      return 'Інше';
  }
}

IconData _categoryIcon(String c) {
  switch (c) {
    case 'bug':
      return Icons.bug_report_outlined;
    case 'idea':
      return Icons.lightbulb_outline;
    default:
      return Icons.chat_bubble_outline;
  }
}

String _fmtDate(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Список звітів від користувачів. Правила Firestore пускають сюди лише
/// акаунт розробниці; для всіх інших буде повідомлення про відсутність доступу.
class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = AppServicesScope.of(context).reports;
    return Scaffold(
      appBar: AppBar(title: const Text('Звіти користувачів')),
      body: StreamBuilder<List<ReportEntry>>(
        stream: reports.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Немає доступу до звітів або немає зв\'язку.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const Center(child: Text('Звітів поки немає.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = list[i];
              return ListTile(
                leading: Icon(_categoryIcon(r.category)),
                title: Text(
                  r.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${_categoryLabel(r.category)} · ${r.email} · ${_fmtDate(r.createdAt)}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminReportDetailPage(entry: r, reports: reports),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminReportDetailPage extends StatelessWidget {
  const AdminReportDetailPage({super.key, required this.entry, required this.reports});

  final ReportEntry entry;
  final ReportService reports;

  Future<void> _delete(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Видалити звіт?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await reports.delete(entry.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_categoryLabel(entry.category)),
        actions: [
          IconButton(
            tooltip: 'Видалити',
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(entry.text, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 20),
          SelectableText(
            'Від: ${entry.email}\n'
                'Коли: ${_fmtDate(entry.createdAt)}\n'
                'Версія: ${entry.appVersion}\n'
                'Телефон: ${entry.device}',
            style: theme.textTheme.bodyMedium,
          ),
          if (entry.log.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Журнал', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SelectableText(
              entry.log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
