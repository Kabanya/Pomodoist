import 'package:flutter/material.dart';

import 'app_shell_patch.dart';

/// Per-view entry shell configuration for a secondary or dialog `View`.
///
/// `appearance` overrides app-wide fields (theme, locale, shortcuts) on top of
/// the global `MultiViewDesktop.appShell` snapshot for **this view only**.
///
/// Navigation fields (`routerConfig`, `home`, `routes`, and so on) are also
/// per-view. Each OS window gets its own navigator or router stack. They are
/// never shared through the global `AppShellController`.
///
/// Simple content window (default: `openWindow` builder becomes `home`):
///
/// ```dart
/// openWindow((_, __) => SettingsPage());
/// ```
///
/// Different locale on one window, same theme as everywhere else:
///
/// ```dart
/// openWindow(
///   (_, __) => SettingsPage(),
///   options: WindowOptions(
///     shellOverrides: ViewShellOverrides(
///       appearance: AppShellPatch(locale: const Locale('de')),
///     ),
///   ),
/// );
/// ```
///
/// Dedicated router for one secondary window:
///
/// ```dart
/// openWindow(
///   (_, __) => const SizedBox.shrink(),
///   options: WindowOptions(
///     shellOverrides: ViewShellOverrides(
///       routerConfig: settingsRouter,
///     ),
///   ),
/// );
/// ```
@immutable
class ViewShellOverrides {
  const ViewShellOverrides({
    this.appearance,
    this.navigatorKey,
    this.scaffoldMessengerKey,
    this.home,
    this.routes,
    this.initialRoute,
    this.onGenerateRoute,
    this.onGenerateInitialRoutes,
    this.onUnknownRoute,
    this.onNavigationNotification,
    this.navigatorObservers,
    this.builder,
    this.title,
    this.onGenerateTitle,
    this.routerConfig,
    this.routeInformationProvider,
    this.routeInformationParser,
    this.routerDelegate,
    this.backButtonDispatcher,
    this.pageRouteBuilder,
    this.restorationScopeId,
  });

  /// Shorthand for appearance-only overrides.
  factory ViewShellOverrides.appearance(AppShellPatch patch) => ViewShellOverrides(appearance: patch);

  /// App-wide shell fields overridden for this view (theme, locale, and so on).
  final AppShellPatch? appearance;

  // ---------------------------------------------------------------------------
  // Navigation (per-view only)
  // ---------------------------------------------------------------------------

  /// Navigator key for this view only.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Scaffold messenger key for this view only.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  /// Root widget when this view uses imperative routing instead of a router.
  final Widget? home;

  /// Named routes map for this view.
  final Map<String, WidgetBuilder>? routes;

  /// Initial route name when `routes` is used.
  final String? initialRoute;

  /// Route generator for this view.
  final RouteFactory? onGenerateRoute;

  /// Builds the initial route stack for this view.
  final InitialRouteListFactory? onGenerateInitialRoutes;

  /// Fallback route generator for unknown names.
  final RouteFactory? onUnknownRoute;

  /// Called when a `NavigationNotification` is dispatched in this view.
  final NotificationListenerCallback<NavigationNotification>? onNavigationNotification;

  /// Observers attached to this view's navigator.
  final List<NavigatorObserver>? navigatorObservers;

  /// Wraps the navigator for this view.
  final TransitionBuilder? builder;

  /// Window title string used by the entry shell on this view.
  final String? title;

  /// Generates the title from `BuildContext` on this view.
  final GenerateAppTitle? onGenerateTitle;

  /// Router config for this view (Flutter 3.7+ declarative routing).
  final RouterConfig<Object>? routerConfig;

  /// Route information provider for this view's router.
  final RouteInformationProvider? routeInformationProvider;

  /// Route information parser for this view's router.
  final RouteInformationParser<Object>? routeInformationParser;

  /// Router delegate for this view.
  final RouterDelegate<Object>? routerDelegate;

  /// Back button dispatcher for this view's router.
  final BackButtonDispatcher? backButtonDispatcher;

  /// Custom `PageRoute` factory for this view.
  final PageRouteFactory? pageRouteBuilder;

  /// Restoration scope id for this view's navigator.
  final String? restorationScopeId;

  /// Whether this view uses a router-based entry instead of `home`.
  bool get usesRouter => routerConfig != null || routerDelegate != null;

  /// Combines `base` with `delta`. Non-null fields in `delta` replace `base`.
  ///
  /// Returns the merged overrides. Used internally when patching view shells.
  static ViewShellOverrides merge(ViewShellOverrides? base, ViewShellOverrides delta) {
    if (base == null) return delta;
    return ViewShellOverrides(
      appearance: delta.appearance != null
          ? AppShellPatch.merge(base.appearance, delta.appearance!)
          : base.appearance,
      navigatorKey: delta.navigatorKey ?? base.navigatorKey,
      scaffoldMessengerKey: delta.scaffoldMessengerKey ?? base.scaffoldMessengerKey,
      home: delta.home ?? base.home,
      routes: delta.routes ?? base.routes,
      initialRoute: delta.initialRoute ?? base.initialRoute,
      onGenerateRoute: delta.onGenerateRoute ?? base.onGenerateRoute,
      onGenerateInitialRoutes: delta.onGenerateInitialRoutes ?? base.onGenerateInitialRoutes,
      onUnknownRoute: delta.onUnknownRoute ?? base.onUnknownRoute,
      onNavigationNotification: delta.onNavigationNotification ?? base.onNavigationNotification,
      navigatorObservers: delta.navigatorObservers ?? base.navigatorObservers,
      builder: delta.builder ?? base.builder,
      title: delta.title ?? base.title,
      onGenerateTitle: delta.onGenerateTitle ?? base.onGenerateTitle,
      routerConfig: delta.routerConfig ?? base.routerConfig,
      routeInformationProvider: delta.routeInformationProvider ?? base.routeInformationProvider,
      routeInformationParser: delta.routeInformationParser ?? base.routeInformationParser,
      routerDelegate: delta.routerDelegate ?? base.routerDelegate,
      backButtonDispatcher: delta.backButtonDispatcher ?? base.backButtonDispatcher,
      pageRouteBuilder: delta.pageRouteBuilder ?? base.pageRouteBuilder,
      restorationScopeId: delta.restorationScopeId ?? base.restorationScopeId,
    );
  }
}
