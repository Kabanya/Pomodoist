// ignore_for_file: deprecated_member_use

import 'package:pomodoist/ui/core/widgets/compact_task_button_location.dart';

import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pomodoist/ui/core/widgets/app_bottom_navigation.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/settings/view_models/bottom_navigation_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/ui/productivity/widgets/achievement_announcements.dart';
import 'package:pomodoist/ui/focus/widgets/focus_completion_celebration.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/collaboration/widgets/shared_project_badge.dart';
import 'package:pomodoist/domain/use_cases/tasks/project_list_data.dart';
import 'package:pomodoist/ui/tasks/widgets/create_project_dialog.dart';
import 'package:pomodoist/ui/tasks/widgets/project_context_menu.dart';
import 'package:pomodoist/ui/tasks/widgets/project_tree_controls.dart';
import 'package:pomodoist/ui/tasks/widgets/project_icon.dart';
import 'package:pomodoist/ui/tasks/widgets/task_search_palette.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart';
export 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart'
    show showQuickAddDialog;
import 'package:pomodoist/ui/tasks/widgets/voice_panel_clearance.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart'
    show voiceQuickAddActiveOf;
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/settings/app_shortcut.dart';
import 'package:pomodoist/ui/core/view_models/shell_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'package:pomodoist/ui/core/themes/theme_background.dart';
import 'package:pomodoist/ui/core/themes/macos_glass.dart';
import 'package:pomodoist/ui/core/widgets/mini_focus_player.dart';
import 'package:pomodoist/ui/core/widgets/task_details_host.dart';

const double _wideLayoutBreakpoint = 820;
const double _wideSidebarDefaultWidth = 280;
const double _wideSidebarMinWidth = 220;
const double _wideSidebarMaxWidth = 380;
const double _wideSidebarCollapseThreshold = 180;
const double _wideSidebarResizeHandleWidth = 12;
const double _wideSidebarEdgeHandleWidth = 16;
const double _shellTopBarHeight = 52;
const Duration _wideSidebarAnimationDuration = AppMotion.panel;
const Curve _wideSidebarAnimationCurve = Curves.easeOutCubic;

class AdaptiveShell extends ConsumerStatefulWidget {
  const AdaptiveShell({
    required this.location,
    required this.child,
    this.taskId,
    super.key,
  });

  final String location;
  final String? taskId;
  final Widget child;

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _addTaskButtonKey = GlobalKey();
  final _backgroundLink = LayerLink();
  Alignment _addTaskCorner = Alignment.bottomRight;
  Offset? _addTaskDrag;

  bool _wideSidebarVisible = true;
  bool _wideSidebarMounted = true;
  bool _wideSidebarDragging = false;
  bool _wideSidebarRevealingFromEdge = false;
  double _wideSidebarWidth = _wideSidebarDefaultWidth;
  double _lastExpandedSidebarWidth = _wideSidebarDefaultWidth;
  bool _quickAddShortcutDialogOpen = false;
  bool _searchPaletteOpen = false;
  int? _rawHandledPhysicalKeyId;
  late final ShellAppMenu? _appMenuController;

  Offset? _visibleAddTaskPosition() {
    // A GlobalKey keeps pointing at a deactivated element until the frame is
    // finalized, so only dereference active elements: crossing the wide/compact
    // breakpoint reparents both the Scaffold and the Add-task button, and
    // findRenderObject() asserts on an element from the previous layout.
    final button = _activeRenderObjectOf(_addTaskButtonKey);
    final scaffold = _activeRenderObjectOf(_scaffoldKey);
    if (button is! RenderBox || scaffold is! RenderBox || !button.hasSize) {
      return null;
    }
    return button.localToGlobal(Offset.zero, ancestor: scaffold);
  }

  RenderObject? _activeRenderObjectOf(GlobalKey key) {
    final element = key.currentContext as Element?;
    return element != null && element.debugIsActive
        ? element.findRenderObject()
        : null;
  }

  @override
  void initState() {
    super.initState();
    _appMenuController = createShellAppMenu(
      keyboard: ref.read(shellKeyboardViewModelProvider),
      onSelected: _runMenuShortcut,
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    RawKeyboard.instance.addListener(_handleRawKeyEvent);
  }

  void _runMenuShortcut(String name) {
    for (final command in AppShortcutCommand.values) {
      if (command.name == name) {
        _runShortcut(command);
        return;
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    RawKeyboard.instance.removeListener(_handleRawKeyEvent);
    _appMenuController?.dispose();
    super.dispose();
  }

  void _handleRawKeyEvent(RawKeyEvent event) {
    if (event is RawKeyUpEvent) {
      if (_rawHandledPhysicalKeyId == event.physicalKey.usbHidUsage) {
        _rawHandledPhysicalKeyId = null;
      }
      return;
    }
    if (event is! RawKeyDownEvent ||
        event.repeat ||
        widget.location == '/settings/shortcuts') {
      return;
    }
    final keyboard = ref.read(shellKeyboardViewModelProvider);
    if (keyboard.matchesZoomRaw(event)) {
      return;
    }
    for (final entry in keyboard.shortcuts.entries) {
      if (entry.value.matchesRawEvent(event)) {
        _rawHandledPhysicalKeyId = event.physicalKey.usbHidUsage;
        _runShortcut(entry.key);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = ref.watch(shellKeyboardViewModelProvider);
    final menuController = _appMenuController;
    if (menuController != null) {
      unawaited(
        menuController.sync(
          locale: context.l10n.localeName,
          labels: {
            for (final command in AppShortcutCommand.values)
              command: appShortcutLabel(context.l10n, command),
          },
          keyboard: keyboard,
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    // Details reached through the `/task/:id` route fill the viewport just like
    // the query-parameter selection, so both hide the shell chrome below 820 px.
    final compactTaskDetailsOpen =
        !wide &&
        (widget.taskId != null || widget.location.startsWith('/task/'));
    final focusLocation = _isFocusLocation(widget.location);
    final navigation =
        ref.watch(bottomNavigationProvider).value ??
        BottomNavigationPreferences();
    final hasTodayFocusStrip =
        widget.location == '/today' &&
        ref.watch(shellTodayFocusStripVisibleProvider);
    final showMiniFocusPlayer =
        !focusLocation && widget.location != '/kanban' && !hasTodayFocusStrip;
    final colors = context.appColors;
    final backgrounds = ref.watch(
      appThemeSettingsProvider.select(
        (settings) => settings.activeTheme.backgrounds,
      ),
    );
    final brightness = Theme.of(context).brightness;
    final glass =
        backgrounds.type == ThemeBackgroundType.macosGlass &&
        macosGlassReady(context, ref);
    final content = Column(
      children: [
        const AchievementAnnouncementBridge(),
        if (!compactTaskDetailsOpen)
          _ShellTopBar(
            location: widget.location,
            onMenuPressed: _toggleSidebar,
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaQuery.removePadding(
                context: context,
                // Fullscreen details own their SafeArea when the header is hidden.
                removeTop: !compactTaskDetailsOpen,
                removeBottom: !wide,
                child: TaskDetailsHost(
                  taskId: widget.taskId,
                  child: widget.child,
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AchievementAnnouncementSlot(
                  presentation: AchievementPresentation.globalBanner,
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AchievementAnnouncementSlot(
                  presentation: AchievementPresentation.bottomPlaque,
                ),
              ),
            ],
          ),
        ),
        if (wide && showMiniFocusPlayer)
          const VoicePanelBottomClearance(child: MiniFocusPlayer()),
      ],
    );

    late final Widget scaffold;
    if (wide) {
      scaffold = Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        body: ThemeBackgroundPreview(
          glassDim: glass ? 0 : null,
          image: backgrounds.mode == ThemeBackgroundMode.wholeApp
              ? backgrounds
                    .resolve(ThemeBackgroundZone.main, brightness)
                    .copyWith(dim: 0)
              : ThemeBackgroundImage.empty(brightness),
          color: colors.canvas,
          child: Stack(
            children: [
              Row(
                children: [
                  _buildWideSidebar(context),
                  Expanded(
                    child: ThemeBackground(
                      zone: ThemeBackgroundZone.main,
                      sharedWholeApp: true,
                      child: content,
                    ),
                  ),
                ],
              ),
              if ((!_wideSidebarVisible && !_wideSidebarMounted) ||
                  _wideSidebarRevealingFromEdge)
                _buildWideSidebarEdgeHandle(),
            ],
          ),
        ),
      );
    } else {
      scaffold = ValueListenableBuilder<double>(
        valueListenable: voicePanelBottomClearanceOf(context),
        builder: (context, clearance, _) {
          final location = CompactTaskButtonLocation(
            corner: _addTaskCorner,
            dragPosition: _addTaskDrag,
            bottomClearance: compactTaskDetailsOpen ? 0 : clearance,
          );
          void finishDrag([DragEndDetails? details]) {
            setState(() {
              _addTaskCorner = location.nearestCorner(
                details?.velocity.pixelsPerSecond ?? Offset.zero,
              );
              _addTaskDrag = null;
            });
          }

          return LayoutBuilder(
            builder: (context, constraints) => CompositedTransformTarget(
              link: _backgroundLink,
              child: ThemeBackground(
                zone: ThemeBackgroundZone.main,
                child: Scaffold(
                  key: _scaffoldKey,
                  backgroundColor: Colors.transparent,
                  drawer: Drawer(
                    width: _wideSidebarDefaultWidth,
                    backgroundColor: glass
                        ? Colors.transparent
                        : colors.surface,
                    shape: const RoundedRectangleBorder(),
                    child: ThemeBackground(
                      zone: ThemeBackgroundZone.sidebar,
                      blurBehind: true,
                      wholeAppViewport: (
                        link: _backgroundLink,
                        size: constraints.biggest,
                      ),
                      child: _TodoistSidebar(
                        location: widget.location,
                        width: _wideSidebarDefaultWidth,
                        onDestinationSelected: _goFromDrawer,
                      ),
                    ),
                  ),
                  body: content,
                  floatingActionButton: ValueListenableBuilder<bool>(
                    valueListenable: voiceQuickAddActiveOf(context),
                    builder: (context, voiceActive, _) =>
                        voiceActive || widget.location == '/calendar'
                        ? const SizedBox.shrink()
                        : SizedBox.square(
                            key: _addTaskButtonKey,
                            dimension: 52,
                            child: GestureDetector(
                              excludeFromSemantics: true,
                              onPanStart: (_) => setState(
                                () => _addTaskDrag =
                                    _visibleAddTaskPosition() ??
                                    location.position,
                              ),
                              onPanUpdate: (details) => setState(
                                () => _addTaskDrag = location.clamp(
                                  (_addTaskDrag ?? location.position) +
                                      details.delta,
                                ),
                              ),
                              onPanEnd: finishDrag,
                              onPanCancel: finishDrag,
                              child: FloatingActionButton(
                                key: const Key('compact-add-task'),
                                heroTag: null,
                                tooltip: context.l10n.addTask,
                                backgroundColor: colors.accentFill,
                                foregroundColor: colors.onAccent,
                                focusColor: colors.onAccent.withValues(
                                  alpha: 0.24,
                                ),
                                elevation: 3,
                                shape: const CircleBorder(),
                                onPressed: () => showQuickAddDialog(context),
                                child: const Icon(LucideIcons.plus, size: 24),
                              ),
                            ),
                          ),
                  ),
                  floatingActionButtonLocation: location,
                  floatingActionButtonAnimator: CompactTaskButtonAnimator(
                    from: _visibleAddTaskPosition(),
                    immediate:
                        _addTaskDrag != null ||
                        MediaQuery.disableAnimationsOf(context),
                  ),
                  bottomNavigationBar: compactTaskDetailsOpen
                      ? null
                      : VoicePanelBottomClearance(
                          child: _ShellBottomChrome(
                            preferences: navigation,
                            selected: navigation.selectedFor(widget.location),
                            showMiniFocusPlayer: showMiniFocusPlayer,
                            onDestinationSelected: (destination) =>
                                context.go(destination.path),
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [scaffold, const FocusRunCompletionCelebrationSlot()],
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || widget.location == '/settings/shortcuts') {
      return false;
    }

    if (_rawHandledPhysicalKeyId == event.physicalKey.usbHidUsage) {
      return true;
    }

    final hardwareKeyboard = HardwareKeyboard.instance;
    final keyboard = ref.read(shellKeyboardViewModelProvider);
    if (keyboard.matchesZoom(event, hardwareKeyboard)) {
      return false;
    }
    AppShortcutCommand? command;
    for (final entry in keyboard.shortcuts.entries) {
      if (entry.value.matches(event, hardwareKeyboard)) {
        command = entry.key;
        break;
      }
    }
    if (command == null) {
      return false;
    }

    _runShortcut(command);
    return true;
  }

  void _runShortcut(AppShortcutCommand command) {
    switch (command) {
      case AppShortcutCommand.toggleSidebar:
        _toggleSidebar();
      case AppShortcutCommand.quickAdd:
        _openQuickAddFromShortcut();
      case AppShortcutCommand.browse:
        _goFromShortcut('/browse');
      case AppShortcutCommand.search:
        _goFromShortcut('/search');
      case AppShortcutCommand.today:
        _goFromShortcut('/today');
      case AppShortcutCommand.upcoming:
        _goFromShortcut('/upcoming');
      case AppShortcutCommand.focus:
        _goFromShortcut('/focus');
      case AppShortcutCommand.inbox:
        _goFromShortcut('/inbox');
      case AppShortcutCommand.priorityMatrix:
        _goFromShortcut('/priority-matrix');
      case AppShortcutCommand.calendar:
        _goFromShortcut('/calendar');
      case AppShortcutCommand.timeline:
        _goFromShortcut('/timeline');
      case AppShortcutCommand.kanban:
        _goFromShortcut('/kanban');
      case AppShortcutCommand.reports:
        _goFromShortcut('/reports');
      case AppShortcutCommand.settings:
        _goFromShortcut('/settings');
    }
  }

  void _openQuickAddFromShortcut() {
    if (_quickAddShortcutDialogOpen) return;
    _quickAddShortcutDialogOpen = true;
    unawaited(
      showQuickAddDialog(
        context,
      ).whenComplete(() => _quickAddShortcutDialogOpen = false),
    );
  }

  void _goFromShortcut(String path) {
    _scaffoldKey.currentState?.closeDrawer();
    _go(path);
  }

  void _toggleSidebar() {
    final scaffold = _scaffoldKey.currentState;
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    if (wide) {
      if (scaffold?.isDrawerOpen ?? false) {
        scaffold?.closeDrawer();
      }
      if (_wideSidebarVisible) {
        _collapseWideSidebar();
      } else {
        _restoreWideSidebar();
      }
      return;
    }

    if (scaffold == null) {
      return;
    }
    if (scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    } else {
      scaffold.openDrawer();
    }
  }

  void _go(String path) {
    if (path == '/search' &&
        MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint) {
      if (_searchPaletteOpen) return;
      _searchPaletteOpen = true;
      unawaited(
        showTaskSearchPalette(
          context,
          ref,
        ).whenComplete(() => _searchPaletteOpen = false),
      );
      return;
    }
    context.go(path);
  }

  void _goFromDrawer(String path) {
    _scaffoldKey.currentState?.closeDrawer();
    _go(path);
  }

  Widget _buildWideSidebar(BuildContext context) {
    if (!_wideSidebarMounted && !_wideSidebarVisible) {
      return const SizedBox.shrink();
    }

    final maxWidth = _maxWideSidebarWidth(context);
    final targetWidth = _wideSidebarVisible
        ? _wideSidebarWidth.clamp(0.0, maxWidth).toDouble()
        : 0.0;
    final preferredContentWidth =
        _wideSidebarVisible && targetWidth >= _wideSidebarMinWidth
        ? targetWidth
        : null;
    final contentWidth = _stableWideSidebarWidth(
      context,
      preferredContentWidth,
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetWidth),
      duration: _wideSidebarDragging
          ? Duration.zero
          : AppMotion.duration(context, _wideSidebarAnimationDuration),
      curve: _wideSidebarAnimationCurve,
      onEnd: () {
        if (!mounted || _wideSidebarVisible || !_wideSidebarMounted) {
          return;
        }
        setState(() => _wideSidebarMounted = false);
      },
      builder: (context, width, child) {
        final progress = (width / contentWidth).clamp(0.0, 1.0).toDouble();
        final opacity = Curves.easeOut.transform(progress);

        return SizedBox(
          key: const Key('wide-sidebar-frame'),
          width: width,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  bottom: 0,
                  width: contentWidth,
                  child: Transform.translate(
                    offset: Offset(-20 * (1 - progress), 0),
                    child: Opacity(
                      opacity: opacity,
                      child: RepaintBoundary(
                        child: ThemeBackground(
                          zone: ThemeBackgroundZone.sidebar,
                          sharedWholeApp: true,
                          child: _TodoistSidebar(
                            location: widget.location,
                            width: contentWidth,
                            onDestinationSelected: _go,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_wideSidebarVisible) _buildWideSidebarResizeHandle(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideSidebarResizeHandle() {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: _wideSidebarResizeHandleWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          key: const Key('wide-sidebar-resize-handle'),
          behavior: HitTestBehavior.opaque,
          onPanStart: _startWideSidebarResize,
          onPanUpdate: _updateWideSidebarResize,
          onPanEnd: (_) => _settleWideSidebarDrag(),
          onPanCancel: _settleWideSidebarDrag,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildWideSidebarEdgeHandle() {
    return Positioned(
      top: 0,
      left: 0,
      bottom: 0,
      width: _wideSidebarEdgeHandleWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          key: const Key('wide-sidebar-edge-reveal-handle'),
          behavior: HitTestBehavior.opaque,
          onPanStart: _startWideSidebarReveal,
          onPanUpdate: _updateWideSidebarResize,
          onPanEnd: (_) => _settleWideSidebarDrag(),
          onPanCancel: _settleWideSidebarDrag,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  void _startWideSidebarResize(DragStartDetails _) {
    setState(() {
      _wideSidebarDragging = true;
      _wideSidebarRevealingFromEdge = false;
      _wideSidebarMounted = true;
      _wideSidebarVisible = true;
    });
  }

  void _startWideSidebarReveal(DragStartDetails _) {
    setState(() {
      _wideSidebarDragging = true;
      _wideSidebarRevealingFromEdge = true;
      _wideSidebarMounted = true;
      _wideSidebarVisible = true;
      _wideSidebarWidth = 0;
    });
  }

  void _updateWideSidebarResize(DragUpdateDetails details) {
    final maxWidth = _maxWideSidebarWidth(context);
    setState(() {
      _wideSidebarWidth = (_wideSidebarWidth + details.delta.dx)
          .clamp(0.0, maxWidth)
          .toDouble();
    });
  }

  void _settleWideSidebarDrag() {
    if (_wideSidebarWidth < _wideSidebarCollapseThreshold) {
      _collapseWideSidebar();
      return;
    }

    final width = _stableWideSidebarWidth(context, _wideSidebarWidth);
    setState(() {
      _wideSidebarDragging = false;
      _wideSidebarRevealingFromEdge = false;
      _wideSidebarMounted = true;
      _wideSidebarVisible = true;
      _wideSidebarWidth = width;
      _lastExpandedSidebarWidth = width;
    });
  }

  void _collapseWideSidebar() {
    setState(() {
      _wideSidebarDragging = false;
      _wideSidebarRevealingFromEdge = false;
      _wideSidebarMounted = true;
      _wideSidebarVisible = false;
    });
  }

  void _restoreWideSidebar() {
    final width = _stableWideSidebarWidth(context, _lastExpandedSidebarWidth);
    final wasUnmounted = !_wideSidebarMounted;
    setState(() {
      _wideSidebarDragging = false;
      _wideSidebarRevealingFromEdge = false;
      _wideSidebarMounted = true;
      _wideSidebarVisible = true;
      _wideSidebarWidth = wasUnmounted ? 0 : width;
      _lastExpandedSidebarWidth = width;
    });

    if (!wasUnmounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_wideSidebarVisible || _wideSidebarDragging) {
        return;
      }

      setState(() {
        _wideSidebarWidth = _stableWideSidebarWidth(
          context,
          _lastExpandedSidebarWidth,
        );
      });
    });
  }

  double _stableWideSidebarWidth(BuildContext context, [double? preferred]) {
    final maxWidth = _maxWideSidebarWidth(context);
    final minWidth = math.min(_wideSidebarMinWidth, maxWidth);
    return (preferred ?? _lastExpandedSidebarWidth)
        .clamp(minWidth, maxWidth)
        .toDouble();
  }

  double _maxWideSidebarWidth(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    return math.max(0, math.min(_wideSidebarMaxWidth, viewportWidth));
  }
}

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({required this.location, required this.onMenuPressed});

  final String location;
  final VoidCallback onMenuPressed;

  @override
  Widget build(BuildContext context) {
    final compactKanban =
        location == '/kanban' &&
        MediaQuery.sizeOf(context).width < _wideLayoutBreakpoint;
    final content = SizedBox(
      height: _shellTopBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _ShellMenuButton(onPressed: onMenuPressed),
          ),
          if (compactKanban)
            Text(
              context.l10n.kanbanTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          if (compactKanban)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('kanban-shell-add'),
                    tooltip: context.l10n.addTask,
                    onPressed: () => showQuickAddDialog(context),
                    icon: const Icon(LucideIcons.circlePlus),
                    color: context.appColors.accent,
                  ),
                  IconButton(
                    key: const Key('kanban-shell-focus'),
                    tooltip: context.l10n.navFocus,
                    onPressed: () => context.go('/focus'),
                    icon: const Icon(LucideIcons.timer),
                    color: context.appColors.accent,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
        ],
      ),
    );
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: compactKanban
              ? Border(bottom: BorderSide(color: context.appColors.border))
              : null,
        ),
        child: content,
      ),
    );
  }
}

class _ShellMenuButton extends StatelessWidget {
  const _ShellMenuButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('shell-menu-button'),
      tooltip: context.l10n.menuTooltip,
      onPressed: onPressed,
      icon: const Icon(LucideIcons.panelLeft),
    );
  }
}

class _ShellBottomChrome extends StatelessWidget {
  const _ShellBottomChrome({
    required this.preferences,
    required this.selected,
    required this.showMiniFocusPlayer,
    required this.onDestinationSelected,
  });

  final BottomNavigationPreferences preferences;
  final BottomNavigationDestination? selected;
  final bool showMiniFocusPlayer;
  final ValueChanged<BottomNavigationDestination> onDestinationSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMiniFocusPlayer) const MiniFocusPlayer(floating: true),
        AppBottomNavigation(
          key: const Key('mobile-bottom-navigation'),
          preferences: preferences,
          selected: selected,
          onSelected: onDestinationSelected,
        ),
      ],
    ),
  );
}

bool _isFocusLocation(String path) =>
    path == '/focus' || path.startsWith('/focus/');

class _TodoistSidebar extends ConsumerStatefulWidget {
  const _TodoistSidebar({
    required this.location,
    required this.width,
    required this.onDestinationSelected,
  });

  final String location;
  final double width;
  final ValueChanged<String> onDestinationSelected;

  @override
  ConsumerState<_TodoistSidebar> createState() => _TodoistSidebarState();
}

class _TodoistSidebarState extends ConsumerState<_TodoistSidebar> {
  bool _projectsExpanded = true;
  final _projectTree = ProjectTreeController();
  void _treeChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _projectTree.addListener(_treeChanged);
  }

  @override
  void dispose() {
    _projectTree.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final colors = context.appColors;
    final destinations = {
      for (final destination in _desktopDestinations(context))
        destination.path: destination,
    };
    final pinFooter = MediaQuery.sizeOf(context).height >= 560;
    final keyboard = ref.watch(shellKeyboardViewModelProvider);
    final sidebar = ref.watch(shellSidebarViewModelProvider);
    final searchShortcut = keyboard.shortcuts[AppShortcutCommand.search]
        ?.labelFor(keyboard.platform);
    final displayName = _displayName(context, sidebar.displayName);
    final projects = sidebar.projects;
    final projectTaskCounts = sidebar.projectTaskCounts;
    final projectCount = projects.value
        ?.where(
          (project) => project.id != inboxProjectId && !project.isArchived,
        )
        .length;
    final counts = <String, int>{
      '/inbox': sidebar.inboxCount,
      '/today': sidebar.todayCount,
      '/upcoming': sidebar.upcomingCount,
    };

    Widget destinationTile(String path) => _SidebarDestinationTile(
      destination: destinations[path]!,
      selected: _isSelected(widget.location, path),
      count: counts[path],
      shortcut: path == '/search' ? searchShortcut : null,
      onTap: () => widget.onDestinationSelected(path),
    );
    Widget groupLabel(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
      child: Text(
        title,
        style: textTheme.labelSmall?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Divider(height: 1, color: colors.border),
        const SizedBox(height: 8),
        for (final path in ['/browse', '/reports', '/settings'])
          destinationTile(path),
      ],
    );

    return SafeArea(
      right: false,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.border)),
        ),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SidebarProfileHeader(
                  displayName: displayName,
                  onProfileTap: () =>
                      widget.onDestinationSelected('/settings?section=account'),
                ),
                const SizedBox(height: 16),
                destinationTile('/search'),
                const SizedBox(height: 4),
                _AddTaskTile(onTap: () => showQuickAddDialog(context)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      groupLabel(l10n.sidebarDaily),
                      for (final path in [
                        '/inbox',
                        '/today',
                        '/upcoming',
                        '/focus',
                      ])
                        destinationTile(path),
                      groupLabel(l10n.sidebarViews),
                      for (final path in [
                        '/calendar',
                        '/timeline',
                        '/kanban',
                        '/priority-matrix',
                      ])
                        destinationTile(path),
                      const SizedBox(height: 20),
                      _ProjectsHeader(
                        count: projectCount,
                        expanded: _projectsExpanded,
                        selected: widget.location == '/projects',
                        onTitleTap: () =>
                            widget.onDestinationSelected('/projects'),
                        onToggle: () => setState(
                          () => _projectsExpanded = !_projectsExpanded,
                        ),
                        onAdd: () => showCreateProjectDialog(context),
                      ),
                      if (_projectsExpanded) ...[
                        const SizedBox(height: 6),
                        projects.when(
                          data: (items) {
                            final visibleProjects = items
                                .where(
                                  (project) =>
                                      project.id != inboxProjectId &&
                                      !project.isArchived,
                                )
                                .toList();
                            if (visibleProjects.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Text(
                                  l10n.noProjects,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colors.mutedText,
                                  ),
                                ),
                              );
                            }
                            final rows = projectRows(
                              visibleProjects,
                              collapsedIds: _projectTree.collapsedIds,
                            );
                            return ProjectTreeScope(
                              controller: _projectTree,
                              child: Column(
                                children: [
                                  const ProjectTreeRootTarget(),
                                  for (final row in rows)
                                    ProjectTreeRow(
                                      key: ValueKey(
                                        'sidebar-tree-${row.project.id}',
                                      ),
                                      row: row,
                                      child: _SidebarProjectTile(
                                        project: row.project,
                                        count:
                                            projectTaskCounts[row.project.id] ??
                                            0,
                                        selected:
                                            widget.location ==
                                            '/project/${row.project.id}',
                                        onTap: () =>
                                            widget.onDestinationSelected(
                                              '/project/${row.project.id}',
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                          error: (error, stackTrace) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Text(
                              l10n.projectsUnavailableShort,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.mutedText,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!pinFooter) footer,
                    ],
                  ),
                ),
                if (pinFooter) footer,
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isSelected(String location, String path) {
    return location == path || location.startsWith('$path/');
  }

  String _displayName(BuildContext context, String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return context.l10n.localUser;
    }
    return trimmed;
  }
}

class _SidebarProfileHeader extends StatelessWidget {
  const _SidebarProfileHeader({
    required this.displayName,
    required this.onProfileTap,
  });

  final String displayName;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final initial = displayName.trim().isEmpty
        ? '?'
        : displayName.trim().substring(0, 1).toUpperCase();
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surfaceHover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    initial,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.chevronDown,
                        color: colors.secondaryText,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTaskTile extends StatelessWidget {
  const _AddTaskTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ShadButton.ghost(
      key: const Key('sidebar-add-task'),
      onPressed: onTap,
      height: 0,
      expands: true,
      mainAxisAlignment: MainAxisAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      foregroundColor: colors.accent,
      hoverForegroundColor: colors.accent,
      leading: const Icon(LucideIcons.circlePlus, size: 20),
      gap: 10,
      child: Text(
        context.l10n.addTask,
        textAlign: TextAlign.start,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProjectsHeader extends StatelessWidget {
  const _ProjectsHeader({
    required this.count,
    required this.expanded,
    required this.selected,
    required this.onTitleTap,
    required this.onToggle,
    required this.onAdd,
  });

  final int? count;
  final bool expanded;
  final bool selected;
  final VoidCallback onTitleTap;
  final VoidCallback onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.accent : colors.secondaryText;
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: selected ? colors.accentTint : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: const Key('sidebar-projects-link'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTitleTap,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 4, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.navProjects,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '$count',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: foreground,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        IconButton(
          key: const Key('sidebar-add-project'),
          tooltip: l10n.addProject,
          onPressed: onAdd,
          icon: const Icon(LucideIcons.plus),
          iconSize: 22,
          style: IconButton.styleFrom(
            foregroundColor: colors.secondaryText,
            fixedSize: const Size(30, 34),
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        IconButton(
          key: const Key('sidebar-projects-toggle'),
          tooltip: expanded ? l10n.collapseProjects : l10n.expandProjects,
          onPressed: onToggle,
          icon: Icon(
            expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
          ),
          iconSize: 24,
          style: IconButton.styleFrom(
            foregroundColor: colors.secondaryText,
            fixedSize: const Size(30, 34),
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

class _SidebarDestinationTile extends StatelessWidget {
  const _SidebarDestinationTile({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.count,
    this.shortcut,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.accent : colors.primaryText;
    final metadataColor = selected ? colors.accent : colors.mutedText;
    final showCount = count != null && count! > 0;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      hint: shortcut,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('sidebar-destination-${destination.path}'),
        color: selected ? colors.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: foreground,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (shortcut case final label?)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 76),
                    child: Tooltip(
                      message: label,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: metadataColor),
                      ),
                    ),
                  ),
                if (showCount)
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: metadataColor,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarProjectTile extends StatelessWidget {
  const _SidebarProjectTile({
    required this.project,
    required this.selected,
    required this.onTap,
    required this.count,
  });

  final ProjectItem project;
  final bool selected;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.accent : colors.primaryText;
    return ProjectContextMenu(
      project: project,
      child: Material(
        key: ValueKey('sidebar-project-${project.id}'),
        color: selected ? colors.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                ProjectIconView(project: project, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          project.displayName(context.l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: foreground,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SharedProjectBadge(project: project),
                    ],
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.mutedText,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<_Destination> _desktopDestinations(BuildContext context) {
  final l10n = context.l10n;
  return [
    _Destination(
      l10n.navBrowse,
      '/browse',
      LucideIcons.layoutGrid,
      LucideIcons.layoutGrid,
    ),
    _Destination(
      l10n.navSearch,
      '/search',
      LucideIcons.search,
      LucideIcons.search,
    ),
    _Destination(
      l10n.navToday,
      '/today',
      LucideIcons.calendarCheck,
      LucideIcons.calendarCheck,
    ),
    _Destination(
      l10n.navUpcoming,
      '/upcoming',
      LucideIcons.calendarDays,
      LucideIcons.calendarDays,
    ),
    _Destination(l10n.navFocus, '/focus', LucideIcons.timer, LucideIcons.timer),
    _Destination(l10n.navInbox, '/inbox', LucideIcons.inbox, LucideIcons.inbox),
    _Destination(
      l10n.navPriorityMatrix,
      '/priority-matrix',
      LucideIcons.grid2x2,
      LucideIcons.grid2x2,
    ),
    _Destination(
      l10n.navCalendar,
      '/calendar',
      LucideIcons.calendarRange,
      LucideIcons.calendarRange,
    ),
    _Destination(
      l10n.navTimeline,
      '/timeline',
      LucideIcons.chartNoAxesGantt,
      LucideIcons.chartNoAxesGantt,
    ),
    _Destination(
      l10n.navKanban,
      '/kanban',
      LucideIcons.columns3,
      LucideIcons.columns3,
    ),
    _Destination(
      l10n.navReports,
      '/reports',
      LucideIcons.chartNoAxesColumnIncreasing,
      LucideIcons.chartNoAxesColumnIncreasing,
    ),
    _Destination(
      l10n.navSettings,
      '/settings',
      LucideIcons.settings2,
      LucideIcons.settings2,
    ),
  ];
}

class _Destination {
  const _Destination(this.label, this.path, this.icon, this.selectedIcon);

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}
