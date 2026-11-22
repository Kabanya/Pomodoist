part of 'quick_add_bar.dart';

int _taskCount(Iterable<DecomposedTaskDraft> tasks) {
  var count = 0;
  for (final task in tasks) {
    count += 1 + _taskCount(task.subtasks);
  }
  return count;
}

class _VoiceTaskDraftController {
  _VoiceTaskDraftController({
    required String quickAdd,
    String? description,
    List<DecomposedTaskDraft> subtasks = const [],
  }) : quickAdd = QuickAddTextController(text: quickAdd),
       description = TextEditingController(text: description ?? ''),
       subtasks = [
         for (final subtask in subtasks)
           _VoiceTaskDraftController(
             quickAdd: subtask.quickAdd,
             description: subtask.description,
             subtasks: subtask.subtasks,
           ),
       ];

  final QuickAddTextController quickAdd;
  final TextEditingController description;
  final List<_VoiceTaskDraftController> subtasks;

  void dispose() {
    quickAdd.dispose();
    description.dispose();
    for (final subtask in subtasks) {
      subtask.dispose();
    }
  }
}

class _TaskDraftList extends StatelessWidget {
  const _TaskDraftList({
    super.key,
    required this.controllers,
    required this.onChanged,
    required this.onRemove,
    this.defaultDate,
    this.projectId,
    this.priority,
    this.enabled = true,
  });

  final List<_VoiceTaskDraftController> controllers;
  final DateTime? defaultDate;
  final String? projectId;
  final int? priority;
  final bool enabled;
  final VoidCallback onChanged;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: controllers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          key: ValueKey(controllers[index]),
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.duration(context, AppMotion.task),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 6 * (1 - value)),
                child: child,
              ),
            );
          },
          child: _TaskDraftItem(
            controller: controllers[index],
            depth: 0,
            index: index,
            onChanged: onChanged,
            defaultDate: defaultDate,
            projectId: projectId,
            priority: priority,
            enabled: enabled,
            onRemove: () => onRemove(index),
          ),
        );
      },
    );
  }
}

class _TaskDraftItem extends ConsumerStatefulWidget {
  const _TaskDraftItem({
    super.key,
    required this.controller,
    required this.depth,
    required this.index,
    required this.onChanged,
    required this.onRemove,
    this.defaultDate,
    this.projectId,
    this.inheritedProjectName,
    this.reviewNumber,
    this.opened,
    this.onToggle,
    this.priority,
    this.enabled = true,
  });

  final _VoiceTaskDraftController controller;
  final DateTime? defaultDate;
  final String? projectId;
  final String? inheritedProjectName;
  final String? reviewNumber;
  final _VoiceTaskDraftController? opened;
  final ValueChanged<_VoiceTaskDraftController>? onToggle;
  final int? priority;
  final bool enabled;
  final int depth;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  ConsumerState<_TaskDraftItem> createState() => _TaskDraftItemState();
}

class _TaskDraftItemState extends ConsumerState<_TaskDraftItem> {
  bool _editing = false;
  bool _commentExpanded = false;
  final _commentKey = GlobalKey();
  final _titleFocus = FocusNode();

  @override
  void didUpdateWidget(_TaskDraftItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opened == widget.controller &&
        widget.opened != widget.controller) {
      _editing = false;
      _commentExpanded = false;
    }
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = ref.watch(
      voiceDraftViewModelProvider((
        widget.controller.quickAdd.text,
        widget.defaultDate,
      )),
    );
    final title = parsed.content.trim().isEmpty
        ? widget.controller.quickAdd.text.trim()
        : parsed.content;
    final horizontalOffset = widget.depth * 20.0;
    return Padding(
      padding: EdgeInsets.only(
        left: widget.reviewNumber != null
            ? (widget.depth > 0 ? 8 : 0)
            : horizontalOffset,
        top: widget.reviewNumber == null ? 8 : 0,
        bottom: widget.reviewNumber == null ? 8 : 0,
      ),
      child: Column(
        children: [
          if (widget.reviewNumber != null)
            _reviewRow(context, title)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_editing)
                  const Padding(
                    padding: EdgeInsets.only(top: 13, right: 8),
                    child: Icon(LucideIcons.circleCheck, size: 20),
                  ),
                Expanded(
                  child: _editing
                      ? _fields(context)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              key: ValueKey('voice-draft-open-${widget.index}'),
                              focusNode: _titleFocus,
                              onTap: widget.enabled
                                  ? () => setState(() => _editing = true)
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                              ),
                            ),
                            QuickAddDetails(
                              controller: widget.controller.quickAdd,
                              defaultDate: widget.defaultDate,
                              projectId: widget.projectId,
                              inheritedProjectName: widget.inheritedProjectName,
                              priority: widget.priority,
                              enabled: widget.enabled,
                              touchTargets: true,
                              onChanged: widget.onChanged,
                              trailing: _commentButton(),
                            ),
                            if (_commentExpanded) _commentField(),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: context.l10n.voiceRemoveTask,
                  onPressed: widget.enabled ? widget.onRemove : null,
                  icon: const Icon(LucideIcons.trash2),
                ),
              ],
            ),
            if (_editing)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _editing = false),
                  child: Text(context.l10n.commonDone),
                ),
              ),
          ],
          for (
            var childIndex = 0;
            childIndex < widget.controller.subtasks.length;
            childIndex++
          ) ...[
            _TaskDraftItem(
              key: ValueKey(widget.controller.subtasks[childIndex]),
              controller: widget.controller.subtasks[childIndex],
              depth: widget.depth + 1,
              reviewNumber: widget.reviewNumber == null
                  ? null
                  : '${widget.reviewNumber}.${childIndex + 1}',
              opened: widget.opened,
              onToggle: widget.onToggle,
              index: childIndex,
              onChanged: widget.onChanged,
              defaultDate: widget.defaultDate,
              projectId: parsed.project == null ? widget.projectId : null,
              inheritedProjectName:
                  parsed.project ?? widget.inheritedProjectName,
              priority: widget.priority,
              enabled: widget.enabled,
              onRemove: () {
                widget.controller.subtasks.removeAt(childIndex).dispose();
                widget.onChanged();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewRow(BuildContext context, String title) {
    final open = identical(widget.controller, widget.opened);
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: open ? colors.surfaceTint : colors.surface,
        borderRadius: open ? BorderRadius.circular(10) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              key: ValueKey('voice-review-${widget.reviewNumber}'),
              onTap: widget.enabled
                  ? () => widget.onToggle!(widget.controller)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        widget.reviewNumber!,
                        style: theme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Container(
                        height: 16,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: colors.border,
                      ),
                      Expanded(
                        child: Text(
                          title.isEmpty
                              ? l10n.voiceTaskLabel(widget.index + 1)
                              : title,
                          style: theme.bodyLarge?.copyWith(
                            fontWeight: open
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                        size: 18,
                        color: open ? colors.accent : colors.secondaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _editing
                            ? QuickAddInput(
                                controller: widget.controller.quickAdd,
                                focusNode: _titleFocus,
                                autofocus: true,
                                enabled: widget.enabled,
                                maxLines: 3,
                                onChanged: (_) => widget.onChanged(),
                                onSubmitted: (_) =>
                                    setState(() => _editing = false),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: colors.surface,
                                ),
                              )
                            : InkWell(
                                key: const Key('voice-review-edit-title'),
                                onTap: widget.enabled
                                    ? () => setState(() => _editing = true)
                                    : null,
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: colors.surface,
                                    isDense: true,
                                  ),
                                  child: Text(
                                    title.isEmpty
                                        ? l10n.voiceTaskLabel(widget.index + 1)
                                        : title,
                                    style: theme.bodyLarge,
                                  ),
                                ),
                              ),
                      ),
                      IconButton(
                        tooltip: l10n.voiceRemoveTask,
                        onPressed: widget.enabled ? widget.onRemove : null,
                        icon: const Icon(LucideIcons.trash2, size: 18),
                      ),
                    ],
                  ),
                  QuickAddDetails(
                    controller: widget.controller.quickAdd,
                    defaultDate: widget.defaultDate,
                    projectId: widget.projectId,
                    inheritedProjectName: widget.inheritedProjectName,
                    priority: widget.priority,
                    enabled: widget.enabled,
                    touchTargets: true,
                    reviewRows: true,
                    showWhenEmpty: true,
                    onChanged: widget.onChanged,
                    trailing: QuickAddDetailRow(
                      title: l10n.voiceReviewNote,
                      value: widget.controller.description.text,
                      icon: LucideIcons.notepadText,
                      expanded: _commentExpanded,
                      onPressed: widget.enabled
                          ? () => setState(
                              () => _commentExpanded = !_commentExpanded,
                            )
                          : null,
                    ),
                  ),
                  if (_commentExpanded) _commentField(),
                ],
              ),
            )
          else
            const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _fields(BuildContext context) {
    return Column(
      children: [
        QuickAddInput(
          controller: widget.controller.quickAdd,
          focusNode: _titleFocus,
          enabled: widget.enabled,
          maxLines: 3,
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(
            labelText: context.l10n.voiceTaskLabel(widget.index + 1),
            prefixIcon: Icon(
              widget.depth == 0
                  ? LucideIcons.circleCheck
                  : LucideIcons.cornerDownRight,
            ),
          ),
        ),
        QuickAddDetails(
          controller: widget.controller.quickAdd,
          defaultDate: widget.defaultDate,
          projectId: widget.projectId,
          inheritedProjectName: widget.inheritedProjectName,
          priority: widget.priority,
          enabled: widget.enabled,
          touchTargets: true,
          onChanged: widget.onChanged,
          trailing: _commentButton(),
        ),
        if (_commentExpanded) _commentField(),
      ],
    );
  }

  Widget _commentButton() => _QuickAddCommentButton(
    controller: widget.controller.description,
    expanded: _commentExpanded,
    enabled: widget.enabled,
    touchTargets: true,
    onPressed: () => setState(() => _commentExpanded = !_commentExpanded),
  );

  Widget _commentField() => _QuickAddCommentField(
    key: _commentKey,
    enabled: widget.enabled,
    controller: widget.controller.description,
    onChanged: widget.onChanged,
    onClose: () {
      setState(() => _commentExpanded = false);
      _titleFocus.requestFocus();
    },
  );
}
