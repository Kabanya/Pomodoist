import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import 'app_motion.dart';

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
    canvas: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    surfaceTint: Color(0xFFF5F5F5),
    surfaceHover: Color(0xFFEEEEEE),
    primaryText: Color(0xFF171717),
    secondaryText: Color(0xFF737373),
    mutedText: Color(0xFF737373),
    border: Color(0xFFE5E5E5),
    accent: Color(0xFFD83B2E),
    accentFill: Color(0xFFD83B2E),
    accentTint: Color(0xFFFDECEA),
    warning: Color(0xFFB76A00),
    info: Color(0xFF3B6EA8),
    success: Color(0xFF2E7D32),
  );

  static const _dark = AppThemePalette(
    canvas: Color(0xFF0A0A0A),
    surface: Color(0xFF141414),
    surfaceTint: Color(0xFF1C1C1C),
    surfaceHover: Color(0xFF242424),
    primaryText: Color(0xFFFAFAFA),
    secondaryText: Color(0xFFA3A3A3),
    mutedText: Color(0xFFA3A3A3),
    border: Color(0xFF292929),
    accent: Color(0xFFFF6B5E),
    accentFill: Color(0xFFD83B2E),
    accentTint: Color(0xFF301B19),
    warning: Color(0xFFE0A449),
    info: Color(0xFF6EA6D8),
    success: Color(0xFF6FCF97),
  );

  static ThemeData light() => _build(_light, Brightness.light);

  static ThemeData dark() => _build(_dark, Brightness.dark);

  static const monoTextStyle = TextStyle(
    fontFamily: 'GeistMono',
    package: 'shadcn_ui',
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Material drives the transition; both widget families share its palette.
  static shad.ShadThemeData shadFromMaterial(
    ThemeData theme, {
    bool reduceMotion = false,
  }) {
    final colors = theme.extension<AppThemePalette>()!;
    final popupDuration = reduceMotion ? Duration.zero : AppMotion.popup;
    final panelDuration = reduceMotion ? Duration.zero : AppMotion.panel;
    final enter = <Effect<dynamic>>[
      FadeEffect(
        begin: 0,
        end: 1,
        duration: popupDuration,
        curve: AppMotion.curve,
      ),
      MoveEffect(
        begin: const Offset(0, 4),
        end: Offset.zero,
        duration: popupDuration,
        curve: AppMotion.curve,
      ),
    ];
    final exit = <Effect<dynamic>>[
      FadeEffect(
        begin: 1,
        end: 0,
        duration: popupDuration,
        curve: AppMotion.curve,
      ),
    ];
    final dialog = shad.ShadDialogTheme(
      radius: BorderRadius.circular(12),
      backgroundColor: colors.surface,
      border: Border.all(color: colors.border),
      animateIn: enter,
      animateOut: exit,
      titleStyle: theme.textTheme.titleLarge,
      descriptionStyle: theme.textTheme.bodyMedium,
    );
    return shad.ShadThemeData(
      brightness: theme.brightness,
      radius: BorderRadius.circular(8),
      colorScheme: shad.ShadColorScheme(
        background: colors.canvas,
        foreground: colors.primaryText,
        card: colors.surface,
        cardForeground: colors.primaryText,
        popover: colors.surface,
        popoverForeground: colors.primaryText,
        primary: colors.accentFill,
        primaryForeground: Colors.white,
        secondary: colors.surfaceTint,
        secondaryForeground: colors.primaryText,
        muted: colors.surfaceTint,
        mutedForeground: colors.secondaryText,
        accent: colors.surfaceHover,
        accentForeground: colors.primaryText,
        destructive: colors.accentFill,
        destructiveForeground: Colors.white,
        border: colors.border,
        input: colors.border,
        ring: colors.accent,
        selection: colors.accentTint,
      ),
      textTheme: shad.ShadTextTheme(
        family: 'Geist',
        package: 'shadcn_ui',
        h1Large: theme.textTheme.displayLarge,
        h1: theme.textTheme.headlineLarge,
        h2: theme.textTheme.headlineMedium,
        h3: theme.textTheme.headlineSmall,
        h4: theme.textTheme.titleLarge,
        p: theme.textTheme.bodyLarge,
        large: theme.textTheme.titleMedium,
        small: theme.textTheme.labelLarge,
        muted: theme.textTheme.bodySmall,
      ),
      primaryButtonTheme: shad.ShadButtonTheme(
        shadows: const [],
        textStyle: theme.textTheme.labelLarge,
        hoverBackgroundColor: Color.lerp(
          colors.accentFill,
          colors.primaryText,
          .08,
        ),
        pressedBackgroundColor: Color.lerp(
          colors.accentFill,
          colors.primaryText,
          .16,
        ),
      ),
      outlineButtonTheme: shad.ShadButtonTheme(
        shadows: const [],
        textStyle: theme.textTheme.labelLarge,
      ),
      secondaryButtonTheme: shad.ShadButtonTheme(
        shadows: const [],
        textStyle: theme.textTheme.labelLarge,
      ),
      ghostButtonTheme: shad.ShadButtonTheme(
        textStyle: theme.textTheme.labelLarge,
      ),
      cardTheme: shad.ShadCardTheme(
        radius: BorderRadius.circular(10),
        shadows: const [],
      ),
      inputTheme: shad.ShadInputTheme(
        style: theme.textTheme.bodyLarge,
        placeholderStyle: theme.textTheme.bodyLarge?.copyWith(
          color: colors.mutedText,
        ),
        decoration: shad.ShadDecoration(color: colors.surface),
      ),
      primaryDialogTheme: dialog,
      alertDialogTheme: dialog,
      popoverTheme: shad.ShadPopoverTheme(
        effects: enter,
        reverseDuration: popupDuration,
      ),
      contextMenuTheme: shad.ShadContextMenuTheme(
        effects: enter,
        popoverReverseDuration: popupDuration,
      ),
      tooltipTheme: shad.ShadTooltipTheme(
        effects: enter,
        reverseDuration: popupDuration,
      ),
      sheetTheme: shad.ShadSheetTheme(
        radius: BorderRadius.circular(12),
        snapAnimationDuration: panelDuration,
        snapAnimationCurve: AppMotion.curve,
        animateIn: [
          FadeEffect(begin: 0, end: 1, duration: panelDuration),
          MoveEffect(
            begin: const Offset(0, 4),
            end: Offset.zero,
            duration: panelDuration,
            curve: AppMotion.curve,
          ),
        ],
        animateOut: [FadeEffect(begin: 1, end: 0, duration: panelDuration)],
      ),
    );
  }

  static ThemeData _build(AppThemePalette colors, Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      brightness: brightness,
      primary: colors.accentFill,
      onPrimary: Colors.white,
      primaryContainer: colors.accentTint,
      onPrimaryContainer: colors.accent,
      secondary: colors.secondaryText,
      onSecondary: Colors.white,
      secondaryContainer: colors.surfaceTint,
      onSecondaryContainer: colors.primaryText,
      tertiary: colors.secondaryText,
      tertiaryContainer: colors.surfaceTint,
      onTertiaryContainer: colors.primaryText,
      inverseSurface: colors.primaryText,
      onInverseSurface: colors.canvas,
      inversePrimary: colors.accent,
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
    final textTheme = Typography.material2021().englishLike
        .merge(ThemeData(useMaterial3: true, brightness: brightness).textTheme)
        .apply(
          fontFamily: 'Geist',
          package: 'shadcn_ui',
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
      fontFamily: 'Geist',
      package: 'shadcn_ui',
      splashFactory: NoSplash.splashFactory,
      hoverColor: colors.surfaceHover,
      focusColor: colors.accentTint,
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
        bodyMedium: textTheme.bodyMedium?.copyWith(color: colors.primaryText),
        bodySmall: textTheme.bodySmall?.copyWith(color: colors.secondaryText),
        labelMedium: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.primaryText,
      ),
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
          animationDuration: AppMotion.hover,
          elevation: 0,
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
          animationDuration: AppMotion.hover,
          foregroundColor: colors.primaryText,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          animationDuration: AppMotion.hover,
          foregroundColor: colors.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          animationDuration: AppMotion.hover,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        elevation: 4,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        backgroundColor: colors.surfaceHover,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
        ),
        actionTextColor: colors.accent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: colors.primaryText),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
