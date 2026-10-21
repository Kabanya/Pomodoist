import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_shell/app_shell_patch.dart';
import 'app_shell/app_shell_registry.dart';
import 'app_shell/app_shell_snapshot.dart';
import 'app_shell/app_entry_kind.dart';
import 'app_shell/view_shell_overrides.dart';
/// Finds `MaterialApp` / `CupertinoApp` / `WidgetsApp` in the main view tree.
abstract final class AppEntryPointFinder {
  /// Walks **up** from `context` and keeps the outermost recognized entry widget.
  static AppShellSnapshot? findOutermostUpstream(BuildContext context) {
    AppShellSnapshot? material;
    AppShellSnapshot? cupertino;
    AppShellSnapshot? widgets;

    context.visitAncestorElements((Element ancestor) {
      final widget = ancestor.widget;
      if (widget is MaterialApp) {
        material = AppShellSnapshot.fromMaterialApp(widget);
      } else if (widget is CupertinoApp) {
        cupertino = AppShellSnapshot.fromCupertinoApp(widget);
      } else if (widget is WidgetsApp) {
        widgets = AppShellSnapshot.fromWidgetsApp(widget);
      }
      return true;
    });

    return material ?? cupertino ?? widgets;
  }

  /// Walks **down** from `root` and returns the shallowest recognized entry widget.
  static AppShellSnapshot? findShallowestInSubtree(Element root) {
    AppShellSnapshot? material;
    AppShellSnapshot? cupertino;
    AppShellSnapshot? widgets;
    var materialDepth = 1 << 30;
    var cupertinoDepth = 1 << 30;
    var widgetsDepth = 1 << 30;

    void visit(Element element, int depth) {
      final widget = element.widget;
      if (widget is MaterialApp && depth < materialDepth) {
        material = AppShellSnapshot.fromMaterialApp(widget);
        materialDepth = depth;
      } else if (widget is CupertinoApp && depth < cupertinoDepth) {
        cupertino = AppShellSnapshot.fromCupertinoApp(widget);
        cupertinoDepth = depth;
      } else if (widget is WidgetsApp && depth < widgetsDepth) {
        widgets = AppShellSnapshot.fromWidgetsApp(widget);
        widgetsDepth = depth;
      }
      element.visitChildren((Element child) => visit(child, depth + 1));
    }

    root.visitChildren((Element child) => visit(child, 0));
    return material ?? cupertino ?? widgets;
  }
}

/// Captures the main entry widget into `registry` after each frame.
class MainAppShellCapture extends StatefulWidget {
  const MainAppShellCapture({super.key, required this.registry, required this.child});

  final AppShellRegistry registry;
  final Widget child;

  @override
  State<MainAppShellCapture> createState() => _MainAppShellCaptureState();
}

class _MainAppShellCaptureState extends State<MainAppShellCapture> {
  bool _captureLoopScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleCaptureLoop();
  }

  @override
  void dispose() {
    _captureLoopScheduled = false;
    super.dispose();
  }

  /// Re-syncs after every frame while mounted.
  ///
  /// `homeBuilder` may return a `StatefulWidget` (e.g. `MainWindowRoot`) whose
  /// inner `MaterialApp` rebuilds without updating this capture widget. A
  /// one-shot capture on `didUpdateWidget` misses runtime theme/locale changes.
  void _scheduleCaptureLoop() {
    if (_captureLoopScheduled || !mounted) return;
    _captureLoopScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_onPostFrameCapture);
  }

  void _onPostFrameCapture(_) {
    _captureLoopScheduled = false;
    if (!mounted) return;
    _captureFromSubtree();
    _scheduleCaptureLoop();
  }

  void _captureFromSubtree() {
    final snapshot = AppEntryPointFinder.findShallowestInSubtree(context as Element);
    widget.registry.replace(snapshot);
  }

  void _captureFromUpstream(BuildContext context) {
    widget.registry.replace(AppEntryPointFinder.findOutermostUpstream(context));
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child is MaterialApp) {
      return _MaterialAppWithUpstreamProbe(
        app: child,
        onUpstreamContext: _captureFromUpstream,
      );
    }
    if (child is CupertinoApp) {
      return _CupertinoAppWithUpstreamProbe(
        app: child,
        onUpstreamContext: _captureFromUpstream,
      );
    }
    if (child is WidgetsApp) {
      return _WidgetsAppWithUpstreamProbe(
        app: child,
        onUpstreamContext: _captureFromUpstream,
      );
    }
    return child;
  }
}

class _AppShellUpstreamProbe extends StatefulWidget {
  const _AppShellUpstreamProbe({required this.onUpstreamContext, required this.child});

  final void Function(BuildContext context) onUpstreamContext;
  final Widget child;

  @override
  State<_AppShellUpstreamProbe> createState() => _AppShellUpstreamProbeState();
}

class _AppShellUpstreamProbeState extends State<_AppShellUpstreamProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_probe);
  }

  @override
  void didUpdateWidget(covariant _AppShellUpstreamProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_probe);
  }

  void _probe(_) {
    if (mounted) widget.onUpstreamContext(context);
  }

  @override
  Widget build(BuildContext context) {
    // Runs when an ancestor `MaterialApp` rebuilds (e.g. `ThemeMode` toggle).
    WidgetsBinding.instance.addPostFrameCallback(_probe);
    return widget.child;
  }
}

class _MaterialAppWithUpstreamProbe extends StatelessWidget {
  const _MaterialAppWithUpstreamProbe({required this.app, required this.onUpstreamContext});

  final MaterialApp app;
  final void Function(BuildContext context) onUpstreamContext;

  @override
  Widget build(BuildContext context) {
    final isRouter = app.routerConfig != null || app.routerDelegate != null;
    if (isRouter) {
      return MaterialApp.router(
        scaffoldMessengerKey: app.scaffoldMessengerKey,
        routeInformationProvider: app.routeInformationProvider,
        routeInformationParser: app.routeInformationParser,
        routerDelegate: app.routerDelegate,
        routerConfig: app.routerConfig,
        backButtonDispatcher: app.backButtonDispatcher,
        builder: _mergeBuilder(app.builder, onUpstreamContext),
        title: app.title,
        onGenerateTitle: app.onGenerateTitle,
        onNavigationNotification: app.onNavigationNotification,
        color: app.color,
        theme: app.theme,
        darkTheme: app.darkTheme,
        highContrastTheme: app.highContrastTheme,
        highContrastDarkTheme: app.highContrastDarkTheme,
        themeMode: app.themeMode,
        themeAnimationDuration: app.themeAnimationDuration,
        themeAnimationCurve: app.themeAnimationCurve,
        locale: app.locale,
        localizationsDelegates: app.localizationsDelegates,
        localeListResolutionCallback: app.localeListResolutionCallback,
        localeResolutionCallback: app.localeResolutionCallback,
        supportedLocales: app.supportedLocales,
        debugShowMaterialGrid: app.debugShowMaterialGrid,
        showPerformanceOverlay: app.showPerformanceOverlay,
        checkerboardRasterCacheImages: app.checkerboardRasterCacheImages,
        checkerboardOffscreenLayers: app.checkerboardOffscreenLayers,
        showSemanticsDebugger: app.showSemanticsDebugger,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        shortcuts: app.shortcuts,
        actions: app.actions,
        restorationScopeId: app.restorationScopeId,
        scrollBehavior: app.scrollBehavior,
        themeAnimationStyle: app.themeAnimationStyle,
      );
    }

    return MaterialApp(
      navigatorKey: app.navigatorKey,
      scaffoldMessengerKey: app.scaffoldMessengerKey,
      home: app.home == null
          ? null
          : _AppShellUpstreamProbe(onUpstreamContext: onUpstreamContext, child: app.home!),
      routes: app.routes ?? const <String, WidgetBuilder>{},
      initialRoute: app.initialRoute,
      onGenerateRoute: app.onGenerateRoute,
      onGenerateInitialRoutes: app.onGenerateInitialRoutes,
      onUnknownRoute: app.onUnknownRoute,
      onNavigationNotification: app.onNavigationNotification,
      navigatorObservers: app.navigatorObservers ?? const <NavigatorObserver>[],
      builder: _mergeBuilder(app.builder, onUpstreamContext),
      title: app.title,
      onGenerateTitle: app.onGenerateTitle,
      color: app.color,
      theme: app.theme,
      darkTheme: app.darkTheme,
      highContrastTheme: app.highContrastTheme,
      highContrastDarkTheme: app.highContrastDarkTheme,
      themeMode: app.themeMode,
      themeAnimationDuration: app.themeAnimationDuration,
      themeAnimationCurve: app.themeAnimationCurve,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      debugShowMaterialGrid: app.debugShowMaterialGrid,
      showPerformanceOverlay: app.showPerformanceOverlay,
      checkerboardRasterCacheImages: app.checkerboardRasterCacheImages,
      checkerboardOffscreenLayers: app.checkerboardOffscreenLayers,
      showSemanticsDebugger: app.showSemanticsDebugger,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
      shortcuts: app.shortcuts,
      actions: app.actions,
      restorationScopeId: app.restorationScopeId,
      scrollBehavior: app.scrollBehavior,
      themeAnimationStyle: app.themeAnimationStyle,
    );
  }
}

class _CupertinoAppWithUpstreamProbe extends StatelessWidget {
  const _CupertinoAppWithUpstreamProbe({required this.app, required this.onUpstreamContext});

  final CupertinoApp app;
  final void Function(BuildContext context) onUpstreamContext;

  @override
  Widget build(BuildContext context) {
    final isRouter = app.routerConfig != null || app.routerDelegate != null;
    if (isRouter) {
      return CupertinoApp.router(
        routeInformationProvider: app.routeInformationProvider,
        routeInformationParser: app.routeInformationParser,
        routerDelegate: app.routerDelegate,
        routerConfig: app.routerConfig,
        backButtonDispatcher: app.backButtonDispatcher,
        builder: _mergeBuilder(app.builder, onUpstreamContext),
        title: app.title,
        onGenerateTitle: app.onGenerateTitle,
        onNavigationNotification: app.onNavigationNotification,
        theme: app.theme,
        color: app.color,
        locale: app.locale,
        localizationsDelegates: app.localizationsDelegates,
        localeListResolutionCallback: app.localeListResolutionCallback,
        localeResolutionCallback: app.localeResolutionCallback,
        supportedLocales: app.supportedLocales,
        showPerformanceOverlay: app.showPerformanceOverlay,
        checkerboardRasterCacheImages: app.checkerboardRasterCacheImages,
        checkerboardOffscreenLayers: app.checkerboardOffscreenLayers,
        showSemanticsDebugger: app.showSemanticsDebugger,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        shortcuts: app.shortcuts,
        actions: app.actions,
        restorationScopeId: app.restorationScopeId,
        scrollBehavior: app.scrollBehavior,
      );
    }

    return CupertinoApp(
      navigatorKey: app.navigatorKey,
      home: app.home == null
          ? null
          : _AppShellUpstreamProbe(onUpstreamContext: onUpstreamContext, child: app.home!),
      theme: app.theme,
      routes: app.routes ?? const <String, WidgetBuilder>{},
      initialRoute: app.initialRoute,
      onGenerateRoute: app.onGenerateRoute,
      onGenerateInitialRoutes: app.onGenerateInitialRoutes,
      onUnknownRoute: app.onUnknownRoute,
      onNavigationNotification: app.onNavigationNotification,
      navigatorObservers: app.navigatorObservers ?? const <NavigatorObserver>[],
      builder: _mergeBuilder(app.builder, onUpstreamContext),
      title: app.title,
      onGenerateTitle: app.onGenerateTitle,
      color: app.color,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      showPerformanceOverlay: app.showPerformanceOverlay,
      checkerboardRasterCacheImages: app.checkerboardRasterCacheImages,
      checkerboardOffscreenLayers: app.checkerboardOffscreenLayers,
      showSemanticsDebugger: app.showSemanticsDebugger,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
      shortcuts: app.shortcuts,
      actions: app.actions,
      restorationScopeId: app.restorationScopeId,
      scrollBehavior: app.scrollBehavior,
    );
  }
}

class _WidgetsAppWithUpstreamProbe extends StatelessWidget {
  const _WidgetsAppWithUpstreamProbe({required this.app, required this.onUpstreamContext});

  final WidgetsApp app;
  final void Function(BuildContext context) onUpstreamContext;

  @override
  Widget build(BuildContext context) {
    final isRouter = app.routerConfig != null || app.routerDelegate != null;
    if (isRouter) {
      return WidgetsApp.router(
        key: app.key,
        routeInformationProvider: app.routeInformationProvider,
        routeInformationParser: app.routeInformationParser,
        routerDelegate: app.routerDelegate,
        routerConfig: app.routerConfig,
        backButtonDispatcher: app.backButtonDispatcher,
        builder: _mergeBuilder(app.builder, onUpstreamContext),
        title: app.title,
        onGenerateTitle: app.onGenerateTitle,
        onNavigationNotification: app.onNavigationNotification,
        textStyle: app.textStyle,
        color: app.color,
        locale: app.locale,
        localizationsDelegates: app.localizationsDelegates,
        localeListResolutionCallback: app.localeListResolutionCallback,
        localeResolutionCallback: app.localeResolutionCallback,
        supportedLocales: app.supportedLocales,
        showPerformanceOverlay: app.showPerformanceOverlay,
        showSemanticsDebugger: app.showSemanticsDebugger,
        debugShowWidgetInspector: app.debugShowWidgetInspector,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        exitWidgetSelectionButtonBuilder: app.exitWidgetSelectionButtonBuilder,
        moveExitWidgetSelectionButtonBuilder: app.moveExitWidgetSelectionButtonBuilder,
        tapBehaviorButtonBuilder: app.tapBehaviorButtonBuilder,
        shortcuts: app.shortcuts,
        actions: app.actions,
        restorationScopeId: app.restorationScopeId,
      );
    }

    return WidgetsApp(
      key: app.key,
      navigatorKey: app.navigatorKey,
      onGenerateRoute: app.onGenerateRoute,
      onGenerateInitialRoutes: app.onGenerateInitialRoutes,
      onUnknownRoute: app.onUnknownRoute,
      onNavigationNotification: app.onNavigationNotification,
      navigatorObservers: app.navigatorObservers ?? const <NavigatorObserver>[],
      initialRoute: app.initialRoute,
      pageRouteBuilder: app.pageRouteBuilder,
      home: app.home == null
          ? null
          : _AppShellUpstreamProbe(onUpstreamContext: onUpstreamContext, child: app.home!),
      routes: app.routes ?? const <String, WidgetBuilder>{},
      builder: _mergeBuilder(app.builder, onUpstreamContext),
      title: app.title,
      onGenerateTitle: app.onGenerateTitle,
      textStyle: app.textStyle,
      color: app.color,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      showPerformanceOverlay: app.showPerformanceOverlay,
      showSemanticsDebugger: app.showSemanticsDebugger,
      debugShowWidgetInspector: app.debugShowWidgetInspector,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
      exitWidgetSelectionButtonBuilder: app.exitWidgetSelectionButtonBuilder,
      moveExitWidgetSelectionButtonBuilder: app.moveExitWidgetSelectionButtonBuilder,
      tapBehaviorButtonBuilder: app.tapBehaviorButtonBuilder,
      shortcuts: app.shortcuts,
      actions: app.actions,
      restorationScopeId: app.restorationScopeId,
    );
  }
}

TransitionBuilder _mergeBuilder(
  TransitionBuilder? original,
  void Function(BuildContext context) onUpstreamContext,
) {
  return (BuildContext context, Widget? child) {
    return _AppShellUpstreamProbe(
      onUpstreamContext: onUpstreamContext,
      child: original == null ? child ?? const SizedBox.shrink() : original(context, child),
    );
  };
}

/// Secondary/dialog shell: global appearance plus optional per-view navigation.
class SharedEntryApp extends StatelessWidget {
  const SharedEntryApp({
    super.key,
    required this.registry,
    required this.viewShellOverrides,
    required this.child,
  });

  final AppShellRegistry registry;
  final ValueNotifier<ViewShellOverrides?> viewShellOverrides;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([registry, viewShellOverrides]),
      builder: (BuildContext context, _) {
        final view = viewShellOverrides.value;
        final shell = AppShellPatch.composeAppearance(registry.snapshot, view?.appearance);
        if (shell == null && view == null) return child;
        final effective = shell ?? const AppShellSnapshot(kind: AppEntryKind.material);
        return switch (effective.kind) {
          AppEntryKind.material => _materialShell(effective, view, child),
          AppEntryKind.cupertino => _cupertinoShell(effective, view, child),
          AppEntryKind.widgets => _widgetsShell(effective, view, child),
        };
      },
    );
  }

  Widget _materialShell(AppShellSnapshot shell, ViewShellOverrides? nav, Widget child) {
    if (nav?.usesRouter ?? false) {
      return MaterialApp.router(
        scaffoldMessengerKey: nav!.scaffoldMessengerKey,
        routeInformationProvider: nav.routeInformationProvider,
        routeInformationParser: nav.routeInformationParser,
        routerDelegate: nav.routerDelegate,
        routerConfig: nav.routerConfig,
        backButtonDispatcher: nav.backButtonDispatcher,
        builder: nav.builder,
        title: nav.title ?? '',
        onGenerateTitle: nav.onGenerateTitle,
        onNavigationNotification: nav.onNavigationNotification,
        theme: shell.theme,
        darkTheme: shell.darkTheme,
        highContrastTheme: shell.highContrastTheme,
        highContrastDarkTheme: shell.highContrastDarkTheme,
        themeMode: shell.themeMode,
        themeAnimationDuration: shell.themeAnimationDuration,
        themeAnimationCurve: shell.themeAnimationCurve,
        themeAnimationStyle: shell.themeAnimationStyle,
        color: shell.color,
        locale: shell.locale,
        localizationsDelegates: shell.localizationsDelegates,
        localeListResolutionCallback: shell.localeListResolutionCallback,
        localeResolutionCallback: shell.localeResolutionCallback,
        supportedLocales: shell.supportedLocales,
        debugShowCheckedModeBanner: shell.debugShowCheckedModeBanner,
        scrollBehavior: shell.scrollBehavior,
        shortcuts: shell.shortcuts,
        actions: shell.actions,
        restorationScopeId: nav.restorationScopeId,
      );
    }

    final home = nav?.home ?? Builder(builder: (_) => child);
    return MaterialApp(
      navigatorKey: nav?.navigatorKey,
      scaffoldMessengerKey: nav?.scaffoldMessengerKey,
      home: home,
      routes: nav?.routes ?? const <String, WidgetBuilder>{},
      initialRoute: nav?.initialRoute,
      onGenerateRoute: nav?.onGenerateRoute,
      onGenerateInitialRoutes: nav?.onGenerateInitialRoutes,
      onUnknownRoute: nav?.onUnknownRoute,
      onNavigationNotification: nav?.onNavigationNotification,
      navigatorObservers: nav?.navigatorObservers ?? const <NavigatorObserver>[],
      builder: nav?.builder,
      title: nav?.title ?? '',
      onGenerateTitle: nav?.onGenerateTitle,
      restorationScopeId: nav?.restorationScopeId,
      theme: shell.theme,
      darkTheme: shell.darkTheme,
      highContrastTheme: shell.highContrastTheme,
      highContrastDarkTheme: shell.highContrastDarkTheme,
      themeMode: shell.themeMode,
      themeAnimationDuration: shell.themeAnimationDuration,
      themeAnimationCurve: shell.themeAnimationCurve,
      themeAnimationStyle: shell.themeAnimationStyle,
      color: shell.color,
      locale: shell.locale,
      localizationsDelegates: shell.localizationsDelegates,
      localeListResolutionCallback: shell.localeListResolutionCallback,
      localeResolutionCallback: shell.localeResolutionCallback,
      supportedLocales: shell.supportedLocales,
      debugShowCheckedModeBanner: shell.debugShowCheckedModeBanner,
      scrollBehavior: shell.scrollBehavior,
      shortcuts: shell.shortcuts,
      actions: shell.actions,
    );
  }

  Widget _cupertinoShell(AppShellSnapshot shell, ViewShellOverrides? nav, Widget child) {
    if (nav?.usesRouter ?? false) {
      return CupertinoApp.router(
        routeInformationProvider: nav!.routeInformationProvider,
        routeInformationParser: nav.routeInformationParser,
        routerDelegate: nav.routerDelegate,
        routerConfig: nav.routerConfig,
        backButtonDispatcher: nav.backButtonDispatcher,
        builder: nav.builder,
        title: nav.title,
        onGenerateTitle: nav.onGenerateTitle,
        onNavigationNotification: nav.onNavigationNotification,
        theme: shell.cupertinoTheme,
        color: shell.color,
        locale: shell.locale,
        localizationsDelegates: shell.localizationsDelegates,
        localeListResolutionCallback: shell.localeListResolutionCallback,
        localeResolutionCallback: shell.localeResolutionCallback,
        supportedLocales: shell.supportedLocales,
        debugShowCheckedModeBanner: shell.debugShowCheckedModeBanner,
        scrollBehavior: shell.scrollBehavior,
        shortcuts: shell.shortcuts,
        actions: shell.actions,
        restorationScopeId: nav.restorationScopeId,
      );
    }

    final home = nav?.home ?? Builder(builder: (_) => child);
    return CupertinoApp(
      navigatorKey: nav?.navigatorKey,
      home: home,
      routes: nav?.routes ?? const <String, WidgetBuilder>{},
      initialRoute: nav?.initialRoute,
      onGenerateRoute: nav?.onGenerateRoute,
      onGenerateInitialRoutes: nav?.onGenerateInitialRoutes,
      onUnknownRoute: nav?.onUnknownRoute,
      onNavigationNotification: nav?.onNavigationNotification,
      navigatorObservers: nav?.navigatorObservers ?? const <NavigatorObserver>[],
      builder: nav?.builder,
      title: nav?.title,
      onGenerateTitle: nav?.onGenerateTitle,
      theme: shell.cupertinoTheme,
      color: shell.color,
      locale: shell.locale,
      localizationsDelegates: shell.localizationsDelegates,
      localeListResolutionCallback: shell.localeListResolutionCallback,
      localeResolutionCallback: shell.localeResolutionCallback,
      supportedLocales: shell.supportedLocales,
      debugShowCheckedModeBanner: shell.debugShowCheckedModeBanner,
      scrollBehavior: shell.scrollBehavior,
      shortcuts: shell.shortcuts,
      actions: shell.actions,
      restorationScopeId: nav?.restorationScopeId,
    );
  }

  Widget _widgetsShell(AppShellSnapshot shell, ViewShellOverrides? nav, Widget child) {
    if (nav?.usesRouter ?? false) {
      return WidgetsApp.router(
        routeInformationProvider: nav!.routeInformationProvider,
        routeInformationParser: nav.routeInformationParser,
        routerDelegate: nav.routerDelegate,
        routerConfig: nav.routerConfig,
        backButtonDispatcher: nav.backButtonDispatcher,
        builder: nav.builder,
        title: nav.title,
        onGenerateTitle: nav.onGenerateTitle,
        onNavigationNotification: nav.onNavigationNotification,
        textStyle: shell.textStyle,
        color: shell.color ?? const Color(0xFF2196F3),
        locale: shell.locale,
        localizationsDelegates: shell.localizationsDelegates,
        localeListResolutionCallback: shell.localeListResolutionCallback,
        localeResolutionCallback: shell.localeResolutionCallback,
        supportedLocales: shell.supportedLocales,
        debugShowCheckedModeBanner: shell.debugShowCheckedModeBanner,
        shortcuts: shell.shortcuts,
        actions: shell.actions,
        restorationScopeId: nav.restorationScopeId,
      );
    }

    final home = nav?.home ?? Builder(builder: (_) => child);
    return WidgetsApp(
      navigatorKey: nav?.navigatorKey,
      onGenerateRoute: nav?.onGenerateRoute,
      onGenerateInitialRoutes: nav?.onGenerateInitialRoutes,
      onUnknownRoute: nav?.onUnknownRoute,
      onNavigationNotification: nav?.onNavigationNotification,
      navigatorObservers: nav?.navigatorObservers ?? const <NavigatorObserver>[],
      initialRoute: nav?.initialRoute,
      pageRouteBuilder: nav?.pageRouteBuilder,
      home: home,
      routes: nav?.routes ?? const <String, WidgetBuilder>{},
      builder: nav?.builder,
      title: nav?.title,
      onGenerateTitle: nav?.onGenerateTitle,
      textStyle: shell.textStyle,
      color: shell.color ?? const Color(0xFF2196F3),
      locale: shell.locale,
      localizationsDelegates: shell.localizationsDelegates,
      localeListResolutionCallback: shell.localeListResolutionCallback,
      localeResolutionCallback: shell.localeResolutionCallback,
      supportedLocales: shell.supportedLocales,
      debugShowCheckedModeBanner: shell.debugShowCheckedModeBanner,
      shortcuts: shell.shortcuts,
      actions: shell.actions,
      restorationScopeId: nav?.restorationScopeId,
    );
  }
}
