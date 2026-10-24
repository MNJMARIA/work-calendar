/*
// «Робочий календар» — точка входу й нижнє меню.
//
// Додаток має дві вкладки:
//  • «Календар» — місяць / тиждень / день, таймер, вибір кількох днів;
//  • «Планування» — чернетка, що не змінює справжній календар.
//
// Усе зберігається на телефоні й працює без інтернету.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'calendar_page.dart';
import 'planning_page.dart';
import 'theme.dart';

// Щоб тести могли імпортувати функції розрахунків прямо з main.dart.
export 'logic.dart';

/// Запуск: спершу відкриваємо сховище телефона, потім показуємо додаток.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(WorkCalendarApp(state: AppState(prefs)));
}

class WorkCalendarApp extends StatelessWidget {
  const WorkCalendarApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Коли в налаштуваннях змінюється тема, весь додаток перемальовується.
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'Робочий календар',
          debugShowCheckedModeBanner: false,
          themeMode: state.themeMode,
          // Преміальна тема: графіт + помаранчевий акцент (див. theme.dart).
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: AppShell(state: state),
        );
      },
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

class _AppShellState extends State<AppShell> {
  int _index = 0;

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
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
*/
// «Робочий календар» — точка входу й нижнє меню.
//
// Додаток має дві вкладки:
//  • «Календар» — місяць / тиждень / день, таймер, вибір кількох днів;
//  • «Планування» — чернетка, що не змінює справжній календар.
//
// Усе зберігається на телефоні й працює без інтернету.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'calendar_page.dart';
import 'planning_page.dart';
import 'theme.dart';

// Щоб тести могли імпортувати функції розрахунків прямо з main.dart.
export 'logic.dart';

/// Запуск: спершу відкриваємо сховище телефона, потім показуємо додаток.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(WorkCalendarApp(state: AppState(prefs)));
}

class WorkCalendarApp extends StatelessWidget {
  const WorkCalendarApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Коли в налаштуваннях змінюється тема, весь додаток перемальовується.
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'Робочий календар',
          debugShowCheckedModeBanner: false,
          themeMode: state.themeMode,
          // Преміальна тема: графіт + помаранчевий акцент (див. theme.dart).
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: AppShell(state: state),
        );
      },
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

class _AppShellState extends State<AppShell> {
  int _index = 0;

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
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
