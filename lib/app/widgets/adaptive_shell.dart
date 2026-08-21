// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../features/productivity/domain/achievement_models.dart';
import '../../features/productivity/presentation/achievement_announcements.dart';
import '../../features/focus/presentation/focus_completion_celebration.dart';
import '../../features/tasks/domain/project_colors.dart';
import '../../features/tasks/domain/task_models.dart';
import '../../features/tasks/presentation/widgets/create_project_dialog.dart';
import '../../features/tasks/presentation/widgets/project_color_picker.dart';
import '../../features/tasks/presentation/widgets/quick_add_bar.dart';
import '../account_providers.dart';
import '../app_l10n.dart';
import '../keyboard_shortcuts.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'mini_focus_player.dart';
import 'resizable_dialog.dart';

const double _wideLayoutBreakpoint = 820;
const double _wideSidebarDefaultWidth = 280;
const double _wideSidebarMinWidth = 220;
const double _wideSidebarMaxWidth = 380;
const double _wideSidebarCollapseThreshold = 180;
const double _wideSidebarResizeHandleWidth = 12;
const double _wideSidebarEdgeHandleWidth = 16;
const double _shellTopBarHeight = 52;
const Duration _wideSidebarAnimationDuration = Duration(milliseconds: 220);
const Curve _wideSidebarAnimationCurve = Curves.easeOutCubic;

class AdaptiveShell extends ConsumerStatefulWidget {
  const AdaptiveShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _wideSidebarVisible = true;
  bool _wideSidebarMounted = true;
  bool _wideSidebarDragging = false;
  bool _wideSidebarRevealingFromEdge = false;
  double _wideSidebarWidth = _wideSidebarDefaultWidth;
  double _lastExpandedSidebarWidth = _wideSidebarDefaultWidth;
  bool _quickAddShortcutDialogOpen = false;
  int? _rawHandledPhysicalKeyId;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    RawKeyboard.instance.addListener(_handleRawKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    RawKeyboard.instance.removeListener(_handleRawKeyEvent);
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
    for (final entry in ref.read(keyboardShortcutsProvider).entries) {
      if (entry.value.matchesRawEvent(event)) {
        _rawHandledPhysicalKeyId = event.physicalKey.usbHidUsage;
        _runShortcut(entry.key);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(keyboardShortcutsProvider);
    ref.watch(keyboardShortcutsLoadedProvider);
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    final focusLocation = _isFocusLocation(widget.location);
    final mobileDestinations = _mobileDestinations(context);
    final selected = _selectedMobileIndex(widget.location, mobileDestinations);
    final showMiniFocusPlayer = !focusLocation && widget.location != '/kanban';
    final colors = context.appColors;
    final content = Column(
      children: [
        const AchievementAnnouncementBridge(),
        _ShellTopBar(location: widget.location, onMenuPressed: _toggleSidebar),
        const AchievementAnnouncementSlot(
          presentation: AchievementPresentation.globalBanner,
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: !wide,
            child: widget.child,
          ),
        ),
        if (wide) ...[
          const AchievementAnnouncementSlot(
            presentation: AchievementPresentation.bottomPlaque,
          ),
          if (showMiniFocusPlayer) const MiniFocusPlayer(),
        ],
      ],
    );

    late final Widget scaffold;
    if (wide) {
      scaffold = Scaffold(
        key: _scaffoldKey,
        body: Stack(
          children: [
            Row(
              children: [
                _buildWideSidebar(context),
                Expanded(child: content),
              ],
            ),
            if ((!_wideSidebarVisible && !_wideSidebarMounted) ||
                _wideSidebarRevealingFromEdge)
              _buildWideSidebarEdgeHandle(),
          ],
        ),
      );
    } else {
      scaffold = Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          width: _wideSidebarDefaultWidth,
          backgroundColor: colors.surface,
          shape: const RoundedRectangleBorder(),
          child: _TodoistSidebar(
            location: widget.location,
            width: _wideSidebarDefaultWidth,
            onDestinationSelected: _goFromDrawer,
          ),
        ),
        body: content,
        bottomNavigationBar: _ShellBottomChrome(
          selectedIndex: selected,
          showMiniFocusPlayer: showMiniFocusPlayer,
          onDestinationSelected: (index) =>
              context.go(mobileDestinations[index].path),
        ),
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

    final keyboard = HardwareKeyboard.instance;
    AppShortcutCommand? command;
    for (final entry in ref.read(keyboardShortcutsProvider).entries) {
      if (entry.value.matches(event, keyboard)) {
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
      _showSidebarQuickAddDialog(
        context,
      ).whenComplete(() => _quickAddShortcutDialogOpen = false),
    );
  }

  void _goFromShortcut(String path) {
    _scaffoldKey.currentState?.closeDrawer();
    context.go(path);
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
    context.go(path);
  }

  void _goFromDrawer(String path) {
    _scaffoldKey.currentState?.closeDrawer();
    context.go(path);
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
          : _wideSidebarAnimationDuration,
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
                        child: _TodoistSidebar(
                          location: widget.location,
                          width: contentWidth,
                          onDestinationSelected: _go,
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

  int? _selectedMobileIndex(String path, List<_Destination> destinations) {
    if (path.startsWith('/project')) {
      return 4;
    }
    final index = destinations.indexWhere(
      (destination) => path.startsWith(destination.path),
    );
    return index < 0 ? null : index;
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
                    onPressed: () => _showSidebarQuickAddDialog(context),
                    icon: const Icon(Icons.add_circle),
                    color: context.appColors.accent,
                  ),
                  IconButton(
                    key: const Key('kanban-shell-focus'),
                    tooltip: context.l10n.navFocus,
                    onPressed: () => context.go('/focus'),
                    icon: const Icon(Icons.timer_outlined),
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
      icon: const Icon(Icons.menu),
    );
  }
}

class _ShellBottomChrome extends StatelessWidget {
  const _ShellBottomChrome({
    required this.selectedIndex,
    required this.showMiniFocusPlayer,
    required this.onDestinationSelected,
  });

  final int? selectedIndex;
  final bool showMiniFocusPlayer;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AchievementAnnouncementSlot(
          presentation: AchievementPresentation.bottomPlaque,
        ),
        if (showMiniFocusPlayer)
          MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: const MiniFocusPlayer(floating: true),
          ),
        _FloatingBottomNavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
        ),
      ],
    );
  }
}

bool _isFocusLocation(String path) =>
    path == '/focus' || path.startsWith('/focus/');

class _FloatingBottomNavigationBar extends StatelessWidget {
  const _FloatingBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int? selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = context.appColors;
    final destinations = _mobileDestinations(context);
    return SafeArea(
      key: const Key('mobile-bottom-navigation'),
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.primaryText.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (var index = 0; index < 5; index++)
                      Expanded(
                        child: _FloatingDestinationButton(
                          destination: destinations[index],
                          selected: index == selectedIndex,
                          textTheme: textTheme,
                          onTap: () => onDestinationSelected(index),
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

class _FloatingDestinationButton extends StatelessWidget {
  const _FloatingDestinationButton({
    required this.destination,
    required this.selected,
    required this.textTheme,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final TextTheme textTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.accent : colors.secondaryText;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: foreground,
                  size: selected ? 23 : 22,
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final colors = context.appColors;
    final desktopDestinations = _desktopDestinations(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final user = ref.watch(currentUserProvider).value;
    final account = ref.watch(accountClientProvider);
    final accountProfile = account == null
        ? null
        : ref.watch(accountOverviewProvider).value?.profile;
    final displayName = _displayName(
      context,
      accountProfile?.displayName ?? accountProfile?.email ?? user?.displayName,
    );
    final inboxCount = _taskCount(
      ref.watch(tasksByQueryProvider(const TaskQuery.inbox())),
    );
    final todayCount = _taskCount(
      ref.watch(
        tasksByQueryProvider(TaskQuery(kind: TaskQueryKind.today, now: today)),
      ),
    );
    final upcomingCount = _taskCount(
      ref.watch(
        tasksByQueryProvider(
          TaskQuery(kind: TaskQueryKind.upcoming, now: today),
        ),
      ),
    );
    final projects = ref.watch(projectsProvider);
    final projectTaskCounts = _projectTaskCounts(
      ref.watch(tasksByQueryProvider(const TaskQuery.all())).value ??
          const <TaskItem>[],
    );
    final projectCount = projects.value
        ?.where(
          (project) => project.id != inboxProjectId && !project.isArchived,
        )
        .length;
    final counts = <String, int>{
      '/inbox': inboxCount,
      '/today': todayCount,
      '/upcoming': upcomingCount,
    };

    return SafeArea(
      right: false,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(right: BorderSide(color: colors.border)),
        ),
        child: Material(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SidebarProfileHeader(
                  displayName: displayName,
                  onProfileTap: () => widget.onDestinationSelected('/settings'),
                  onFocusTap: () => widget.onDestinationSelected('/focus'),
                ),
                const SizedBox(height: 28),
                _AddTaskTile(onTap: () => _showSidebarQuickAddDialog(context)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final destination in desktopDestinations) ...[
                        _SidebarDestinationTile(
                          destination: destination,
                          selected: _isSelected(
                            widget.location,
                            destination.path,
                          ),
                          count: counts[destination.path],
                          onTap: () =>
                              widget.onDestinationSelected(destination.path),
                        ),
                        const SizedBox(height: 2),
                      ],
                      const SizedBox(height: 28),
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
                            final rows = _projectRows(visibleProjects);
                            return Column(
                              children: [
                                for (final row in rows)
                                  _SidebarProjectTile(
                                    project: row.project,
                                    depth: row.depth,
                                    count:
                                        projectTaskCounts[row.project.id] ?? 0,
                                    selected:
                                        widget.location ==
                                        '/project/${row.project.id}',
                                    onTap: () => widget.onDestinationSelected(
                                      '/project/${row.project.id}',
                                    ),
                                  ),
                              ],
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _taskCount(AsyncValue<List<TaskItem>> value) {
    return value.maybeWhen(data: (items) => items.length, orElse: () => 0);
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

class _ProjectListRow {
  const _ProjectListRow({required this.project, required this.depth});

  final ProjectItem project;
  final int depth;
}

class _ProjectTreeNode {
  _ProjectTreeNode(this.project);

  final ProjectItem project;
  final List<_ProjectTreeNode> children = [];
}

List<_ProjectListRow> _projectRows(List<ProjectItem> projects) {
  final nodes = {
    for (final project in projects) project.id: _ProjectTreeNode(project),
  };
  final roots = <_ProjectTreeNode>[];

  for (final project in projects) {
    final node = nodes[project.id]!;
    final parentId = project.parentId;
    if (parentId != null && nodes.containsKey(parentId)) {
      nodes[parentId]!.children.add(node);
    } else {
      roots.add(node);
    }
  }

  final rows = <_ProjectListRow>[];
  void visit(_ProjectTreeNode node, int depth) {
    rows.add(_ProjectListRow(project: node.project, depth: depth));
    for (final child in node.children) {
      visit(child, depth + 1);
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return rows;
}

Map<String, int> _projectTaskCounts(List<TaskItem> tasks) {
  final counts = <String, int>{};
  for (final task in tasks) {
    if (task.projectId == inboxProjectId || task.isCompleted) {
      continue;
    }
    counts.update(task.projectId, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

class _SidebarProfileHeader extends StatelessWidget {
  const _SidebarProfileHeader({
    required this.displayName,
    required this.onProfileTap,
    required this.onFocusTap,
  });

  final String displayName;
  final VoidCallback onProfileTap;
  final VoidCallback onFocusTap;

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
                    color: colors.info,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
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
                        Icons.keyboard_arrow_down,
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
        IconButton(
          tooltip: context.l10n.navFocus,
          onPressed: onFocusTap,
          icon: const Icon(Icons.timer_outlined),
          iconSize: 22,
          style: IconButton.styleFrom(
            foregroundColor: colors.accent,
            minimumSize: const Size(36, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: const Key('sidebar-add-task'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.accentFill,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.addTask,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
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
                padding: const EdgeInsets.symmetric(vertical: 10),
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
                              fontSize: 16,
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
                          color: colors.primaryText.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          l10n.projectsCountCompact(count!),
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
          icon: const Icon(Icons.add),
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
            expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
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
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

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
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontSize: 17,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (showCount)
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: metadataColor,
                      fontSize: 16,
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
    required this.depth,
    required this.count,
  });

  final ProjectItem project;
  final bool selected;
  final VoidCallback onTap;
  final int depth;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.accent : colors.primaryText;
    return Material(
      key: ValueKey('sidebar-project-${project.id}'),
      color: selected ? colors.accentTint : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 10.0 + depth * 18.0,
            right: 10,
            top: 8,
            bottom: 8,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '#',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: projectColorValue(effectiveProjectColor(project)),
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
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
    );
  }
}

class _SidebarQuickAddDialog extends StatelessWidget {
  const _SidebarQuickAddDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ResizableDialog(
      title: Text(l10n.addTask),
      initialSize: const Size(560, 260),
      minSize: const Size(320, 220),
      content: QuickAddComposer(
        onCompleted: () => Navigator.of(context).pop(),
        onCancel: () => Navigator.of(context).pop(),
      ),
      actions: const [],
    );
  }
}

Future<void> _showSidebarQuickAddDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SidebarQuickAddDialog(),
  );
}

List<_Destination> _mobileDestinations(BuildContext context) {
  final l10n = context.l10n;
  return [
    _Destination(l10n.navToday, '/today', Icons.today_outlined, Icons.today),
    _Destination(
      l10n.navUpcoming,
      '/upcoming',
      Icons.calendar_month_outlined,
      Icons.calendar_month,
    ),
    _Destination(l10n.navFocus, '/focus', Icons.timer_outlined, Icons.timer),
    _Destination(l10n.navInbox, '/inbox', Icons.inbox_outlined, Icons.inbox),
    _Destination(
      l10n.navProjects,
      '/projects',
      Icons.folder_outlined,
      Icons.folder,
    ),
  ];
}

List<_Destination> _desktopDestinations(BuildContext context) {
  final l10n = context.l10n;
  return [
    _Destination(
      l10n.navBrowse,
      '/browse',
      Icons.grid_view_outlined,
      Icons.grid_view,
    ),
    _Destination(l10n.navSearch, '/search', Icons.search, Icons.search),
    _Destination(l10n.navToday, '/today', Icons.today_outlined, Icons.today),
    _Destination(
      l10n.navUpcoming,
      '/upcoming',
      Icons.calendar_month_outlined,
      Icons.calendar_month,
    ),
    _Destination(l10n.navFocus, '/focus', Icons.timer_outlined, Icons.timer),
    _Destination(l10n.navInbox, '/inbox', Icons.inbox_outlined, Icons.inbox),
    _Destination(
      l10n.navPriorityMatrix,
      '/priority-matrix',
      Icons.dashboard_customize_outlined,
      Icons.dashboard_customize,
    ),
    _Destination(
      l10n.navTimeline,
      '/timeline',
      Icons.view_timeline_outlined,
      Icons.view_timeline,
    ),
    _Destination(
      l10n.navKanban,
      '/kanban',
      Icons.view_kanban_outlined,
      Icons.view_kanban,
    ),
    _Destination(
      l10n.navReports,
      '/reports',
      Icons.bar_chart_outlined,
      Icons.bar_chart,
    ),
    _Destination(
      l10n.navSettings,
      '/settings',
      Icons.settings_outlined,
      Icons.settings,
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
