import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_entry_kind.dart';

/// Immutable app-wide settings shared by secondary and dialog views.
///
/// Contains only fields that are safe to replicate across separate `View`
/// trees: theme, locale, shortcuts, scroll behavior, and similar. Navigation
/// (`home`, `routes`, `routerConfig`, `navigatorKey`) is intentionally omitted
/// because each OS window has its own widget subtree.
///
/// Obtain a snapshot from the main entry widget:
///
/// ```dart
/// final snapshot = AppShellSnapshot.fromMaterialApp(myMaterialApp);
/// MultiViewDesktop.appShell.apply(snapshot);
/// ```
///
/// While the main window is open, the library also keeps the live registry in
/// sync by reading the entry widget from the main view each frame. Programmatic
/// updates via `AppShellController` work even after the main window is closed.
@immutable
class AppShellSnapshot {
  /// Creates a snapshot. Prefer `fromMaterialApp` and related factories when
  /// copying from an existing entry widget.
  const AppShellSnapshot({
    required this.kind,
    this.theme,
    this.darkTheme,
    this.highContrastTheme,
    this.highContrastDarkTheme,
    this.themeMode = ThemeMode.system,
    this.themeAnimationDuration = kThemeAnimationDuration,
    this.themeAnimationCurve = Curves.linear,
    this.themeAnimationStyle,
    this.cupertinoTheme,
    this.color,
    this.locale,
    this.localizationsDelegates,
    this.localeListResolutionCallback,
    this.localeResolutionCallback,
    this.supportedLocales = const <Locale>[Locale('en', 'US')],
    this.debugShowCheckedModeBanner = true,
    this.scrollBehavior,
    this.shortcuts,
    this.actions,
    this.textStyle,
  });

  /// Root widget type used for secondary and dialog shells.
  final AppEntryKind kind;

  /// Light `ThemeData` for `AppEntryKind.material`.
  final ThemeData? theme;

  /// Dark `ThemeData` for `AppEntryKind.material`.
  final ThemeData? darkTheme;

  /// High-contrast light theme for `AppEntryKind.material`.
  final ThemeData? highContrastTheme;

  /// High-contrast dark theme for `AppEntryKind.material`.
  final ThemeData? highContrastDarkTheme;

  /// Active theme mode for `AppEntryKind.material`.
  final ThemeMode themeMode;

  /// Duration of theme change animations on `AppEntryKind.material`.
  final Duration themeAnimationDuration;

  /// Curve of theme change animations on `AppEntryKind.material`.
  final Curve themeAnimationCurve;

  /// Optional animation style for theme transitions on `AppEntryKind.material`.
  final AnimationStyle? themeAnimationStyle;

  /// Theme for `AppEntryKind.cupertino`.
  final CupertinoThemeData? cupertinoTheme;

  /// Primary color used by `AppEntryKind.widgets` and as a fallback elsewhere.
  final Color? color;

  /// Active locale.
  final Locale? locale;

  /// Localization delegates.
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;

  /// Called to resolve the locale from the platform locale list.
  final LocaleListResolutionCallback? localeListResolutionCallback;

  /// Called to resolve the locale from a single platform locale.
  final LocaleResolutionCallback? localeResolutionCallback;

  /// Locales supported by the app.
  final Iterable<Locale> supportedLocales;

  /// Whether to show the debug mode banner.
  final bool debugShowCheckedModeBanner;

  /// Scroll behavior applied by the entry shell.
  final ScrollBehavior? scrollBehavior;

  /// Global shortcut bindings.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Global action bindings.
  final Map<Type, Action<Intent>>? actions;

  /// Base text style for `AppEntryKind.widgets`.
  final TextStyle? textStyle;

  /// Copies app-wide fields from `app`, excluding navigation.
  factory AppShellSnapshot.fromMaterialApp(MaterialApp app) {
    return AppShellSnapshot(
      kind: AppEntryKind.material,
      theme: app.theme,
      darkTheme: app.darkTheme,
      highContrastTheme: app.highContrastTheme,
      highContrastDarkTheme: app.highContrastDarkTheme,
      themeMode: app.themeMode ?? ThemeMode.system,
      themeAnimationDuration: app.themeAnimationDuration,
      themeAnimationCurve: app.themeAnimationCurve,
      themeAnimationStyle: app.themeAnimationStyle,
      color: app.color,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
      scrollBehavior: app.scrollBehavior,
      shortcuts: app.shortcuts,
      actions: app.actions,
    );
  }

  /// Copies app-wide fields from `app`, excluding navigation.
  factory AppShellSnapshot.fromCupertinoApp(CupertinoApp app) {
    return AppShellSnapshot(
      kind: AppEntryKind.cupertino,
      cupertinoTheme: app.theme,
      color: app.color,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
      scrollBehavior: app.scrollBehavior,
      shortcuts: app.shortcuts,
      actions: app.actions,
    );
  }

  /// Copies app-wide fields from `app`, excluding navigation.
  factory AppShellSnapshot.fromWidgetsApp(WidgetsApp app) {
    return AppShellSnapshot(
      kind: AppEntryKind.widgets,
      color: app.color,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
      shortcuts: app.shortcuts,
      actions: app.actions,
      textStyle: app.textStyle,
    );
  }

  /// Resolves native window chrome brightness for this shell.
  ///
  /// `ThemeMode.system` follows `platformBrightness` when provided, otherwise
  /// `PlatformDispatcher.platformBrightness`.
  Brightness resolveWindowBrightness([Brightness? platformBrightness]) {
    final platform =
        platformBrightness ?? WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return switch (kind) {
      AppEntryKind.material => switch (themeMode) {
        ThemeMode.dark => Brightness.dark,
        ThemeMode.light => Brightness.light,
        ThemeMode.system => platform,
      },
      AppEntryKind.cupertino => cupertinoTheme?.brightness ?? platform,
      AppEntryKind.widgets => platform,
    };
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// Fields that are not passed keep their current values.
  AppShellSnapshot copyWith({
    AppEntryKind? kind,
    ThemeData? theme,
    ThemeData? darkTheme,
    ThemeData? highContrastTheme,
    ThemeData? highContrastDarkTheme,
    ThemeMode? themeMode,
    Duration? themeAnimationDuration,
    Curve? themeAnimationCurve,
    AnimationStyle? themeAnimationStyle,
    CupertinoThemeData? cupertinoTheme,
    Color? color,
    Locale? locale,
    Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates,
    LocaleListResolutionCallback? localeListResolutionCallback,
    LocaleResolutionCallback? localeResolutionCallback,
    Iterable<Locale>? supportedLocales,
    bool? debugShowCheckedModeBanner,
    ScrollBehavior? scrollBehavior,
    Map<ShortcutActivator, Intent>? shortcuts,
    Map<Type, Action<Intent>>? actions,
    TextStyle? textStyle,
  }) {
    return AppShellSnapshot(
      kind: kind ?? this.kind,
      theme: theme ?? this.theme,
      darkTheme: darkTheme ?? this.darkTheme,
      highContrastTheme: highContrastTheme ?? this.highContrastTheme,
      highContrastDarkTheme: highContrastDarkTheme ?? this.highContrastDarkTheme,
      themeMode: themeMode ?? this.themeMode,
      themeAnimationDuration: themeAnimationDuration ?? this.themeAnimationDuration,
      themeAnimationCurve: themeAnimationCurve ?? this.themeAnimationCurve,
      themeAnimationStyle: themeAnimationStyle ?? this.themeAnimationStyle,
      cupertinoTheme: cupertinoTheme ?? this.cupertinoTheme,
      color: color ?? this.color,
      locale: locale ?? this.locale,
      localizationsDelegates: localizationsDelegates ?? this.localizationsDelegates,
      localeListResolutionCallback:
          localeListResolutionCallback ?? this.localeListResolutionCallback,
      localeResolutionCallback: localeResolutionCallback ?? this.localeResolutionCallback,
      supportedLocales: supportedLocales ?? this.supportedLocales,
      debugShowCheckedModeBanner: debugShowCheckedModeBanner ?? this.debugShowCheckedModeBanner,
      scrollBehavior: scrollBehavior ?? this.scrollBehavior,
      shortcuts: shortcuts ?? this.shortcuts,
      actions: actions ?? this.actions,
      textStyle: textStyle ?? this.textStyle,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppShellSnapshot &&
        other.kind == kind &&
        other.theme == theme &&
        other.darkTheme == darkTheme &&
        other.highContrastTheme == highContrastTheme &&
        other.highContrastDarkTheme == highContrastDarkTheme &&
        other.themeMode == themeMode &&
        other.themeAnimationDuration == themeAnimationDuration &&
        other.themeAnimationCurve == themeAnimationCurve &&
        other.themeAnimationStyle == themeAnimationStyle &&
        other.cupertinoTheme == cupertinoTheme &&
        other.color == color &&
        other.locale == locale &&
        other.localizationsDelegates == localizationsDelegates &&
        other.localeListResolutionCallback == localeListResolutionCallback &&
        other.localeResolutionCallback == localeResolutionCallback &&
        _iterableEquals(other.supportedLocales, supportedLocales) &&
        other.debugShowCheckedModeBanner == debugShowCheckedModeBanner &&
        other.scrollBehavior == scrollBehavior &&
        other.shortcuts == shortcuts &&
        other.actions == actions &&
        other.textStyle == textStyle;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    kind,
    theme,
    darkTheme,
    highContrastTheme,
    highContrastDarkTheme,
    themeMode,
    themeAnimationDuration,
    themeAnimationCurve,
    themeAnimationStyle,
    cupertinoTheme,
    color,
    locale,
    localizationsDelegates,
    localeListResolutionCallback,
    localeResolutionCallback,
    supportedLocales,
    debugShowCheckedModeBanner,
    scrollBehavior,
    shortcuts,
    actions,
    textStyle,
  ]);

  static bool _iterableEquals<T>(Iterable<T> a, Iterable<T> b) {
    final listA = a.toList();
    final listB = b.toList();
    if (listA.length != listB.length) return false;
    for (var i = 0; i < listA.length; i++) {
      if (listA[i] != listB[i]) return false;
    }
    return true;
  }
}
