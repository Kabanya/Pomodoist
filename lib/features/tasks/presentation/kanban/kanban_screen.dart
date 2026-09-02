import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_l10n.dart';
import '../../../../app/formatters.dart';
import '../../../../app/providers.dart';
import '../../../../app/task_time.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/action_feedback.dart';
import '../../../focus/domain/focus_models.dart';
import '../../domain/project_colors.dart';
import '../../domain/task_models.dart';
import '../widgets/project_color_picker.dart';
import '../widgets/quick_add_bar.dart';
import '../widgets/task_motion.dart';
import 'kanban_board_controller.dart';

const _kanbanWideBreakpoint = 820.0;
const _columnGap = 12.0;

String _statusDisplayName(BuildContext context, KanbanStatus status) {
  final l10n = context.l10n;
  return switch (status.systemKey) {
    KanbanSystemKey.backlog when status.name == 'Backlog' =>
      l10n.kanbanDefaultBacklog,
    KanbanSystemKey.todo when status.name == 'To do' => l10n.kanbanDefaultTodo,
    KanbanSystemKey.inProgress when status.name == 'In progress' =>
      l10n.kanbanDefaultInProgress,
    KanbanSystemKey.done when status.name == 'Done' => l10n.kanbanDefaultDone,
    _ => status.name,
  };
}

class KanbanScreen extends ConsumerStatefulWidget {
  const KanbanScreen({this.showMobileTitle = true, super.key});

  final bool showMobileTitle;

  @override
  ConsumerState<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends ConsumerState<KanbanScreen> {
  late final KanbanBoardController _controller;
  final _searchController = TextEditingController();
  String? _expandedStatusId;
  String _query = '';
  bool _searchVisible = false;
  bool _hideDone = false;
  KanbanBoardSnapshot? _latestBoard;
  TaskMotionController? _motion;

  @override
  void initState() {
    super.initState();
    _controller = KanbanBoardController(ref.read(kanbanRepositoryProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardValue = ref.watch(kanbanBoardProvider);
    final board = boardValue.value;
    if (board == null) {
      if (boardValue.hasError) {
        return _KanbanHardError(
          error: boardValue.error!,
          onRetry: () => ref.invalidate(kanbanBoardProvider),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    _latestBoard = board;

    final statuses = board.statuses
        .where((status) => !_hideDone || !status.isDone)
        .toList(growable: false);
    final focusStatusId = board.settings.focusStatusLabelId;
    final expandedStatusId =
        statuses.any((status) => status.id == _expandedStatusId)
        ? _expandedStatusId!
        : statuses.any((status) => status.id == focusStatusId)
        ? focusStatusId
        : statuses.first.id;
    if (_expandedStatusId != expandedStatusId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _expandedStatusId = expandedStatusId);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.reconcile(board);
      }
    });

    return TaskMotionScope(
      builder: (context, motion) {
        _motion = motion;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final cardsByStatus = _filteredCards(
              _controller.visibleCards(board),
              _query,
            );
            final wide =
                MediaQuery.sizeOf(context).width >= _kanbanWideBreakpoint;
            return ColoredBox(
              color: context.appColors.canvas,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  children: [
                    _KanbanHeader(
                      board: board,
                      wide: wide,
                      showMobileTitle: widget.showMobileTitle,
                      searchVisible: _searchVisible,
                      searchController: _searchController,
                      hideDone: _hideDone,
                      onToggleSearch: () =>
                          setState(() => _searchVisible = !_searchVisible),
                      onQueryChanged: (value) => setState(() => _query = value),
                      onToggleDone: () =>
                          setState(() => _hideDone = !_hideDone),
                      onSelectProjects: () => _selectProjects(board),
                      onAdd: () =>
                          _openAddDialog(board, statusId: _backlogId(board)),
                    ),
                    if (boardValue.isLoading)
                      const LinearProgressIndicator(
                        key: Key('kanban-stale-loading'),
                        minHeight: 2,
                      ),
                    Expanded(
                      child: wide
                          ? _DesktopKanbanBoard(
                              statuses: statuses,
                              allStatuses: board.statuses,
                              focusStatusId: focusStatusId,
                              cardsByStatus: cardsByStatus,
                              onMove: _moveTask,
                              onOpen: _openTask,
                              onStartFocus: _startFocus,
                              onAdd: (status) =>
                                  _openAddDialog(board, statusId: status.id),
                            )
                          : _MobileKanbanBoard(
                              statuses: statuses,
                              allStatuses: board.statuses,
                              focusStatusId: focusStatusId,
                              expandedStatusId: expandedStatusId,
                              cardsByStatus: cardsByStatus,
                              onExpanded: (statusId) =>
                                  setState(() => _expandedStatusId = statusId),
                              onMove: _moveTask,
                              onOpen: _openTask,
                              onStartFocus: _startFocus,
                              onAdd: (status) =>
                                  _openAddDialog(board, statusId: status.id),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Map<String, List<KanbanCard>> _filteredCards(
    Map<String, List<KanbanCard>> cards,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return cards;
    }
    return {
      for (final entry in cards.entries)
        entry.key: entry.value
            .where(
              (card) =>
                  card.task.content.toLowerCase().contains(normalized) ||
                  card.project.name.toLowerCase().contains(normalized),
            )
            .toList(growable: false),
    };
  }

  String _backlogId(KanbanBoardSnapshot board) {
    return board.statuses.firstWhere((status) => status.isBacklog).id;
  }

  Future<void> _moveTask(
    String taskId,
    String statusId, {
    int? targetIndex,
  }) async {
    try {
      await _controller.moveTask(
        taskId,
        statusId: statusId,
        targetIndex: targetIndex,
      );
      if (mounted) {
        _motion?.landed({taskId});
        unawaited(playHaptic(AppHapticCue.light));
        KanbanStatus? status;
        for (final candidate in _latestBoard?.statuses ?? const []) {
          if (candidate.id == statusId) {
            status = candidate;
            break;
          }
        }
        if (status != null) {
          _announce(
            context.l10n.kanbanMoveAnnouncement(
              _statusDisplayName(context, status),
            ),
          );
        }
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.taskActionFailedCount(1))),
      );
    }
  }

  void _openTask(String taskId) => context.push('/task/$taskId');

  Future<void> _startFocus(KanbanCard card) async {
    if (card.task.isCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.kanbanRestoreBeforeFocus)),
      );
      return;
    }
    try {
      await ref
          .read(focusRepositoryProvider)
          .startRun(
            StartFocusRunInput(
              taskId: card.task.id,
              projectId: card.project.id,
              targetWorkIntervals: card.task.estimatedFocusIntervals,
            ),
          );
      if (mounted) {
        _announce(
          context.l10n.kanbanFocusStartedAnnouncement(card.task.content),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.kanbanCouldNotStartFocus(error))),
        );
      }
    }
  }

  void _announce(String message) {
    if (!MediaQuery.supportsAnnounceOf(context)) {
      return;
    }
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  Future<void> _selectProjects(KanbanBoardSnapshot board) async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _ProjectSelectionDialog(board: board),
    );
    if (selected == null || selected.isEmpty) {
      return;
    }
    await ref.read(kanbanRepositoryProvider).setSelectedProjectIds(selected);
  }

  Future<void> _openAddDialog(
    KanbanBoardSnapshot board, {
    required String statusId,
  }) async {
    final status = board.statuses.firstWhere((item) => item.id == statusId);
    if (status.isDone) {
      return;
    }
    final createdIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => _KanbanAddDialog(board: board, status: status),
    );
    if (createdIds != null && createdIds.isNotEmpty) {
      _motion?.created(createdIds.toSet());
      await playHaptic(AppHapticCue.light);
    }
  }
}

class _KanbanHardError extends StatelessWidget {
  const _KanbanHardError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              context.l10n.kanbanCouldNotLoad(error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('kanban-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanHeader extends StatelessWidget {
  const _KanbanHeader({
    required this.board,
    required this.wide,
    required this.showMobileTitle,
    required this.searchVisible,
    required this.searchController,
    required this.hideDone,
    required this.onToggleSearch,
    required this.onQueryChanged,
    required this.onToggleDone,
    required this.onSelectProjects,
    required this.onAdd,
  });

  final KanbanBoardSnapshot board;
  final bool wide;
  final bool showMobileTitle;
  final bool searchVisible;
  final TextEditingController searchController;
  final bool hideDone;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleDone;
  final VoidCallback onSelectProjects;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.kanbanTitle,
          key: const Key('kanban-title'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        if (wide)
          Text(
            context.l10n.kanbanSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
          ),
      ],
    );
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ProjectSelectorButton(board: board, onPressed: onSelectProjects),
        IconButton.outlined(
          key: const Key('kanban-search-toggle'),
          tooltip: context.l10n.kanbanSearchTooltip,
          onPressed: onToggleSearch,
          icon: Icon(searchVisible ? Icons.search_off : Icons.search),
        ),
        IconButton.outlined(
          key: const Key('kanban-filter-toggle'),
          tooltip: hideDone
              ? context.l10n.kanbanShowDone
              : context.l10n.kanbanHideDone,
          onPressed: onToggleDone,
          icon: Icon(
            hideDone ? Icons.filter_alt_off : Icons.filter_alt_outlined,
          ),
        ),
        if (wide || showMobileTitle)
          FilledButton.icon(
            key: const Key('kanban-global-add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(context.l10n.addTask),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        wide ? 24 : 16,
        12,
        wide ? 24 : 16,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                Flexible(child: controls),
              ],
            )
          else ...[
            if (showMobileTitle) ...[
              Center(child: title),
              const SizedBox(height: 12),
            ],
            controls,
          ],
          if (searchVisible) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('kanban-search-field'),
              autofocus: true,
              controller: searchController,
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: context.l10n.kanbanSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProjectSelectorButton extends StatelessWidget {
  const _ProjectSelectorButton({required this.board, required this.onPressed});

  final KanbanBoardSnapshot board;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final selected = board.availableProjects
        .where(
          (project) => board.settings.selectedProjectIds.contains(project.id),
        )
        .toList(growable: false);
    return OutlinedButton(
      key: const Key('kanban-project-selector'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final project in selected.take(2)) ...[
            _ProjectDot(project: project),
            const SizedBox(width: 5),
            Flexible(
              child: Text(project.name, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
          ],
          if (selected.length > 2) Text('+${selected.length - 2}'),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }
}

class _DesktopKanbanBoard extends StatelessWidget {
  const _DesktopKanbanBoard({
    required this.statuses,
    required this.allStatuses,
    required this.focusStatusId,
    required this.cardsByStatus,
    required this.onMove,
    required this.onOpen,
    required this.onStartFocus,
    required this.onAdd,
  });

  final List<KanbanStatus> statuses;
  final List<KanbanStatus> allStatuses;
  final String focusStatusId;
  final Map<String, List<KanbanCard>> cardsByStatus;
  final Future<void> Function(String, String, {int? targetIndex}) onMove;
  final ValueChanged<String> onOpen;
  final ValueChanged<KanbanCard> onStartFocus;
  final ValueChanged<KanbanStatus> onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('kanban-desktop-board'),
      padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < statuses.length; index++) ...[
            if (index > 0) const SizedBox(width: _columnGap),
            Expanded(
              child: _KanbanStatusColumn(
                status: statuses[index],
                statuses: allStatuses,
                cards: cardsByStatus[statuses[index].id] ?? const [],
                focused: statuses[index].id == focusStatusId,
                onMove: onMove,
                onOpen: onOpen,
                onStartFocus: onStartFocus,
                onAdd: statuses[index].isDone ? null : () => onAdd(statuses[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KanbanStatusColumn extends StatelessWidget {
  const _KanbanStatusColumn({
    required this.status,
    required this.statuses,
    required this.cards,
    required this.focused,
    required this.onMove,
    required this.onOpen,
    required this.onStartFocus,
    required this.onAdd,
  });

  final KanbanStatus status;
  final List<KanbanStatus> statuses;
  final List<KanbanCard> cards;
  final bool focused;
  final Future<void> Function(String, String, {int? targetIndex}) onMove;
  final ValueChanged<String> onOpen;
  final ValueChanged<KanbanCard> onStartFocus;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final background = focused
        ? Color.alphaBlend(
            colors.accentTint.withValues(alpha: 0.72),
            colors.surface,
          )
        : colors.surfaceTint;
    return DecoratedBox(
      key: Key('kanban-column-${status.id}'),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
          color: focused
              ? colors.accent.withValues(alpha: 0.2)
              : colors.border,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _StatusHeader(
            status: status,
            count: cards.length,
            focused: focused,
          ),
          Expanded(
            child: ListView.builder(
              key: Key('kanban-column-scroll-${status.id}'),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              itemCount: cards.length + 1,
              itemBuilder: (context, index) {
                if (index == cards.length) {
                  return _KanbanDropTarget(
                    key: Key('kanban-drop-end-${status.id}'),
                    onAccept: (payload) => onMove(
                      payload.taskId,
                      status.id,
                      targetIndex: status.isDone ? null : cards.length,
                    ),
                    child: SizedBox(
                      height: cards.isEmpty ? 96 : 24,
                      child: cards.isEmpty
                          ? Center(child: Text(context.l10n.kanbanNoTasks))
                          : null,
                    ),
                  );
                }
                final card = cards[index];
                return _KanbanDropTarget(
                  key: Key('kanban-drop-${status.id}-$index'),
                  onAccept: (payload) => onMove(
                    payload.taskId,
                    status.id,
                    targetIndex: status.isDone ? null : index,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _KanbanTaskCard(
                      card: card,
                      status: status,
                      statuses: statuses,
                      desktop: true,
                      sourceIndex: index,
                      onMove: onMove,
                      onOpen: onOpen,
                      onStartFocus: onStartFocus,
                    ),
                  ),
                );
              },
            ),
          ),
          if (onAdd != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextButton.icon(
                key: Key('kanban-add-${status.id}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  alignment: AlignmentDirectional.centerStart,
                ),
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.addTask),
              ),
            ),
        ],
      ),
    );
  }
}

class _MobileKanbanBoard extends StatelessWidget {
  const _MobileKanbanBoard({
    required this.statuses,
    required this.allStatuses,
    required this.focusStatusId,
    required this.expandedStatusId,
    required this.cardsByStatus,
    required this.onExpanded,
    required this.onMove,
    required this.onOpen,
    required this.onStartFocus,
    required this.onAdd,
  });

  final List<KanbanStatus> statuses;
  final List<KanbanStatus> allStatuses;
  final String focusStatusId;
  final String expandedStatusId;
  final Map<String, List<KanbanCard>> cardsByStatus;
  final ValueChanged<String> onExpanded;
  final Future<void> Function(String, String, {int? targetIndex}) onMove;
  final ValueChanged<String> onOpen;
  final ValueChanged<KanbanCard> onStartFocus;
  final ValueChanged<KanbanStatus> onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('kanban-mobile-board'),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
      itemCount: statuses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final status = statuses[index];
        final cards = cardsByStatus[status.id] ?? const [];
        final expanded = status.id == expandedStatusId;
        return _MobileStatusSection(
          status: status,
          statuses: allStatuses,
          cards: cards,
          focused: status.id == focusStatusId,
          expanded: expanded,
          onExpanded: () => onExpanded(status.id),
          onMove: (payload) {
            onExpanded(status.id);
            return onMove(
              payload.taskId,
              status.id,
              targetIndex: status.isDone ? null : cards.length,
            );
          },
          onMoveTask: onMove,
          onOpen: onOpen,
          onStartFocus: onStartFocus,
          onAdd: status.isDone ? null : () => onAdd(status),
        );
      },
    );
  }
}

class _MobileStatusSection extends StatelessWidget {
  const _MobileStatusSection({
    required this.status,
    required this.statuses,
    required this.cards,
    required this.focused,
    required this.expanded,
    required this.onExpanded,
    required this.onMove,
    required this.onMoveTask,
    required this.onOpen,
    required this.onStartFocus,
    required this.onAdd,
  });

  final KanbanStatus status;
  final List<KanbanStatus> statuses;
  final List<KanbanCard> cards;
  final bool focused;
  final bool expanded;
  final VoidCallback onExpanded;
  final Future<void> Function(KanbanDragPayload) onMove;
  final Future<void> Function(String, String, {int? targetIndex}) onMoveTask;
  final ValueChanged<String> onOpen;
  final ValueChanged<KanbanCard> onStartFocus;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final background = focused
        ? Color.alphaBlend(
            colors.accentTint.withValues(alpha: 0.72),
            colors.surface,
          )
        : colors.surface;
    return _KanbanDropTarget(
      key: Key('kanban-mobile-drop-${status.id}'),
      onAccept: onMove,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: focused
                ? colors.accent.withValues(alpha: 0.25)
                : colors.border,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          key: Key(
            expanded ? 'kanban-section-expanded' : 'kanban-section-collapsed',
          ),
          children: [
            InkWell(
              key: Key('kanban-section-header-${status.id}'),
              borderRadius: BorderRadius.circular(14),
              onTap: onExpanded,
              child: _StatusHeader(
                status: status,
                count: cards.length,
                focused: focused,
                expanded: expanded,
              ),
            ),
            if (expanded) ...[
              if (cards.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(context.l10n.kanbanNoTasks),
                ),
              for (var index = 0; index < cards.length; index++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: _KanbanTaskCard(
                    card: cards[index],
                    status: status,
                    statuses: statuses,
                    desktop: false,
                    sourceIndex: index,
                    onMove: onMoveTask,
                    onOpen: onOpen,
                    onStartFocus: onStartFocus,
                  ),
                ),
              if (onAdd != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: TextButton.icon(
                    key: Key('kanban-add-${status.id}'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      alignment: AlignmentDirectional.centerStart,
                    ),
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.addTask),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.status,
    required this.count,
    required this.focused,
    this.expanded,
  });

  final KanbanStatus status;
  final int count;
  final bool focused;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: expanded != null,
      expanded: expanded,
      label:
          '${_statusDisplayName(context, status)}, ${context.l10n.kanbanTasksCount(count)}',
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _statusDisplayName(context, status),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: focused ? colors.accent : colors.primaryText,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: focused
                      ? colors.accent.withValues(alpha: 0.1)
                      : colors.surfaceHover,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text('$count'),
                ),
              ),
              if (expanded != null) ...[
                const SizedBox(width: 8),
                Icon(expanded! ? Icons.expand_less : Icons.expand_more),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KanbanDropTarget extends StatelessWidget {
  const _KanbanDropTarget({
    required this.onAccept,
    required this.child,
    super.key,
  });

  final Future<void> Function(KanbanDragPayload) onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<KanbanDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => unawaited(onAccept(details.data)),
      builder: (context, candidates, rejected) {
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120);
        return AnimatedPadding(
          duration: duration,
          padding: candidates.isEmpty
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedContainer(
            duration: duration,
            decoration: candidates.isEmpty
                ? null
                : BoxDecoration(
                    border: Border.all(color: context.appColors.accent),
                    borderRadius: BorderRadius.circular(12),
                  ),
            child: child,
          ),
        );
      },
    );
  }
}

class _KanbanTaskCard extends ConsumerWidget {
  const _KanbanTaskCard({
    required this.card,
    required this.status,
    required this.statuses,
    required this.desktop,
    required this.sourceIndex,
    required this.onMove,
    required this.onOpen,
    required this.onStartFocus,
  });

  final KanbanCard card;
  final KanbanStatus status;
  final List<KanbanStatus> statuses;
  final bool desktop;
  final int sourceIndex;
  final Future<void> Function(String, String, {int? targetIndex}) onMove;
  final ValueChanged<String> onOpen;
  final ValueChanged<KanbanCard> onStartFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final task = card.task;
    final activeFocusTaskId = ref.watch(activeFocusRunProvider).value?.taskId;
    final active = activeFocusTaskId == task.id;
    final taskTimeState = ref.watch(taskTimeStateProvider(task));
    final timeDisplayMode = ref.watch(taskTimeDisplayModeProvider);
    final defaultTimedBlockMinutes = ref.watch(
      quickAddDefaultTimedBlockMinutesProvider,
    );
    final taskTimeLabel = task.schedule == null
        ? null
        : formatTaskListSchedule(
            context,
            task.schedule!,
            displayMode: timeDisplayMode,
            defaultTimedBlockMinutes: defaultTimedBlockMinutes,
          );
    final taskTimeStatus = taskTimeState == null
        ? null
        : taskTimeStatusLabel(context.l10n, taskTimeState);
    final taskTimeColor = taskTimeState == null
        ? null
        : colors.taskTimeColor(taskTimeState);
    final payload = KanbanDragPayload(
      taskId: task.id,
      sourceStatusId: status.id,
      sourceIndex: sourceIndex,
      token: DateTime.now().microsecondsSinceEpoch,
    );
    final content = Semantics(
      key: Key('kanban-card-semantics-${task.id}'),
      container: true,
      label: _semanticLabel(
        context,
        taskTimeLabel: taskTimeLabel,
        taskTimeStatus: taskTimeStatus,
      ),
      child: Material(
        key: Key('kanban-card-${task.id}'),
        color: colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: active
                ? colors.accent.withValues(alpha: 0.65)
                : colors.border,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onOpen(task.id),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        task.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? colors.mutedText
                              : colors.primaryText,
                        ),
                      ),
                    ),
                    if (desktop)
                      Tooltip(
                        message: context.l10n.kanbanDragTask,
                        child: Draggable<KanbanDragPayload>(
                          data: payload,
                          feedback: Transform.scale(
                            scale: 1.025,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 260,
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(task.content),
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: const SizedBox.square(
                            dimension: 48,
                          ),
                          child: SizedBox.square(
                            key: Key('kanban-drag-handle-${task.id}'),
                            dimension: 48,
                            child: const Icon(Icons.drag_indicator),
                          ),
                        ),
                      ),
                    _CardMenu(
                      card: card,
                      status: status,
                      statuses: statuses,
                      onMove: onMove,
                      onOpen: onOpen,
                      onStartFocus: onStartFocus,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _ProjectDot(project: card.project),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        card.project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.secondaryText),
                      ),
                    ),
                    _PriorityFlag(priority: task.priority),
                  ],
                ),
                if (task.schedule != null || card.totalSubtasks > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if (taskTimeLabel != null)
                        _MetaLabel(
                          icon: Icons.calendar_today_outlined,
                          text: taskTimeLabel,
                          color: taskTimeColor,
                          semanticLabel: taskTimeStatus,
                          taskId: task.id,
                        ),
                      if (card.totalSubtasks > 0)
                        _MetaLabel(
                          icon: Icons.account_tree_outlined,
                          text:
                              '${card.completedSubtasks}/${card.totalSubtasks}',
                        ),
                    ],
                  ),
                ],
                if (active)
                  const _ActiveFocusProgress()
                else if ((task.estimatedFocusIntervals ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  _FocusProgress(task: task),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final draggable = desktop
        ? content
        : LongPressDraggable<KanbanDragPayload>(
            key: Key('kanban-long-press-${task.id}'),
            data: payload,
            feedback: Transform.scale(
              scale: 1.025,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width - 64,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(task.content),
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: content),
            child: content,
          );
    return TaskMotionItem(taskId: task.id, child: draggable);
  }

  String _semanticLabel(
    BuildContext context, {
    String? taskTimeLabel,
    String? taskTimeStatus,
  }) {
    final task = card.task;
    final parts = <String>[
      task.content,
      _statusDisplayName(context, status),
      card.project.name,
      context.l10n.kanbanPriority(task.priority),
    ];
    if (taskTimeLabel != null) {
      parts.add(taskTimeLabel);
    }
    if (taskTimeStatus != null) {
      parts.add(taskTimeStatus);
    }
    if (card.totalSubtasks > 0) {
      parts.add(
        context.l10n.kanbanSubtasksProgress(
          card.completedSubtasks,
          card.totalSubtasks,
        ),
      );
    }
    if ((task.estimatedFocusIntervals ?? 0) > 0) {
      parts.add(
        context.l10n.kanbanFocusIntervalsProgress(
          task.completedFocusIntervals,
          task.estimatedFocusIntervals!,
        ),
      );
    }
    return parts.join(', ');
  }
}

enum _CardActionKind { open, move, completeOrRestore, focus }

class _CardAction {
  const _CardAction(this.kind, [this.statusId]);

  final _CardActionKind kind;
  final String? statusId;
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({
    required this.card,
    required this.status,
    required this.statuses,
    required this.onMove,
    required this.onOpen,
    required this.onStartFocus,
  });

  final KanbanCard card;
  final KanbanStatus status;
  final List<KanbanStatus> statuses;
  final Future<void> Function(String, String, {int? targetIndex}) onMove;
  final ValueChanged<String> onOpen;
  final ValueChanged<KanbanCard> onStartFocus;

  @override
  Widget build(BuildContext context) {
    final done = statuses.firstWhere((candidate) => candidate.isDone);
    final restoreTarget = statuses.firstWhere(
      (candidate) => !candidate.isDone && !candidate.isBacklog,
      orElse: () => statuses.firstWhere((candidate) => candidate.isBacklog),
    );
    return PopupMenuButton<_CardAction>(
      key: Key('kanban-card-menu-${card.task.id}'),
      tooltip: context.l10n.kanbanTaskActions,
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (action) {
        switch (action.kind) {
          case _CardActionKind.open:
            onOpen(card.task.id);
          case _CardActionKind.move:
            unawaited(onMove(card.task.id, action.statusId!));
          case _CardActionKind.completeOrRestore:
            unawaited(
              onMove(
                card.task.id,
                card.task.isCompleted ? restoreTarget.id : done.id,
              ),
            );
          case _CardActionKind.focus:
            onStartFocus(card);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: const _CardAction(_CardActionKind.open),
          child: ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(context.l10n.commonOpen),
          ),
        ),
        for (final candidate in statuses)
          if (candidate.id != status.id)
            PopupMenuItem(
              value: _CardAction(_CardActionKind.move, candidate.id),
              child: ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(
                  context.l10n.kanbanMoveTo(
                    _statusDisplayName(context, candidate),
                  ),
                ),
              ),
            ),
        PopupMenuItem(
          value: const _CardAction(_CardActionKind.completeOrRestore),
          child: ListTile(
            leading: Icon(
              card.task.isCompleted
                  ? Icons.restore
                  : Icons.check_circle_outline,
            ),
            title: Text(
              card.task.isCompleted
                  ? context.l10n.markOpen
                  : context.l10n.markComplete,
            ),
          ),
        ),
        PopupMenuItem(
          enabled: !card.task.isCompleted,
          value: const _CardAction(_CardActionKind.focus),
          child: ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(context.l10n.startFocus),
          ),
        ),
      ],
      icon: const Icon(Icons.more_horiz),
    );
  }
}

class _ProjectDot extends StatelessWidget {
  const _ProjectDot({required this.project});

  final ProjectItem project;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: projectColorValue(effectiveProjectColor(project)),
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 10),
    );
  }
}

class _PriorityFlag extends StatelessWidget {
  const _PriorityFlag({required this.priority});

  final int priority;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = switch (priority) {
      1 => colors.accent,
      2 => colors.warning,
      3 => colors.info,
      _ => colors.mutedText,
    };
    return Tooltip(
      message: context.l10n.kanbanPriority(priority),
      child: SizedBox.square(
        dimension: 44,
        child: Icon(Icons.flag_outlined, color: color, size: 20),
      ),
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({
    required this.icon,
    required this.text,
    this.color,
    this.semanticLabel,
    this.taskId,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final String? semanticLabel;
  final String? taskId;

  @override
  Widget build(BuildContext context) {
    final labelColor = color ?? context.appColors.secondaryText;
    final content = Row(
      key: taskId == null ? null : ValueKey('kanban-task-time-meta-$taskId'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: labelColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            key: taskId == null
                ? null
                : ValueKey('kanban-task-time-label-$taskId'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: labelColor),
          ),
        ),
      ],
    );
    final status = semanticLabel;
    return status == null
        ? content
        : Semantics(label: '$text, $status', child: content);
  }
}

class _FocusProgress extends StatelessWidget {
  const _FocusProgress({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final total = task.estimatedFocusIntervals ?? 0;
    final value = total == 0
        ? 0.0
        : (task.completedFocusIntervals / total).clamp(0.0, 1.0);
    return Row(
      children: [
        Text('${context.l10n.navFocus} ${task.completedFocusIntervals}/$total'),
        const SizedBox(width: 8),
        Expanded(child: LinearProgressIndicator(value: value, minHeight: 5)),
      ],
    );
  }
}

class _ActiveFocusProgress extends ConsumerWidget {
  const _ActiveFocusProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(activeFocusRemainingProvider);
    final interval = ref.watch(activeFocusIntervalProvider).value;
    final planned = interval == null
        ? null
        : Duration(seconds: interval.plannedSeconds);
    final progress = interval == null || remaining == null
        ? 0.0
        : 1 - (remaining.inSeconds / interval.plannedSeconds).clamp(0.0, 1.0);
    return Padding(
      key: const Key('kanban-active-focus-progress'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.timer_outlined,
                size: 18,
                color: context.appColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.navFocus,
                style: TextStyle(color: context.appColors.accent),
              ),
              Expanded(
                child: Text(
                  remaining == null
                      ? context.l10n.kanbanActive
                      : planned == null
                      ? formatDurationCompact(remaining)
                      : '${formatDurationCompact(remaining)} / ${formatDurationCompact(planned)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: context.appColors.accent),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                key: const Key('kanban-stop-focus'),
                tooltip: context.l10n.commonStop,
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_stop(ref)),
                icon: const Icon(Icons.stop_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            borderRadius: BorderRadius.circular(5),
            color: context.appColors.accent,
          ),
        ],
      ),
    );
  }

  Future<void> _stop(WidgetRef ref) {
    return ref
        .read(focusRepositoryProvider)
        .stopActiveRun(reason: StopFocusReason.stopped);
  }
}

class _ProjectSelectionDialog extends StatefulWidget {
  const _ProjectSelectionDialog({required this.board});

  final KanbanBoardSnapshot board;

  @override
  State<_ProjectSelectionDialog> createState() =>
      _ProjectSelectionDialogState();
}

class _ProjectSelectionDialogState extends State<_ProjectSelectionDialog> {
  late final Set<String> _selected = widget.board.settings.selectedProjectIds
      .toSet();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.kanbanProjectsTitle),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final project in widget.board.availableProjects)
              CheckboxListTile(
                key: Key('kanban-project-option-${project.id}'),
                value: _selected.contains(project.id),
                secondary: _ProjectDot(project: project),
                title: Text(project.name),
                onChanged: (selected) {
                  setState(() {
                    if (selected ?? false) {
                      _selected.add(project.id);
                    } else if (_selected.length > 1) {
                      _selected.remove(project.id);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}

class _KanbanAddDialog extends ConsumerStatefulWidget {
  const _KanbanAddDialog({required this.board, required this.status});

  final KanbanBoardSnapshot board;
  final KanbanStatus status;

  @override
  ConsumerState<_KanbanAddDialog> createState() => _KanbanAddDialogState();
}

class _KanbanAddDialogState extends ConsumerState<_KanbanAddDialog> {
  String? _projectId;

  @override
  void initState() {
    super.initState();
    if (widget.board.settings.selectedProjectIds.length == 1) {
      _projectId = widget.board.settings.selectedProjectIds.single;
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.board.availableProjects
        .where(
          (project) =>
              widget.board.settings.selectedProjectIds.contains(project.id),
        )
        .toList(growable: false);
    return AlertDialog(
      title: Text(
        context.l10n.kanbanAddToStatus(
          _statusDisplayName(context, widget.status),
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (projects.length > 1) ...[
              DropdownButtonFormField<String>(
                key: const Key('kanban-add-project'),
                initialValue: _projectId,
                decoration: InputDecoration(
                  labelText: context.l10n.kanbanProjectField,
                ),
                items: [
                  for (final project in projects)
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
                onChanged: (value) => setState(() => _projectId = value),
              ),
              const SizedBox(height: 12),
            ],
            if (projects.length > 1 && _projectId == null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.l10n.kanbanChooseProject,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              QuickAddBar(
                inputKey: const Key('kanban-add-input'),
                voiceButtonKey: const Key('kanban-add-voice'),
                submitButtonKey: const Key('kanban-add-submit'),
                projectId: _projectId,
                kanbanStatusId: widget.status.id,
                onTaskCreated: (taskIds) => Navigator.of(context).pop(taskIds),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
      ],
    );
  }
}
