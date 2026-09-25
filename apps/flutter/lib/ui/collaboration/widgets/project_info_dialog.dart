import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadDialog;

import 'package:pomodoist/ui/collaboration/view_models/project_info_view_model.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';

Future<void> showProjectInfoDialog(BuildContext context, String projectId) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ProjectInfoDialog(projectId: projectId),
    );

class _ProjectInfoDialog extends ConsumerWidget {
  const _ProjectInfoDialog({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final provider = projectInfoViewModelProvider(projectId);
    final state = ref.watch(provider);
    return ShadDialog(
      title: Text(l10n.projectInfoTitle),
      constraints: const BoxConstraints(maxWidth: 512, maxHeight: 680),
      titlePinned: true,
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
      child: SizedBox(
        width: 460,
        child: state.when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(collaborationErrorMessage(l10n, error)),
              const SizedBox(height: 12),
              ShadButton.ghost(
                onPressed: () => ref.read(provider.notifier).reload(),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
          data: (info) => _content(context, info),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ProjectInfoState info) {
    final l10n = context.l10n;
    final scope = info.scope;
    final theme = Theme.of(context).textTheme;
    final owner = scope == null || scope.ownerId == info.actorId
        ? l10n.projectInfoYou
        : collaborationMemberLabel(l10n, scope, scope.ownerId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(info.project.displayName(l10n), style: theme.titleMedium),
        const SizedBox(height: 4),
        Text(
          scope == null
              ? l10n.projectInfoPersonal
              : l10n.collaborationSharedBadge,
          style: theme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text('${l10n.collaborationOwner}: $owner'),
        const SizedBox(height: 8),
        Text(
          '${l10n.collaborationJoinRole}: ${scope == null ? l10n.collaborationOwner : collaborationRoleLabel(l10n, scope.role)}',
        ),
        const SizedBox(height: 20),
        Text(
          '${l10n.collaborationMembers} (${info.memberCount})',
          style: theme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (scope == null)
          _member(context, l10n.projectInfoYou, l10n.collaborationOwner)
        else
          for (final member in scope.members)
            _member(
              context,
              member.displayName ?? l10n.collaborationMemberFallback,
              [
                collaborationRoleLabel(l10n, member.role),
                if (member.userId == scope.ownerId) l10n.collaborationOwner,
                if (member.userId == info.actorId) l10n.projectInfoYou,
              ].join(' · '),
            ),
      ],
    );
  }

  Widget _member(BuildContext context, String name, String details) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.userRound, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name),
              Text(details, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}
