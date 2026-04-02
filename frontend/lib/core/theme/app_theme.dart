import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const Color _seed = Color(0xFF4F8D95);

  // Dark chrome
  static const Color _chromeDark = Color(0xFF0B1016);
  static const Color _chromeOnDark = Color(0xFFF4EFE8);

  // Light chrome
  static const Color _chromeLight = Color(0xFFEDE8E1);
  static const Color _chromeOnLight = Color(0xFF1A1410);

  static ThemeData theme() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF121821),
    );

    final colorScheme = baseScheme.copyWith(
      primary: const Color(0xFFE8C7AA),
      onPrimary: const Color(0xFF33241B),
      primaryContainer: const Color(0xFF5D473A),
      onPrimaryContainer: const Color(0xFFFFEBDD),
      secondary: const Color(0xFF74C2CB),
      onSecondary: const Color(0xFF0D2B2F),
      secondaryContainer: const Color(0xFF1D4A51),
      onSecondaryContainer: const Color(0xFFE2F7F8),
      tertiary: const Color(0xFFADC58C),
      onTertiary: const Color(0xFF1E280E),
      tertiaryContainer: const Color(0xFF3E4A2B),
      onTertiaryContainer: const Color(0xFFF2F7D8),
      surface: const Color(0xFF121821),
      onSurface: const Color(0xFFF5F1EC),
      onSurfaceVariant: const Color(0xFFA4B0BE),
      surfaceContainerLowest: const Color(0xFF0F141C),
      surfaceContainerLow: const Color(0xFF161D27),
      surfaceContainer: const Color(0xFF1B2430),
      surfaceContainerHigh: const Color(0xFF222D3A),
      surfaceContainerHighest: const Color(0xFF2A3745),
      surfaceBright: const Color(0xFF374555),
      outline: const Color(0xFF76695E),
      outlineVariant: const Color(0xFF354252),
    );

    return _buildTheme(
      colorScheme,
      chrome: _chromeDark,
      chromeOn: _chromeOnDark,
    );
  }

  static ThemeData lightTheme() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );

    final colorScheme = baseScheme.copyWith(
      primary: const Color(0xFF7A4F35),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFFFDCC8),
      onPrimaryContainer: const Color(0xFF33180A),
      secondary: const Color(0xFF1A6B75),
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFB8EDF4),
      onSecondaryContainer: const Color(0xFF002025),
      tertiary: const Color(0xFF3D5E26),
      onTertiary: const Color(0xFFFFFFFF),
      tertiaryContainer: const Color(0xFFD4F0B2),
      onTertiaryContainer: const Color(0xFF0E1F00),
      surface: const Color(0xFFF5F0EA),
      onSurface: const Color(0xFF1A1410),
      onSurfaceVariant: const Color(0xFF5C6670),
      surfaceContainerLowest: const Color(0xFFFAF6F0),
      surfaceContainerLow: const Color(0xFFF0EBE4),
      surfaceContainer: const Color(0xFFE8E3DC),
      surfaceContainerHigh: const Color(0xFFE0DAD3),
      surfaceContainerHighest: const Color(0xFFD8D2CB),
      surfaceBright: const Color(0xFFFFFBF7),
      outline: const Color(0xFF8B7E73),
      outlineVariant: const Color(0xFFCDBFB4),
    );

    return _buildTheme(
      colorScheme,
      chrome: _chromeLight,
      chromeOn: _chromeOnLight,
    );
  }

  static ThemeData _buildTheme(
    ColorScheme colorScheme, {
    required Color chrome,
    required Color chromeOn,
  }) {
    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      textTheme: base.textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: chrome,
        surfaceTintColor: Colors.transparent,
        foregroundColor: chromeOn,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: colorScheme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: colorScheme.brightness == Brightness.dark
              ? Brightness.dark
              : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              colorScheme.brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
        ),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: chromeOn,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: chromeOn),
        actionsIconTheme: IconThemeData(color: chromeOn),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.20),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: chrome.withValues(alpha: 0.97),
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: isSelected ? 24 : 22,
            color: isSelected
                ? colorScheme.secondary
                : chromeOn.withValues(alpha: 0.55),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return base.textTheme.labelSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? colorScheme.secondary
                : chromeOn.withValues(alpha: 0.55),
            letterSpacing: isSelected ? 0.2 : 0,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle:
              base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.9),
            width: 1.05,
          ),
          foregroundColor: colorScheme.secondary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow.withValues(alpha: 0.98),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: base.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        labelStyle: base.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.64),
            width: 1.0,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.64),
            width: 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.secondary, width: 1.8),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.42),
        selectedColor: colorScheme.secondary.withValues(alpha: 0.24),
        disabledColor: colorScheme.surfaceContainerHigh,
        secondaryLabelStyle: TextStyle(color: colorScheme.onSecondary),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: colorScheme.secondary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        labelColor: colorScheme.secondary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 4,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.56),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}
