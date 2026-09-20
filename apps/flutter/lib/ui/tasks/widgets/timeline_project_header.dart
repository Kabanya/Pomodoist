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

class _ProjectColumnHeader extends ConsumerWidget {
  const _ProjectColumnHeader({
    required this.projects,
    required this.visibleProjectIds,
  });

  final List<ProjectItem> projects;
  final Set<String> visibleProjectIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temporary = ref.watch(
      timelineViewModelProvider.select((state) => state.temporary),
    );
    return SizedBox(
      height: _timeRulerHeight,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.navProjects,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Tooltip(
            message: context.l10n.timelineProjectsMenu,
            child: ShadIconButton.ghost(
              key: const Key('timeline-project-menu'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => _TimelineProjectMenuDialog(
                  projects: projects,
                  visibleProjectIds: visibleProjectIds,
                  temporaryProjectIds: temporary,
                  onToggleTemporary: ref
                      .read(timelineViewModelProvider.notifier)
                      .toggleTemporary,
                  onToggleFavorite: (project) =>
                      _toggleFavorite(context, ref, project),
                ),
              ),
              icon: const Icon(LucideIcons.slidersHorizontal, size: 18),
              padding: EdgeInsets.zero,
              width: 32,
              height: 32,
            ),
          ),
        ],
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
    final projectColor = projectColorValue(effectiveProjectColor(project));
    return Container(
      key: Key('timeline-project-row-${project.id}'),
      height: layout.height,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.appColors.border.withValues(alpha: 0.55),
          ),
          left: BorderSide(color: projectColor, width: 3),
        ),
      ),
      padding: EdgeInsets.only(
        left: math.min(24, layout.row.depth * 12).toDouble(),
        right: 6,
      ),
      child: Row(
        children: [
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
            )
          else
            const SizedBox(width: 28),
          ProjectColorSwatch(
            key: Key('timeline-project-color-${project.id}'),
            color: effectiveProjectColor(project),
            onPressed: project.id == inboxProjectId ? null : onColor,
            size: 10,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              project.displayName(context.l10n),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineProjectMenuDialog extends StatefulWidget {
  const _TimelineProjectMenuDialog({
    required this.projects,
    required this.visibleProjectIds,
    required this.temporaryProjectIds,
    required this.onToggleTemporary,
    required this.onToggleFavorite,
  });

  final List<ProjectItem> projects;
  final Set<String> visibleProjectIds;
  final Set<String> temporaryProjectIds;
  final ValueChanged<String> onToggleTemporary;
  final Future<void> Function(ProjectItem) onToggleFavorite;

  @override
  State<_TimelineProjectMenuDialog> createState() =>
      _TimelineProjectMenuDialogState();
}

class _TimelineProjectMenuDialogState
    extends State<_TimelineProjectMenuDialog> {
  late final Set<String> _temporary = {...widget.temporaryProjectIds};

  @override
  Widget build(BuildContext context) {
    final active = widget.projects;
    return AlertDialog(
      title: Text(context.l10n.navProjects),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonClose),
        ),
      ],
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final project in active)
              ListTile(
                leading: ProjectColorSwatch(
                  color: effectiveProjectColor(project),
                  size: 16,
                ),
                title: Text(project.displayName(context.l10n)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message:
                          widget.visibleProjectIds.contains(project.id) ||
                              _temporary.contains(project.id)
                          ? context.l10n.timelineHideProject
                          : context.l10n.timelineShowProject,
                      child: ShadIconButton.ghost(
                        key: Key('timeline-project-menu-toggle-${project.id}'),
                        onPressed:
                            widget.visibleProjectIds.contains(project.id) &&
                                !_temporary.contains(project.id)
                            ? null
                            : () {
                                widget.onToggleTemporary(project.id);
                                setState(() {
                                  if (!_temporary.remove(project.id)) {
                                    _temporary.add(project.id);
                                  }
                                });
                              },
                        icon: Icon(
                          widget.visibleProjectIds.contains(project.id) ||
                                  _temporary.contains(project.id)
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                        ),
                        enabled:
                            !(widget.visibleProjectIds.contains(project.id) &&
                                !_temporary.contains(project.id)),
                        width: 40,
                        height: 40,
                      ),
                    ),
                    Tooltip(
                      message: project.isFavorite
                          ? context.l10n.removeProjectFromFavorites
                          : context.l10n.addProjectToFavorites,
                      child: Semantics(
                        toggled: project.isFavorite,
                        child: ShadIconButton.ghost(
                          key: Key(
                            'timeline-project-menu-favorite-${project.id}',
                          ),
                          onPressed: () =>
                              unawaited(widget.onToggleFavorite(project)),
                          icon: Icon(
                            LucideIcons.star,
                            color: project.isFavorite
                                ? context.appColors.accent
                                : context.appColors.mutedText,
                          ),
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
