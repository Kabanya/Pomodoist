part of 'timeline_screen.dart';

class _ProjectTimelineLayout {
  const _ProjectTimelineLayout({
    required this.row,
    required this.tasks,
    required this.top,
    required this.height,
  });

  final TimelineProjectRow row;
  final List<_TimedTaskLayout> tasks;
  final double top;
  final double height;

  double get bottom => top + height;
}

class _TimelineProjectsButton extends StatelessWidget {
  const _TimelineProjectsButton({
    required this.presentation,
    required this.onOpen,
  });

  final TimelineDayPresentation presentation;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ShadButton.ghost(
      key: const Key('timeline-project-menu'),
      onPressed: () {
        onOpen();
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) =>
                _TimelineProjectMenuDialog(presentation: presentation),
          ),
        );
      },
      child: Text(context.l10n.timelineProjectsMenu),
    );
  }
}

class _TimelineProjectHeader extends ConsumerWidget {
  const _TimelineProjectHeader({required this.layout, required this.onColor});

  final _ProjectTimelineLayout layout;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = layout.row.project;
    final collapsed = ref.watch(
      timelineViewModelProvider
          .select((state) => state.collapsed)
          .select((ids) => ids.contains(project.id)),
    );
    return Container(
      key: Key('timeline-project-row-${project.id}'),
      height: layout.height,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.appColors.border.withValues(alpha: 0.55),
          ),
        ),
      ),
      padding: const EdgeInsetsDirectional.only(start: 8, end: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Center(
              child: ProjectColorSwatch(
                key: Key('timeline-project-color-${project.id}'),
                color: effectiveProjectColor(project),
                onPressed: project.id == inboxProjectId ? null : onColor,
                size: 10,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              project.displayName(context.l10n),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          if (layout.row.hasVisibleChildren)
            Tooltip(
              message: collapsed
                  ? context.l10n.timelineExpandProject
                  : context.l10n.timelineCollapseProject,
              child: ShadIconButton.ghost(
                key: Key('timeline-project-collapse-${project.id}'),
                onPressed: () => unawaited(
                  ref
                      .read(timelineViewModelProvider.notifier)
                      .toggleCollapsed(project.id),
                ),
                icon: Icon(
                  collapsed
                      ? LucideIcons.chevronRight
                      : LucideIcons.chevronDown,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                width: 28,
                height: 32,
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineProjectMenuDialog extends ConsumerWidget {
  const _TimelineProjectMenuDialog({required this.presentation});

  final TimelineDayPresentation presentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timelineViewModelProvider);
    final projects = state.projects.value ?? presentation.menuProjects;
    final rows = buildTimelineProjectRows(
      projects: projects,
      tasks: presentation.tasksById.values,
      collapsedProjectIds: const {},
      temporarilyVisibleProjectIds: state.temporary,
    );
    final visible = {for (final row in rows) row.project.id: row};
    final vm = ref.read(timelineViewModelProvider.notifier);
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.navProjects),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final project in activeTimelineProjectMenuItems(projects))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.displayName(l10n)),
                    Wrap(
                      spacing: 4,
                      children: [
                        Tooltip(
                          message: l10n.projectColor,
                          child: ShadIconButton.ghost(
                            width: 44,
                            height: 44,
                            icon: Icon(
                              LucideIcons.circle,
                              color: projectColorValue(
                                effectiveProjectColor(project),
                              ),
                            ),
                            onPressed: () => unawaited(
                              _changeTimelineProjectColor(
                                context,
                                ref,
                                project,
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: visible.containsKey(project.id)
                              ? l10n.timelineHideProject
                              : l10n.timelineShowProject,
                          child: ShadIconButton.ghost(
                            key: Key(
                              'timeline-project-menu-toggle-${project.id}',
                            ),
                            onPressed:
                                visible.containsKey(project.id) &&
                                    !state.temporary.contains(project.id)
                                ? null
                                : () => vm.toggleTemporary(project.id),
                            icon: Icon(
                              visible.containsKey(project.id)
                                  ? LucideIcons.eye
                                  : LucideIcons.eyeOff,
                            ),
                            width: 44,
                            height: 44,
                          ),
                        ),
                        Tooltip(
                          message: project.isFavorite
                              ? l10n.removeProjectFromFavorites
                              : l10n.addProjectToFavorites,
                          child: Semantics(
                            toggled: project.isFavorite,
                            child: ShadIconButton.ghost(
                              key: Key(
                                'timeline-project-menu-favorite-${project.id}',
                              ),
                              onPressed: () => unawaited(
                                _toggleFavorite(context, ref, project),
                              ),
                              icon: Icon(
                                LucideIcons.star,
                                color: project.isFavorite
                                    ? context.appColors.accent
                                    : null,
                              ),
                              width: 44,
                              height: 44,
                            ),
                          ),
                        ),
                        if (visible[project.id]?.hasVisibleChildren ?? false)
                          Tooltip(
                            message: state.collapsed.contains(project.id)
                                ? l10n.timelineExpandProject
                                : l10n.timelineCollapseProject,
                            child: ShadIconButton.ghost(
                              onPressed: () =>
                                  unawaited(vm.toggleCollapsed(project.id)),
                              icon: Icon(
                                state.collapsed.contains(project.id)
                                    ? LucideIcons.chevronRight
                                    : LucideIcons.chevronDown,
                              ),
                              width: 44,
                              height: 44,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    ProjectItem project,
  ) async {
    try {
      await ref
          .read(timelineViewModelProvider.notifier)
          .updateProject(
            project.id,
            UpdateProjectPatch(isFavorite: !project.isFavorite),
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
        );
      }
    }
  }
}
