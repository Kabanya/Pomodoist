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
}

class _TimelineProjectHeader extends ConsumerWidget {
  const _TimelineProjectHeader({required this.layout, required this.onColor});

  final _ProjectTimelineLayout layout;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = layout.row.project;
    final collapsed = ref.watch(
      timelineCollapsedProjectIdsProvider.select(
        (ids) => ids.contains(project.id),
      ),
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
                      .read(timelineCollapsedProjectIdsProvider.notifier)
                      .toggle(project.id),
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

class _TimelineProjectMenuDialog extends ConsumerWidget {
  const _TimelineProjectMenuDialog({
    required this.projects,
    required this.visibleProjectIds,
  });

  final List<ProjectItem> projects;
  final Set<String> visibleProjectIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temporary = ref.watch(timelineTemporarilyVisibleProjectIdsProvider);
    final active =
        projects
            .where(
              (project) =>
                  project.id != inboxProjectId &&
                  !project.isArchived &&
                  !project.isDeleted,
            )
            .toList()
          ..sort((a, b) => a.orderKey.compareTo(b.orderKey));
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
                          visibleProjectIds.contains(project.id) ||
                              temporary.contains(project.id)
                          ? context.l10n.timelineHideProject
                          : context.l10n.timelineShowProject,
                      child: ShadIconButton.ghost(
                        key: Key('timeline-project-menu-toggle-${project.id}'),
                        onPressed:
                            visibleProjectIds.contains(project.id) &&
                                !temporary.contains(project.id)
                            ? null
                            : () => ref
                                  .read(
                                    timelineTemporarilyVisibleProjectIdsProvider
                                        .notifier,
                                  )
                                  .toggle(project.id),
                        icon: Icon(
                          visibleProjectIds.contains(project.id) ||
                                  temporary.contains(project.id)
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                        ),
                        enabled:
                            !(visibleProjectIds.contains(project.id) &&
                                !temporary.contains(project.id)),
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
                              unawaited(_toggleFavorite(context, ref, project)),
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

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    ProjectItem project,
  ) async {
    try {
      await ref
          .read(projectRepositoryProvider)
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
