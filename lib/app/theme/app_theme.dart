import 'package:flutter/material.dart';

import '../task_time.dart';

class AppThemePalette extends ThemeExtension<AppThemePalette> {
  const AppThemePalette({
    required this.canvas,
    required this.surface,
    required this.surfaceTint,
    required this.surfaceHover,
    required this.primaryText,
    required this.secondaryText,
    required this.mutedText,
    required this.border,
    required this.accent,
    required this.accentFill,
    required this.accentTint,
    required this.warning,
    required this.info,
    required this.success,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceTint;
  final Color surfaceHover;
  final Color primaryText;
  final Color secondaryText;
  final Color mutedText;
  final Color border;
  final Color accent;
  final Color accentFill;
  final Color accentTint;
  final Color warning;
  final Color info;
  final Color success;

  @override
  AppThemePalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceTint,
    Color? surfaceHover,
    Color? primaryText,
    Color? secondaryText,
    Color? mutedText,
    Color? border,
    Color? accent,
    Color? accentFill,
    Color? accentTint,
    Color? warning,
    Color? info,
    Color? success,
  }) {
    return AppThemePalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceTint: surfaceTint ?? this.surfaceTint,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      mutedText: mutedText ?? this.mutedText,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      accentFill: accentFill ?? this.accentFill,
      accentTint: accentTint ?? this.accentTint,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      success: success ?? this.success,
    );
  }

  @override
  AppThemePalette lerp(ThemeExtension<AppThemePalette>? other, double t) {
    if (other is! AppThemePalette) {
      return this;
    }
    return AppThemePalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceTint: Color.lerp(surfaceTint, other.surfaceTint, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentFill: Color.lerp(accentFill, other.accentFill, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

extension AppThemePaletteTaskTime on AppThemePalette {
  Color taskTimeColor(TaskTimeState state) {
    return switch (state) {
      TaskTimeState.future => info,
      TaskTimeState.focused => success,
      TaskTimeState.current => warning,
      TaskTimeState.overdue => accent,
      TaskTimeState.completed => mutedText,
    };
  }
}

extension AppThemePaletteContext on BuildContext {
  AppThemePalette get appColors {
    final theme = Theme.of(this);
    return theme.extension<AppThemePalette>() ??
        (theme.brightness == Brightness.dark
            ? AppTheme._dark
            : AppTheme._light);
  }
}

class AppTheme {
  static const _light = AppThemePalette(
    canvas: Color(0xFFFEFDFB),
    surface: Color(0xFFFFFFFF),
    surfaceTint: Color(0xFFF6F5F4),
    surfaceHover: Color(0xFFF2EFEC),
    primaryText: Color(0xFF25221E),
    secondaryText: Color(0xFF6B625C),
    mutedText: Color(0xFF9A918A),
    border: Color(0x1A25221E),
    accent: Color(0xFFE44332),
    accentFill: Color(0xFFD83B2E),
    accentTint: Color(0xFFFDECEA),
    warning: Color(0xFFB76A00),
    info: Color(0xFF3B6EA8),
    success: Color(0xFF2E7D32),
  );

  static const _dark = AppThemePalette(
    canvas: Color(0xFF160D10),
    surface: Color(0xFF201216),
    surfaceTint: Color(0xFF2A171D),
    surfaceHover: Color(0xFF342027),
    primaryText: Color(0xFFF7EDEE),
    secondaryText: Color(0xFFD1C1C5),
    mutedText: Color(0xFF9F8A92),
    border: Color(0x29F7EDEE),
    accent: Color(0xFFFF6B5E),
    accentFill: Color(0xFFD83B2E),
    accentTint: Color(0xFF42191D),
    warning: Color(0xFFE0A449),
    info: Color(0xFF6EA6D8),
    success: Color(0xFF6FCF97),
  );

  static ThemeData light() => _build(_light, Brightness.light);

  static ThemeData dark() => _build(_dark, Brightness.dark);

  static ThemeData _build(AppThemePalette colors, Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      brightness: brightness,
      primary: colors.accentFill,
      onPrimary: Colors.white,
      secondary: colors.secondaryText,
      onSecondary: Colors.white,
      surface: colors.surface,
      onSurface: colors.primaryText,
      surfaceContainerLowest: colors.canvas,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surfaceTint,
      surfaceContainerHigh: colors.surfaceHover,
      surfaceContainerHighest: colors.surfaceTint,
      onSurfaceVariant: colors.secondaryText,
      outline: colors.border,
      outlineVariant: colors.border,
      error: colors.accentFill,
    );
    final textTheme =
        (brightness == Brightness.dark
                ? Typography.whiteMountainView
                : Typography.blackMountainView)
            .apply(
              bodyColor: colors.primaryText,
              displayColor: colors.primaryText,
            );

    final outlinedBorder = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: colors.border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.canvas,
      extensions: const <ThemeExtension<dynamic>>[],
    ).copyWith(
      extensions: <ThemeExtension<dynamic>>[colors],
      textTheme: textTheme.copyWith(
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
        bodySmall: textTheme.bodySmall?.copyWith(color: colors.secondaryText),
        labelMedium: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: colors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceTint,
        selectedColor: colors.accentTint,
        disabledColor: colors.surfaceTint,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        prefixIconColor: colors.mutedText,
        hintStyle: TextStyle(color: colors.mutedText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: outlinedBorder,
        enabledBorder: outlinedBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: colors.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accentFill,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.surfaceHover,
          disabledForegroundColor: colors.mutedText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primaryText,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.secondaryText,
          disabledForegroundColor: colors.mutedText,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        selectedIconTheme: IconThemeData(color: colors.accent),
        unselectedIconTheme: IconThemeData(color: colors.secondaryText),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w500,
        ),
        groupAlignment: -1,
        minWidth: 76,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accentTint,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? colors.accent : colors.secondaryText,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.accent : colors.secondaryText,
          );
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceHover,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceHover,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
        ),
        actionTextColor: colors.accent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
