// Тема «Робочого календаря»: преміальний мінімалізм.
//
// Ідея дизайну: глибокий графітовий фон, великі закруглені картки з тонкою
// рамкою, один акцентний колір (теплий помаранчевий) і багато «повітря».
// Світла тема — світло-сірий фон і білі картки з тим самим акцентом.

import 'package:flutter/material.dart';

const ColorScheme _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFF6B2C),
  onPrimary: Color(0xFF1A0A02),
  primaryContainer: Color(0xFF8F3A12),
  onPrimaryContainer: Color(0xFFFFE3D4),
  secondary: Color(0xFF9A9AA3),
  onSecondary: Color(0xFF0D0D0F),
  secondaryContainer: Color(0xFF2E2E36),
  onSecondaryContainer: Color(0xFFE8E8EC),
  tertiary: Color(0xFF5AB2FF),
  onTertiary: Color(0xFF00213A),
  tertiaryContainer: Color(0xFF1E3A56),
  onTertiaryContainer: Color(0xFFD6EBFF),
  error: Color(0xFFFF7A7A),
  onError: Color(0xFF2A0000),
  surface: Color(0xFF0D0D0F),
  onSurface: Color(0xFFF2F2F4),
  surfaceContainerLowest: Color(0xFF0A0A0B),
  surfaceContainerLow: Color(0xFF151518),
  surfaceContainer: Color(0xFF1A1A1E),
  surfaceContainerHigh: Color(0xFF222227),
  surfaceContainerHighest: Color(0xFF2A2A30),
  onSurfaceVariant: Color(0xFF9A9AA3),
  outline: Color(0xFF3A3A42),
  outlineVariant: Color(0xFF2A2A30),
);

const ColorScheme _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFE8541A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFD9C7),
  onPrimaryContainer: Color(0xFF3A1200),
  secondary: Color(0xFF6B6B75),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE4E4EA),
  onSecondaryContainer: Color(0xFF1B1B1F),
  tertiary: Color(0xFF1976D2),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFD3E6FA),
  onTertiaryContainer: Color(0xFF0B2A47),
  error: Color(0xFFC62828),
  onError: Color(0xFFFFFFFF),
  surface: Color(0xFFF3F3F5),
  onSurface: Color(0xFF111114),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceContainerHigh: Color(0xFFFFFFFF),
  surfaceContainerHighest: Color(0xFFE8E8EC),
  onSurfaceVariant: Color(0xFF6B6B75),
  outline: Color(0xFFC9C9D1),
  outlineVariant: Color(0xFFE3E3E8),
);

/// Збирає тему для світлого або темного режиму.
ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? _darkScheme : _lightScheme;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 68,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      extendedTextStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
      actionTextColor: scheme.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: scheme.surfaceContainer,
        foregroundColor: scheme.onSurfaceVariant,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
