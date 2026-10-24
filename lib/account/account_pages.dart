// Екрани входу, реєстрації, підтвердження пошти й ключа відновлення.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crypto/crypto_service.dart';
import 'account_controller.dart';

/// Показує потрібний екран залежно від етапу; коли все готово — [child].
class AccountGate extends StatelessWidget {
  const AccountGate({super.key, required this.controller, required this.child});

  final AccountController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.stage) {
          case AccountStage.loading:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AccountStage.welcome:
            return WelcomePage(controller: controller);
          case AccountStage.needVerify:
            return VerifyEmailPage(controller: controller);
          case AccountStage.keyCheckFailed:
            return KeyCheckFailedPage(controller: controller);
          case AccountStage.needRecoveryKey:
            return EnterKeyPage(controller: controller);
          case AccountStage.newKey:
            return NewKeyPage(controller: controller);
          case AccountStage.ready:
          case AccountStage.localOnly:
            return child;
        }
      },
    );
  }
}

/// Каркас екрана: прокручування, відступи, вузька колонка.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text!,
        key: const Key('auth-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Привітання, вхід, реєстрація
// ─────────────────────────────────────────────────────────────

enum _WelcomeMode { start, signIn, register }

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.controller});

  final AccountController controller;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  _WelcomeMode _mode = _WelcomeMode.start;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  String? _localError;

  AccountController get c => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  void _go(_WelcomeMode mode) {
    c.clearError();
    setState(() {
      _mode = mode;
      _localError = null;
    });
  }

  bool get _emailOk {
    final v = _email.text.trim();
    return v.contains('@') && v.contains('.') && v.length >= 5;
  }

  void _submit() {
    if (!_emailOk) {
      setState(() => _localError = 'Введи правильну пошту.');
      return;
    }
    if (_mode == _WelcomeMode.register) {
      if (_name.text.trim().isEmpty) {
        setState(() => _localError = 'Введи ім\'я.');
        return;
      }
      if (_password.text.length < 8) {
        setState(() => _localError = 'Пароль має містити щонайменше 8 символів.');
        return;
      }
      if (_password.text != _password2.text) {
        setState(() => _localError = 'Паролі не збігаються.');
        return;
      }
      setState(() => _localError = null);
      c.register(_name.text.trim(), _email.text.trim(), _password.text);
    } else {
      if (_password.text.isEmpty) {
        setState(() => _localError = 'Введи пароль.');
        return;
      }
      setState(() => _localError = null);
      c.signIn(_email.text.trim(), _password.text);
    }
  }

  Future<void> _forgot() async {
    if (!_emailOk) {
      setState(() => _localError = 'Спершу введи пошту, на яку надіслати лист.');
      return;
    }
    setState(() => _localError = null);
    await c.sendPasswordReset(_email.text.trim());
    if (!mounted) return;
    if (c.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лист для відновлення пароля надіслано.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return _AuthScaffold(
          children: [
            Icon(Icons.calendar_month, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Робочий календар',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Облік робочих днів і годин. Дані зашифровані: їх бачиш лише ти.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            if (_mode == _WelcomeMode.start) ..._startButtons() else ..._form(),
          ],
        );
      },
    );
  }

  List<Widget> _startButtons() {
    return [
      FilledButton(
        key: const Key('welcome-signin'),
        onPressed: () => _go(_WelcomeMode.signIn),
        child: const Text('Увійти'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        key: const Key('welcome-register'),
        onPressed: () => _go(_WelcomeMode.register),
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
        child: const Text('Створити акаунт'),
      ),
      const SizedBox(height: 20),
      TextButton(
        key: const Key('welcome-local'),
        onPressed: c.continueWithoutAccount,
        child: const Text('Продовжити без акаунта'),
      ),
      Text(
        'Без акаунта дані лишаються лише на цьому телефоні, без копії в хмарі.',
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ];
  }

  List<Widget> _form() {
    final register = _mode == _WelcomeMode.register;
    return [
      Text(
        register ? 'Створення акаунта' : 'Вхід',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      if (register) ...[
        TextField(
          key: const Key('field-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Ім\'я', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        key: const Key('field-email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Пошта', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('field-password'),
        controller: _password,
        obscureText: true,
        decoration: InputDecoration(
          labelText: register ? 'Пароль (мінімум 8 символів)' : 'Пароль',
          border: const OutlineInputBorder(),
        ),
      ),
      if (register) ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('field-password2'),
          controller: _password2,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Повтори пароль',
            border: OutlineInputBorder(),
          ),
        ),
      ],
      _ErrorText(_localError ?? c.error),
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('auth-submit'),
        onPressed: c.busy ? null : _submit,
        child: c.busy
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 3),
        )
            : Text(register ? 'Створити акаунт' : 'Увійти'),
      ),
      if (!register)
        TextButton(
          key: const Key('auth-forgot'),
          onPressed: c.busy ? null : _forgot,
          child: const Text('Забув пароль?'),
        ),
      TextButton(
        onPressed: c.busy ? null : () => _go(_WelcomeMode.start),
        child: const Text('Назад'),
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────
// Підтвердження пошти
// ─────────────────────────────────────────────────────────────

class VerifyEmailPage extends StatelessWidget {
  const VerifyEmailPage({super.key, required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _AuthScaffold(
      children: [
        Icon(Icons.mark_email_unread_outlined, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Підтвердь пошту',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'Ми надіслали лист на ${controller.user?.email ?? 'твою пошту'}. '
              'Відкрий його й натисни посилання, потім повернись сюди. '
              'Якщо листа немає, перевір «Спам».',
          textAlign: TextAlign.center,
        ),
        _ErrorText(controller.error),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('verify-done'),
          onPressed: controller.busy ? null : controller.checkVerified,
          child: const Text('Я підтвердив(ла) пошту'),
        ),
        TextButton(
          onPressed: controller.busy ? null : controller.resendVerification,
          child: const Text('Надіслати лист ще раз'),
        ),
        TextButton(
          onPressed: controller.busy ? null : () => controller.signOut(),
          child: const Text('Вийти'),
        ),
      ],
    );
  }
}

class KeyCheckFailedPage extends StatelessWidget {
  const KeyCheckFailedPage({super.key, required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      children: [
        Icon(Icons.cloud_off, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Потрібен інтернет',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text(
          'Для першого входу на цьому телефоні потрібен зв\'язок із сервером. '
              'Після цього додаток працює й без інтернету.',
          textAlign: TextAlign.center,
        ),
        _ErrorText(controller.error),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('keycheck-retry'),
          onPressed: controller.busy ? null : controller.retryKeyCheck,
          child: const Text('Спробувати ще раз'),
        ),
        TextButton(
          onPressed: controller.busy ? null : () => controller.signOut(),
          child: const Text('Вийти'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Новий ключ відновлення (показати, зберегти, підтвердити)
// ─────────────────────────────────────────────────────────────

class NewKeyPage extends StatefulWidget {
  const NewKeyPage({super.key, required this.controller, Random? random})
      : _random = random;

  final AccountController controller;
  final Random? _random;

  @override
  State<NewKeyPage> createState() => _NewKeyPageState();
}

class _NewKeyPageState extends State<NewKeyPage> {
  bool _saved = false;
  bool _confirming = false;
  late final List<int> _askIndexes;
  final List<TextEditingController> _answers = [];
  String? _localError;

  AccountController get c => widget.controller;

  // Групи рахуємо один раз: далі ключ у контролері стирається.
  late final List<String> _groups = recoveryKeyGroups(c.pendingRecoveryText ?? '');

  @override
  void initState() {
    super.initState();
    final rnd = widget._random ?? Random.secure();
    final all = List<int>.generate(_groups.length, (i) => i)..shuffle(rnd);
    _askIndexes = (all.take(3).toList())..sort();
    for (var i = 0; i < 3; i++) {
      _answers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final a in _answers) {
      a.dispose();
    }
    super.dispose();
  }

  void _verifyAndFinish() {
    for (var i = 0; i < 3; i++) {
      final typed = _answers[i].text.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
      if (typed != _groups[_askIndexes[i]]) {
        setState(() => _localError = 'Групи не збігаються. Перевір збережений ключ.');
        return;
      }
    }
    setState(() => _localError = null);
    c.confirmKeySaved();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final groups = _groups;
        return _AuthScaffold(
          children: [
            Icon(Icons.key, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              c.regenerating ? 'Новий ключ відновлення' : 'Ключ відновлення',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Це єдиний спосіб повернути дані на новому телефоні. '
                  'Без нього ніхто, навіть розробниця, не зможе їх прочитати. '
                  'Збережи ключ у надійному місці: у нотатках, у менеджері паролів або запиши на папері.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.primary),
              ),
              child: SelectableText(
                groups.join('  '),
                key: const Key('recovery-key-text'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.7,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('recovery-copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: c.pendingRecoveryText ?? ''));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ключ скопійовано. Встав його в безпечне місце.')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Скопіювати ключ'),
            ),
            const SizedBox(height: 12),
            if (!_confirming) ...[
              CheckboxListTile(
                key: const Key('recovery-saved'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _saved,
                onChanged: (v) => setState(() => _saved = v ?? false),
                title: const Text('Я зберіг(ла) ключ у надійному місці'),
              ),
              FilledButton(
                key: const Key('recovery-next'),
                onPressed: _saved ? () => setState(() => _confirming = true) : null,
                child: const Text('Далі'),
              ),
            ] else ...[
              Text(
                'Перевіримо, що ключ збережено. Введи ці групи зі збереженого ключа:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < 3; i++) ...[
                TextField(
                  key: Key('confirm-$i'),
                  controller: _answers[i],
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Група номер ${_askIndexes[i] + 1}',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _ErrorText(_localError ?? c.error),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('recovery-finish'),
                onPressed: c.busy ? null : _verifyAndFinish,
                child: c.busy
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
                    : const Text('Завершити'),
              ),
              TextButton(
                onPressed: c.busy ? null : () => setState(() => _confirming = false),
                child: const Text('Назад до ключа'),
              ),
            ],
            if (c.regenerating)
              TextButton(
                onPressed: c.busy ? null : c.cancelRegenerate,
                child: const Text('Скасувати'),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Введення ключа відновлення (новий телефон)
// ─────────────────────────────────────────────────────────────

class EnterKeyPage extends StatefulWidget {
  const EnterKeyPage({super.key, required this.controller});

  final AccountController controller;

  @override
  State<EnterKeyPage> createState() => _EnterKeyPageState();
}

class _EnterKeyPageState extends State<EnterKeyPage> {
  final _key = TextEditingController();

  AccountController get c => widget.controller;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _startOver() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Почати знову?'),
        content: const Text(
          'Усі дані цього акаунта в хмарі буде видалено без можливості відновлення. '
              'Акаунт лишиться, і ти почнеш з чистого аркуша. Робити так варто, '
              'лише якщо ключ відновлення загублено.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            key: const Key('startover-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Видалити й почати знову'),
          ),
        ],
      ),
    );
    if (sure == true) await c.startOver();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final theme = Theme.of(context);
        return _AuthScaffold(
          children: [
            Icon(Icons.key, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Введи ключ відновлення',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Це новий телефон або перевстановлення. Введи ключ, який ти зберіг(ла) '
                  'під час реєстрації, і дані повернуться з хмари.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('field-recovery'),
              controller: _key,
              minLines: 3,
              maxLines: 5,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Ключ відновлення',
                border: OutlineInputBorder(),
              ),
            ),
            _ErrorText(c.error),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('recovery-submit'),
              onPressed: c.busy ? null : () => c.enterRecoveryKey(_key.text),
              child: const Text('Продовжити'),
            ),
            TextButton(
              key: const Key('recovery-startover'),
              onPressed: c.busy ? null : _startOver,
              child: const Text('Загубив(ла) ключ? Почати знову'),
            ),
            TextButton(
              onPressed: c.busy ? null : () => c.signOut(),
              child: const Text('Вийти'),
            ),
          ],
        );
      },
    );
  }
}
