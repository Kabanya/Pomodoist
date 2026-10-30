import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/collaboration/widgets/task_collaboration_section.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/resizable_dialog.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'package:pomodoist/ui/files/widgets/file_error_message.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_text_controller.dart';
import 'package:pomodoist/ui/tasks/view_models/task_create_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_input.dart';
import 'package:pomodoist/ui/tasks/widgets/task_description_field.dart';

Future<String?> showTaskCreateDialog(
  BuildContext context, {
  required QuickAddTextController title,
  required TextEditingController description,
  int? priority,
  DateTime? defaultDate,
  String? projectId,
  String? kanbanStatusId,
  String? labelId,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  animationStyle: AnimationStyle(
    duration: AppMotion.duration(context, AppMotion.popup),
    reverseDuration: AppMotion.duration(context, AppMotion.popup),
    curve: AppMotion.curve,
  ),
  builder: (_) => _TaskCreateDialog(
    title: title,
    description: description,
    priority: priority,
    defaultDate: defaultDate,
    projectId: projectId,
    kanbanStatusId: kanbanStatusId,
    labelId: labelId,
  ),
);

class _TaskCreateDialog extends ConsumerStatefulWidget {
  const _TaskCreateDialog({
    required this.title,
    required this.description,
    this.priority,
    this.defaultDate,
    this.projectId,
    this.kanbanStatusId,
    this.labelId,
  });
  final QuickAddTextController title;
  final TextEditingController description;
  final int? priority;
  final DateTime? defaultDate;
  final String? projectId, kanbanStatusId, labelId;
  @override
  ConsumerState<_TaskCreateDialog> createState() => _TaskCreateDialogState();
}

class _TaskCreateDialogState extends ConsumerState<_TaskCreateDialog> {
  final _identity = Object();
  TaskCreateViewModel get _model =>
      ref.read(taskCreateViewModelProvider(_identity).notifier);
  TaskCreateState get _state =>
      ref.read(taskCreateViewModelProvider(_identity));

  @override
  void initState() {
    super.initState();
    widget.title.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.title.removeListener(_changed);
    super.dispose();
  }

  TaskCreateContextQuery get _query => (
    text: widget.title.text,
    projectId: widget.projectId,
    defaultDate: widget.defaultDate,
  );

  void _cancel() {
    if (!_state.busy && _state.taskId == null) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    final target = ref.read(taskCreateContextViewModelProvider(_query));
    if (_state.taskId == null &&
        (!target.ready || target.project?.canEdit == false)) {
      return;
    }
    final task = await _model.submit(
      text: widget.title.text,
      description: widget.description.text,
      scopeId: target.scope?.id,
      priority: widget.priority,
      defaultDate: widget.defaultDate,
      projectId: widget.projectId,
      kanbanStatusId: widget.kanbanStatusId,
      labelId: widget.labelId,
    );
    if (mounted && task != null) Navigator.of(context).pop(task);
  }

  Future<void> _pick() async {
    try {
      await _model.pickFile();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(fileErrorMessage(context.l10n, error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskCreateViewModelProvider(_identity));
    final target = ref.watch(taskCreateContextViewModelProvider(_query));
    final l10n = context.l10n;
    final project = target.project;
    final scope = target.scope;
    final shared = project?.scopeId != null;
    final locked = state.busy || state.taskId != null;
    final canCancel = !locked;
    final selected = scope != null && state.assigneeScopeId == scope.id
        ? state.assigneeIds
        : const <String>{};
    final inset = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 28.0;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    return PopScope(
      canPop: canCancel,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submit,
        },
        child: ShortcutHintsScope(
          modal: true,
          identity: state.busy,
          hints: [
            if (!state.busy)
              ShortcutHint(l10n.taskCreateAction, '⌘ / Ctrl Enter'),
          ],
          child: ResizableDialog(
            initialSize: const Size(1080, 760),
            minSize: const Size(360, 480),
            actions: const [],
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(inset, 16, inset - 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              namesRoute: true,
                              header: true,
                              child: Text(
                                l10n.taskNew,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              project?.displayName(l10n) ??
                                  target.projectName ??
                                  l10n.navInbox,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.appColors.secondaryText,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.commonClose,
                        onPressed: canCancel ? _cancel : null,
                        icon: const Icon(LucideIcons.x),
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(inset, 8, inset, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        QuickAddInput(
                          textFieldKey: const Key('task-create-title'),
                          controller: widget.title,
                          autofocus: true,
                          enabled: !locked,
                          maxLines: 4,
                          textInputAction: TextInputAction.done,
                          style: Theme.of(context).textTheme.titleLarge,
                          decoration: InputDecoration(
                            hintText: l10n.taskTitleHint,
                            prefixIcon: const Icon(
                              LucideIcons.listPlus,
                              size: 20,
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (scope != null) ...[
                          const SizedBox(height: 28),
                          heading(l10n.collaborationAssignees),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final id in selected)
                                InputChip(
                                  avatar: CircleAvatar(
                                    backgroundColor:
                                        context.appColors.surfaceTint,
                                    child: Text(
                                      collaborationInitials(
                                        collaborationMemberLabel(
                                          l10n,
                                          scope,
                                          id,
                                        ),
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                  label: Text(
                                    collaborationMemberLabel(l10n, scope, id),
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.padded,
                                  onDeleted: locked || !scope.canEdit
                                      ? null
                                      : () => _model.setAssignees(
                                          scope.id,
                                          {...selected}..remove(id),
                                        ),
                                ),
                              TextButton.icon(
                                onPressed: locked || !scope.canEdit
                                    ? null
                                    : () async {
                                        final ids =
                                            await showTaskAssigneesDialog(
                                              context,
                                              scope: scope,
                                              assigneeIds: selected,
                                            );
                                        if (ids != null && mounted) {
                                          _model.setAssignees(scope.id, ids);
                                        }
                                      },
                                icon: const Icon(
                                  LucideIcons.userPlus,
                                  size: 18,
                                ),
                                label: Text(l10n.collaborationEditAssignees),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 28),
                        heading(l10n.taskDescription),
                        TaskDescriptionField(
                          controller: widget.description,
                          enabled: !locked,
                        ),
                        const SizedBox(height: 28),
                        heading(l10n.filesTitle),
                        for (final file in state.files)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: context.appColors.border,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                                child: Row(
                                  children: [
                                    const Icon(LucideIcons.file, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            file.file.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${(file.bytes / 1024).ceil()} KB',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: context
                                                      .appColors
                                                      .secondaryText,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: l10n.commonDelete,
                                      onPressed: state.busy
                                          ? null
                                          : () => _model.removeFile(file),
                                      icon: const Icon(LucideIcons.x, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: locked ? null : _pick,
                            icon: const Icon(LucideIcons.paperclip, size: 18),
                            label: Text(l10n.filesAdd),
                          ),
                        ),
                        if (state.error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            state.taskId != null
                                ? l10n.taskCreatedFilesPending
                                : l10n.taskCreateFailed,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: context.appColors.error),
                          ),
                          if (state.taskId != null)
                            Text(
                              fileErrorMessage(l10n, state.error),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: context.appColors.border),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: inset,
                    vertical: 12,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final audience = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            !shared ? LucideIcons.lock : LucideIcons.users,
                            size: 16,
                            color: context.appColors.secondaryText,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              !target.ready
                                  ? l10n.projectsUnavailableShort
                                  : !shared
                                  ? l10n.taskVisibleToYou
                                  : l10n.taskVisibleToTeam,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.appColors.secondaryText,
                                  ),
                            ),
                          ),
                        ],
                      );
                      final actions = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          ShadButton.outline(
                            onPressed: canCancel ? _cancel : null,
                            enabled: canCancel,
                            child: Text(l10n.commonCancel),
                          ),
                          ShadButton(
                            key: const Key('task-create-submit'),
                            enabled:
                                !state.busy &&
                                (state.taskId != null ||
                                    (target.ready &&
                                        project?.canEdit != false &&
                                        widget.title.text.trim().isNotEmpty)),
                            onPressed: _submit,
                            leading: state.busy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            child: Text(
                              state.taskId != null
                                  ? (state.files.isEmpty
                                        ? l10n.commonDone
                                        : l10n.filesRetry)
                                  : l10n.taskCreateAction,
                            ),
                          ),
                        ],
                      );
                      return constraints.maxWidth >= 720
                          ? Row(
                              children: [
                                Expanded(child: audience),
                                const SizedBox(width: 16),
                                Expanded(child: actions),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                audience,
                                const SizedBox(height: 12),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: actions,
                                ),
                              ],
                            );
                    },
                  ),
                ),
                const ShortcutHintsBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
