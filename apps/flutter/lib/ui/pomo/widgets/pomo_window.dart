import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadApp,
        ShadAppBuilder,
        ShadTheme,
        GlobalShadLocalizations,
        ShadContextMenuController,
        ShadContextMenuItem;
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/view_models/app_theme_mode_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_context_menu_region.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'package:pomodoist/ui/quick_add/view_models/global_quick_add_view_model.dart';

import 'pomo_geometry.dart';
import 'pomo_stage_canvas.dart';
import 'pomo_model.dart';
import 'pomo_scale_control.dart';
import 'pomo_settings.dart';
import '../view_models/pomo_window_host.dart';

class PomoWindow extends ConsumerStatefulWidget {
  const PomoWindow({super.key, this.settingsPanel = false});
  final bool settingsPanel;
  @override
  ConsumerState<PomoWindow> createState() => _PomoWindowState();
}

class _PomoWindowState extends ConsumerState<PomoWindow> {
  final _canvasKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final (scale, usesGnomeShell) = ref.watch(
      pomoControllerProvider.select(
        (c) => (c.effectiveScale, (c.host as PomoWindowHost).usesGnomeShell),
      ),
    );
    final size = PomoLayout(scale).size;
    final stageSize = widget.settingsPanel
        ? PomoWindowHost.panelSize
        : Size(size.width.ceilToDouble(), size.height.ceilToDouble());
    final settings = ref.watch(appThemeSettingsProvider);
    final light = AppTheme.light(palette: settings.activeTheme.light);
    final dark = AppTheme.dark(palette: settings.activeTheme.dark);
    final themeMode = ref.watch(appThemeModeProvider).themeMode;
    final locale = resolveAppLocale(ref.watch(quickAddWindowLanguageProvider));
    final reduceMotion = ref.watch(
      pomoControllerProvider.select((c) => c.prefs.reduceMotion),
    );
    return ShadApp.custom(
      theme: AppTheme.shadFromMaterial(light),
      darkTheme: AppTheme.shadFromMaterial(dark),
      themeMode: themeMode,
      appBuilder: (context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalShadLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => PomoStageCanvas(
          enabled: usesGnomeShell,
          stageSize: stageSize,
          canvasKey: _canvasKey,
          child: ShadTheme(
            data: AppTheme.shadFromMaterial(
              Theme.of(context),
              reduceMotion:
                  reduceMotion || MediaQuery.disableAnimationsOf(context),
            ),
            child: ShadAppBuilder(
              backgroundColor: Colors.transparent,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
        home: widget.settingsPanel
            ? const _SettingsPanel()
            : _Satellites(canvasKey: _canvasKey),
      ),
    );
  }
}

class _Satellites extends ConsumerStatefulWidget {
  const _Satellites({required this.canvasKey});
  final GlobalKey canvasKey;
  @override
  ConsumerState<_Satellites> createState() => _SatellitesState();
}

class _SatellitesState extends ConsumerState<_Satellites> with WindowListener {
  final _contextMenu = ShadContextMenuController();
  final _openAppItem = GlobalKey();
  final _hideItem = GlobalKey();
  Rect? _contextBounds;

  @override
  void initState() {
    super.initState();
    _contextMenu.addListener(_contextMenuChanged);
  }

  void _contextMenuChanged() {
    if (_contextMenu.isOpen) {
      unawaited(
        ref
            .read(pomoControllerProvider)
            .perform(() => MultiViewDesktop.of(context).focus()),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncContextMenuBounds(),
    );
  }

  void _syncContextMenuBounds() {
    if (!mounted) return;
    final c = ref.read(pomoControllerProvider);
    final canvas =
        widget.canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvas == null || !canvas.hasSize) return;
    final bounds = !_contextMenu.isOpen
        ? null
        : pomoMenuBoundsInCanvas(
            canvas,
            [_openAppItem, _hideItem]
                .map((key) => key.currentContext?.findRenderObject())
                .whereType<RenderBox>(),
            clip: (c.host as PomoWindowHost).usesGnomeShell
                ? null
                : Offset.zero & PomoLayout(c.effectiveScale).size,
          );
    if (_contextBounds == bounds) return;
    _contextBounds = bounds;
    unawaited(
      c.perform(() => (c.host as PomoWindowHost).setContextMenuBounds(bounds)),
    );
  }

  @override
  void dispose() {
    _contextMenu.removeListener(_contextMenuChanged);
    _contextMenu.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(ref.read(pomoControllerProvider).hideManually());
  }

  @override
  void onWindowMoved() {
    unawaited(
      (ref.read(pomoControllerProvider).host as PomoWindowHost).moved(),
    );
  }

  @override
  void onWindowBlur() {
    _contextMenu.hide();
    unawaited(ref.read(pomoControllerProvider).collapse());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    Future.microtask(() {
      if (mounted) ref.read(pomoControllerProvider).setSystemMotion(reduced);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(pomoControllerProvider);
    if (c.closing || !c.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _contextMenu.hide();
      });
    }
    if (!c.visible) return const SizedBox.shrink();
    final g = PomoLayout(c.effectiveScale);
    final f = ref.watch(pomoFocusProvider);
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final seconds = (f.remaining?.inSeconds ?? 0).clamp(0, 864000);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    Widget satellite(
      Rect rect,
      IconData icon,
      String label,
      Future<void> Function()? action,
    ) => Positioned.fromRect(
      rect: rect,
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(
          tooltip: label,
          onPressed: action == null || c.busy || c.closing
              ? null
              : () => unawaited(c.command(action)),
          style: ButtonStyle(
            shape: const WidgetStatePropertyAll(CircleBorder()),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? colors.onSurface.withValues(alpha: .38)
                  : states.any(
                      {WidgetState.hovered, WidgetState.pressed}.contains,
                    )
                  ? colors.primary
                  : colors.onSurface,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(color: colors.primary, width: 2)
                  : BorderSide.none,
            ),
          ),
          icon: Icon(icon, size: g.iconSize),
        ),
      ),
    );
    final host = c.host as PomoWindowHost;
    return MouseRegion(
      onEnter: (_) => host.pointerOver(true),
      onExit: (_) => host.pointerOver(false),
      child: Listener(
        onPointerDown: (_) => host.pointerDown(true),
        onPointerUp: (_) => host.pointerDown(false),
        onPointerCancel: (_) => host.pointerDown(false),
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  _contextMenu.hide();
                  unawaited(c.collapse());
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: g.pet,
                      child: Semantics(
                        button: true,
                        label: l.pomoInteract,
                        child: AppContextMenuRegion(
                          controller: _contextMenu,
                          enableLongPress: false,
                          items: [
                            ShadContextMenuItem(
                              key: _openAppItem,
                              height: 44,
                              enabled: !c.busy && !c.closing,
                              leading: const Icon(
                                LucideIcons.appWindow,
                                size: 16,
                              ),
                              onPressed: () => unawaited(
                                c.command(
                                  ref.read(pomoActionsProvider).openApp,
                                ),
                              ),
                              child: Text(l.pomoOpenApp),
                            ),
                            Builder(
                              builder: (context) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _syncContextMenuBounds(),
                                );
                                return ShadContextMenuItem(
                                  key: _hideItem,
                                  height: 44,
                                  enabled: !c.closing,
                                  leading: const Icon(LucideIcons.x, size: 16),
                                  onPressed: () => unawaited(c.hideManually()),
                                  child: Text(l.pomoHide),
                                );
                              },
                            ),
                          ],
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              unawaited(MultiViewDesktop.of(context).focus());
                              unawaited(c.tap());
                            },
                            onPanStart: (details) {
                              if (host.isLinux) {
                                unawaited(c.perform(host.beginDrag));
                              } else {
                                unawaited(
                                  c.perform(
                                    () => MultiViewDesktop.of(
                                      context,
                                    ).startDragging(),
                                  ),
                                );
                              }
                            },
                            onPanEnd: (_) => unawaited(c.perform(host.endDrag)),
                            onPanCancel: () =>
                                unawaited(c.perform(host.endDrag)),
                            child: FocusableActionDetector(
                              actions: {
                                ActivateIntent: CallbackAction<ActivateIntent>(
                                  onInvoke: (_) {
                                    unawaited(c.tap());
                                    return null;
                                  },
                                ),
                              },
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (f.hasRun)
                                    Positioned.fill(
                                      child: Padding(
                                        padding: EdgeInsets.all(3 * g.scale),
                                        child: CircularProgressIndicator(
                                          value: f.fraction,
                                          strokeWidth: 2 * g.scale,
                                          color: colors.primary,
                                          backgroundColor:
                                              colors.outlineVariant,
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: EdgeInsets.all(8 * g.scale),
                                    child: PomoModel(
                                      emotion: c.emotion,
                                      animated: c.animated,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (c.prefs.showTimer)
                      Positioned.fromRect(
                        rect: g.capsule,
                        child: Material(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(
                            g.capsule.height / 2,
                          ),
                          elevation: 2,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              g.capsule.height / 2,
                            ),
                            onTap: () => unawaited(
                              f.hasRun
                                  ? c.tap(react: false)
                                  : c.command(() => pomoToggleFocus(ref)),
                            ),
                            child: Center(
                              child: Text(
                                f.hasRun ? time : l.startFocus,
                                semanticsLabel: f.hasRun ? time : l.startFocus,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontFamily: f.hasRun ? 'GeistMono' : null,
                                      fontSize: g.timerFontSize,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (c.menu) ...[
                      satellite(
                        g.add,
                        LucideIcons.plus,
                        l.pomoQuickAdd,
                        () => ref.read(pomoActionsProvider).quickAdd(),
                      ),
                      satellite(
                        g.toggle,
                        f.paused || f.ready || !f.hasRun
                            ? LucideIcons.play
                            : LucideIcons.pause,
                        !f.hasRun
                            ? l.startFocus
                            : f.paused
                            ? l.resume
                            : f.ready
                            ? l.startFocus
                            : l.pause,
                        !f.hasRun || f.canToggle
                            ? () => pomoToggleFocus(ref)
                            : null,
                      ),
                      satellite(
                        g.complete,
                        LucideIcons.check,
                        l.completeInterval,
                        f.canComplete ? () => pomoCompleteInterval(ref) : null,
                      ),
                      satellite(
                        g.settings,
                        LucideIcons.settings,
                        l.pomoSettings,
                        c.openSettings,
                      ),
                      satellite(
                        g.hide,
                        LucideIcons.x,
                        l.pomoHide,
                        c.hideManually,
                      ),
                    ],
                    if (c.error != null)
                      Positioned.fromRect(
                        rect: g.capsule,
                        child: Material(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(
                            g.capsule.height / 2,
                          ),
                          child: Tooltip(
                            message: l.pomoError,
                            child: Icon(
                              Icons.error_outline,
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPanel extends ConsumerStatefulWidget {
  const _SettingsPanel();
  @override
  ConsumerState<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<_SettingsPanel>
    with WindowListener {
  void _close() => unawaited(ref.read(pomoControllerProvider).closeSettings());
  @override
  void onWindowFocus() {
    // The panel is reused after hiding. Autofocus only runs on first mount;
    // restore this window's scope when a different view last owned keyboard focus.
    FocusScope.of(context).requestFocus();
  }

  @override
  void onWindowClose() => _close();
  @override
  void onWindowBlur() => _close();
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(pomoControllerProvider);
    final l = context.l10n;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _close();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.pomoSettings,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: l.commonClose,
                            onPressed: _close,
                            icon: const Icon(LucideIcons.x, size: 20),
                          ),
                        ],
                      ),
                      const PomoScaleControl(),
                      const PomoTimerControl(),
                      if (c.error != null)
                        Text(
                          l.pomoError,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
