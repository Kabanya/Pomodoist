import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_entry_kind.dart';
import 'app_shell_snapshot.dart';

/// Partial update applied through `AppShellController.patch`.
///
/// Contains only app-wide fields (theme, locale, shortcuts). Navigation and
/// router settings belong in `ViewShellOverrides` on `WindowOptions.shellOverrides`
/// or `MultiViewDesktop.patchViewShell`.
///
/// Example:
///
/// ```dart
/// MultiViewDesktop.appShell.patch(
///   AppShellPatch(themeMode: ThemeMode.dark),
/// );
/// ```
@immutable
class AppShellPatch {
  /// Creates a patch. All parameters are optional.
  const AppShellPatch({
    this.kind,
    this.theme,
    this.darkTheme,
    this.highContrastTheme,
    this.highContrastDarkTheme,
    this.themeMode,
    this.themeAnimationDuration,
    this.themeAnimationCurve,
    this.themeAnimationStyle,
    this.cupertinoTheme,
    this.color,
    this.locale,
    this.localizationsDelegates,
    this.localeListResolutionCallback,
    this.localeResolutionCallback,
    this.supportedLocales,
    this.debugShowCheckedModeBanner,
    this.scrollBehavior,
    this.shortcuts,
    this.actions,
    this.textStyle,
  });

  final AppEntryKind? kind;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeData? highContrastTheme;
  final ThemeData? highContrastDarkTheme;
  final ThemeMode? themeMode;
  final Duration? themeAnimationDuration;
  final Curve? themeAnimationCurve;
  final AnimationStyle? themeAnimationStyle;
  final CupertinoThemeData? cupertinoTheme;
  final Color? color;
  final Locale? locale;
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;
  final LocaleListResolutionCallback? localeListResolutionCallback;
  final LocaleResolutionCallback? localeResolutionCallback;
  final Iterable<Locale>? supportedLocales;
  final bool? debugShowCheckedModeBanner;
  final ScrollBehavior? scrollBehavior;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final Map<Type, Action<Intent>>? actions;
  final TextStyle? textStyle;

  /// Merges this patch into `current`. Used by the internal registry.
  AppShellSnapshot applyTo(AppShellSnapshot? current) {
    if (current == null) {
      return AppShellSnapshot(
        kind: kind ?? AppEntryKind.material,
        theme: theme,
        darkTheme: darkTheme,
        highContrastTheme: highContrastTheme,
        highContrastDarkTheme: highContrastDarkTheme,
        themeMode: themeMode ?? ThemeMode.system,
        themeAnimationDuration: themeAnimationDuration ?? kThemeAnimationDuration,
        themeAnimationCurve: themeAnimationCurve ?? Curves.linear,
        themeAnimationStyle: themeAnimationStyle,
        cupertinoTheme: cupertinoTheme,
        color: color,
        locale: locale,
        localizationsDelegates: localizationsDelegates,
        localeListResolutionCallback: localeListResolutionCallback,
        localeResolutionCallback: localeResolutionCallback,
        supportedLocales: supportedLocales ?? const <Locale>[Locale('en', 'US')],
        debugShowCheckedModeBanner: debugShowCheckedModeBanner ?? true,
        scrollBehavior: scrollBehavior,
        shortcuts: shortcuts,
        actions: actions,
        textStyle: textStyle,
      );
    }
    return current.copyWith(
      kind: kind,
      theme: theme,
      darkTheme: darkTheme,
      highContrastTheme: highContrastTheme,
      highContrastDarkTheme: highContrastDarkTheme,
      themeMode: themeMode,
      themeAnimationDuration: themeAnimationDuration,
      themeAnimationCurve: themeAnimationCurve,
      themeAnimationStyle: themeAnimationStyle,
      cupertinoTheme: cupertinoTheme,
      color: color,
      locale: locale,
      localizationsDelegates: localizationsDelegates,
      localeListResolutionCallback: localeListResolutionCallback,
      localeResolutionCallback: localeResolutionCallback,
      supportedLocales: supportedLocales,
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      scrollBehavior: scrollBehavior,
      shortcuts: shortcuts,
      actions: actions,
      textStyle: textStyle,
    );
  }

  /// Combines two view-local override patches. Non-null fields in `delta` win.
  static AppShellPatch merge(AppShellPatch? base, AppShellPatch delta) {
    if (base == null) return delta;
    return AppShellPatch(
      kind: delta.kind ?? base.kind,
      theme: delta.theme ?? base.theme,
      darkTheme: delta.darkTheme ?? base.darkTheme,
      highContrastTheme: delta.highContrastTheme ?? base.highContrastTheme,
      highContrastDarkTheme: delta.highContrastDarkTheme ?? base.highContrastDarkTheme,
      themeMode: delta.themeMode ?? base.themeMode,
      themeAnimationDuration: delta.themeAnimationDuration ?? base.themeAnimationDuration,
      themeAnimationCurve: delta.themeAnimationCurve ?? base.themeAnimationCurve,
      themeAnimationStyle: delta.themeAnimationStyle ?? base.themeAnimationStyle,
      cupertinoTheme: delta.cupertinoTheme ?? base.cupertinoTheme,
      color: delta.color ?? base.color,
      locale: delta.locale ?? base.locale,
      localizationsDelegates: delta.localizationsDelegates ?? base.localizationsDelegates,
      localeListResolutionCallback:
          delta.localeListResolutionCallback ?? base.localeListResolutionCallback,
      localeResolutionCallback: delta.localeResolutionCallback ?? base.localeResolutionCallback,
      supportedLocales: delta.supportedLocales ?? base.supportedLocales,
      debugShowCheckedModeBanner:
          delta.debugShowCheckedModeBanner ?? base.debugShowCheckedModeBanner,
      scrollBehavior: delta.scrollBehavior ?? base.scrollBehavior,
      shortcuts: delta.shortcuts ?? base.shortcuts,
      actions: delta.actions ?? base.actions,
      textStyle: delta.textStyle ?? base.textStyle,
    );
  }

  /// Builds the effective app-wide shell for one view.
  static AppShellSnapshot? composeAppearance(AppShellSnapshot? global, AppShellPatch? local) {
    if (local == null) return global;
    return local.applyTo(global);
  }
}
