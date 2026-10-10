import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AlphaColors {
  static const Color primary = Color(0xFF39FF14);
  static const Color ink = Color(0xFF111311);
  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFF4B740);
  static const Color lightMuted = Color(0xFF687068);
  static const Color lightCanvas = Colors.white;
  static const Color lightSurface = Colors.white;
  static const Color lightSoftSurface = Color(0xFFF0F3F0);
  static const Color lightBorder = Color(0xFFE1E6E1);
  static const Color darkCanvas = Color(0xFF0D100D);
  static const Color darkSurface = Color(0xFF171A17);
  static const Color darkSoftSurface = Color(0xFF222622);
  static const Color darkBorder = Color(0xFF343A34);

  static Color background(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;
  static Color surface(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color text(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color muted(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.color!;
  static Color border(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;
}

abstract final class AlphaSpacing {
  static const double contentMaxWidth = 760;
  static const double page = 16;
  static const double controlHeight = 48;
  static const double actionHeight = 56;
  static const double sheetRadius = 24;
  static const double cardRadius = 20;
  static const double controlRadius = 14;
}

abstract final class AlphaTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final Color canvas =
        dark ? AlphaColors.darkCanvas : AlphaColors.lightCanvas;
    final Color surface =
        dark ? AlphaColors.darkSurface : AlphaColors.lightSurface;
    final Color softSurface = dark
        ? AlphaColors.darkSoftSurface
        : AlphaColors.lightSoftSurface;
    final Color border =
        dark ? AlphaColors.darkBorder : AlphaColors.lightBorder;
    final Color ink = dark ? const Color(0xFFF7FAF7) : AlphaColors.ink;
    final Color muted =
        dark ? const Color(0xFFADB6AD) : AlphaColors.lightMuted;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AlphaColors.primary,
      brightness: brightness,
      primary: AlphaColors.primary,
      onPrimary: AlphaColors.ink,
      surface: surface,
      onSurface: ink,
      error: AlphaColors.danger,
    ).copyWith(
      surfaceContainerLowest: surface,
      surfaceContainerLow: softSurface,
      surfaceContainer: softSurface,
      outline: border,
      outlineVariant: border,
    );
    final TextTheme base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme;
    final RoundedRectangleBorder controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AlphaSpacing.controlRadius),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: surface,
      dividerColor: border,
      fontFamily: 'Roboto',
      splashFactory: InkRipple.splashFactory,
      textTheme: base.copyWith(
        headlineLarge: base.headlineLarge?.copyWith(
          color: ink,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
        headlineMedium: base.headlineMedium?.copyWith(
          color: ink,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: base.titleLarge?.copyWith(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: base.titleMedium?.copyWith(
          color: ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.bodyLarge?.copyWith(color: ink, height: 1.45),
        bodyMedium: base.bodyMedium?.copyWith(color: muted, height: 1.42),
        bodySmall: base.bodySmall?.copyWith(color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AlphaSpacing.cardRadius),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: border,
        dragHandleSize: const Size(48, 5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AlphaSpacing.sheetRadius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AlphaSpacing.cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: softSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AlphaSpacing.controlRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AlphaSpacing.controlRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AlphaSpacing.controlRadius),
          borderSide: const BorderSide(color: AlphaColors.primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(AlphaSpacing.actionHeight),
          backgroundColor: AlphaColors.primary,
          foregroundColor: AlphaColors.ink,
          disabledBackgroundColor: softSurface,
          disabledForegroundColor: muted,
          elevation: 0,
          shape: controlShape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AlphaSpacing.controlHeight),
          foregroundColor: ink,
          side: BorderSide(color: border),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          foregroundColor: ink,
          backgroundColor: surface,
          shape: const CircleBorder(),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: AlphaColors.primary.withValues(alpha: 0.2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AlphaColors.ink
              : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AlphaColors.primary
              : border,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFFF4F7F4) : AlphaColors.ink,
        contentTextStyle: TextStyle(
          color: dark ? AlphaColors.ink : Colors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AlphaColors.primary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension AlphaThemeContext on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get alphaCanvas => Theme.of(this).scaffoldBackgroundColor;
  Color get alphaSurface => Theme.of(this).colorScheme.surface;
  Color get alphaSoftSurface => Theme.of(this).colorScheme.surfaceContainerLow;
  Color get alphaInk => Theme.of(this).colorScheme.onSurface;
  Color get alphaMuted => Theme.of(this).textTheme.bodyMedium!.color!;
  Color get alphaBorder => Theme.of(this).colorScheme.outlineVariant;
}
