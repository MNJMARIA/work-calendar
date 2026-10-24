// «Робочий календар»: сам додаток (тема, вхід, нижнє меню).
// Тут немає Firebase, тому тести можуть імпортувати цей файл напряму.
//
// Додаток має дві вкладки:
//  • «Календар» — місяць / тиждень / день, таймер, вибір кількох днів;
//  • «Планування» — чернетка, що не змінює справжній календар.
//
// Усе зберігається на телефоні й працює без інтернету. Якщо підключена хмара
// (див. services.dart), додатково показується вхід і працює синхронізація.

import 'package:flutter/material.dart';

import 'account/account_pages.dart';
import 'app_state.dart';
import 'calendar_page.dart';
import 'planning_page.dart';
import 'services.dart';
import 'theme.dart';
import 'updates/update_pages.dart';

// Щоб тести могли імпортувати функції розрахунків прямо з app.dart.
export 'logic.dart';

class WorkCalendarApp extends StatelessWidget {
  const WorkCalendarApp({
    super.key,
    required this.state,
    this.services,
    this.navigatorKey,
  });

  final AppState state;

  /// Хмарні сервіси; без них додаток працює повністю локально.
  final AppServices? services;

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    final services = this.services ?? AppServices.none;
    final account = services.account;
    // AppServicesScope стоїть над MaterialApp, тому його бачать усі екрани,
    // включно з тими, що відкриваються поверх.
    return AppServicesScope(
      services: services,
      // Коли в налаштуваннях змінюється тема, весь додаток перемальовується.
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return MaterialApp(
            title: 'Робочий календар',
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            themeMode: state.themeMode,
            // Преміальна тема: графіт + помаранчевий акцент (див. theme.dart).
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            home: account == null
                ? AppShell(state: state)
                : AccountGate(controller: account, child: AppShell(state: state)),
          );
        },
      ),
    );
  }
}

/// Оболонка з нижнім меню «Календар / Планування».
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  DateTime _lastCheck = DateTime.now();
  UpdateOpenSignal? _signal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _afterFirstFrame();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final signal = AppServicesScope.of(context).openUpdateSignal;
    if (!identical(signal, _signal)) {
      _signal?.removeListener(_onOpenUpdate);
      _signal = signal..addListener(_onOpenUpdate);
    }
  }

  @override
  void dispose() {
    _signal?.removeListener(_onOpenUpdate);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _afterFirstFrame() {
    final services = AppServicesScope.of(context);
    // Користувач натиснув на сповіщення про оновлення ще до появи екрана.
    if (services.openUpdateSignal.consume()) {
      openUpdatePage(context);
      return;
    }
    // Додаток щойно оновився: пояснюємо це.
    final from = services.takeJustUpdated();
    if (from != null) {
      showJustUpdatedDialog(context, services.currentVersion);
    }
  }

  void _onOpenUpdate() {
    final signal = _signal;
    if (signal != null && signal.consume() && mounted) {
      openUpdatePage(context);
    }
  }

  /// Коли користувач повертається в додаток, перевіряємо оновлення
  /// (не частіше, ніж раз на 10 хвилин).
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    if (now.difference(_lastCheck) < const Duration(minutes: 10)) return;
    _lastCheck = now;
    AppServicesScope.of(context).updates?.check();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack тримає обидві вкладки «живими»:
      // при перемиканні нічого не втрачається.
      body: IndexedStack(
        index: _index,
        children: [
          CalendarPage(state: widget.state),
          PlanningPage(state: widget.state),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Смужка «Доступне оновлення» (з'являється лише коли є нова версія).
          const UpdateBanner(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Календар',
              ),
              NavigationDestination(
                icon: Icon(Icons.edit_calendar_outlined),
                selectedIcon: Icon(Icons.edit_calendar),
                label: 'Планування',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
