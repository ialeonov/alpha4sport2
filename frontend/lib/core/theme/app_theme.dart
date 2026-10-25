import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const Color _seed = Color(0xFFE8B84A);

  // Направление «Тёмный атлет»: графит, золото — действия и награды,
  // бирюза — AI-коуч и подсказки.
  static const Color gold = Color(0xFFE8B84A);
  static const Color onGold = Color(0xFF14110A);
  static const Color coachTeal = Color(0xFF5CC2B5);

  // Dark chrome
  static const Color _chromeDark = Color(0xFF141A1F);
  static const Color _chromeOnDark = Color(0xFFF2F0EA);

  // Light chrome
  static const Color _chromeLight = Color(0xFFEDE8E1);
  static const Color _chromeOnLight = Color(0xFF1A1410);

  static ThemeData theme() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF0F1215),
    );

    final colorScheme = baseScheme.copyWith(
      primary: gold,
      onPrimary: onGold,
      primaryContainer: const Color(0xFF3A2F17),
      onPrimaryContainer: const Color(0xFFFBE7B8),
      secondary: coachTeal,
      onSecondary: const Color(0xFF0B2421),
      secondaryContainer: const Color(0xFF1E3533),
      onSecondaryContainer: const Color(0xFFD5EFEB),
      tertiary: const Color(0xFFADC58C),
      onTertiary: const Color(0xFF1E280E),
      tertiaryContainer: const Color(0xFF3E4A2B),
      onTertiaryContainer: const Color(0xFFF2F7D8),
      surface: const Color(0xFF0F1215),
      onSurface: const Color(0xFFF2F0EA),
      onSurfaceVariant: const Color(0xFF9AA3AD),
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: const Color(0xFF0B0E10),
      surfaceContainerLow: const Color(0xFF181D22),
      surfaceContainer: const Color(0xFF1B2026),
      surfaceContainerHigh: const Color(0xFF20262D),
      surfaceContainerHighest: const Color(0xFF262D35),
      surfaceBright: const Color(0xFF2C343D),
      outline: const Color(0xFF6B747E),
      outlineVariant: const Color(0xFF2C343D),
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
      // Тёмное золото: на светлом фоне яркое не проходит по контрасту.
      primary: const Color(0xFF7A5A12),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFFBE7B8),
      onPrimaryContainer: const Color(0xFF2A1F05),
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
          borderRadius: BorderRadius.circular(22),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        // С пятью вкладками одних иконок мало — подпись у активной вкладки.
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        backgroundColor: chrome.withValues(alpha: 0.97),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: isSelected ? 26 : 22,
            color: isSelected
                ? colorScheme.primary
                : chromeOn.withValues(alpha: 0.5),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return base.textTheme.labelSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? colorScheme.primary
                : chromeOn.withValues(alpha: 0.6),
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          foregroundColor: colorScheme.onSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
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
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: colorScheme.onPrimary,
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
