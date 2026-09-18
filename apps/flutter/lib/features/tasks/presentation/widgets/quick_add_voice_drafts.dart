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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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

class _TaskDraftItem extends ConsumerWidget {
  const _TaskDraftItem({
    required this.controller,
    required this.depth,
    required this.index,
    required this.onChanged,
    required this.onRemove,
    this.defaultDate,
    this.projectId,
    this.inheritedProjectName,
    this.priority,
    this.enabled = true,
  });

  final _VoiceTaskDraftController controller;
  final DateTime? defaultDate;
  final String? projectId;
  final String? inheritedProjectName;
  final int? priority;
  final bool enabled;
  final int depth;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = ref
        .watch(quickAddParserProvider)
        .parse(
          controller.quickAdd.text,
          now: ref.read(clockProvider).now(),
          defaultDate: defaultDate,
        );
    final horizontalOffset = depth * 20.0;
    return Padding(
      padding: EdgeInsets.only(left: horizontalOffset),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fields(context)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: context.l10n.voiceRemoveTask,
                onPressed: enabled ? onRemove : null,
                icon: const Icon(LucideIcons.trash2),
              ),
            ],
          ),
          for (
            var childIndex = 0;
            childIndex < controller.subtasks.length;
            childIndex++
          ) ...[
            const SizedBox(height: 10),
            _TaskDraftItem(
              controller: controller.subtasks[childIndex],
              depth: depth + 1,
              index: childIndex,
              onChanged: onChanged,
              defaultDate: defaultDate,
              projectId: parsed.project == null ? projectId : null,
              inheritedProjectName: parsed.project ?? inheritedProjectName,
              priority: priority,
              enabled: enabled,
              onRemove: () {
                controller.subtasks.removeAt(childIndex).dispose();
                onChanged();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _fields(BuildContext context) {
    return Column(
      children: [
        QuickAddInput(
          controller: controller.quickAdd,
          enabled: enabled,
          maxLines: 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.l10n.voiceTaskLabel(index + 1),
            prefixIcon: Icon(
              depth == 0
                  ? LucideIcons.circleCheck
                  : LucideIcons.cornerDownRight,
            ),
          ),
        ),
        QuickAddDetails(
          controller: controller.quickAdd,
          defaultDate: defaultDate,
          projectId: projectId,
          inheritedProjectName: inheritedProjectName,
          priority: priority,
          enabled: enabled,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        TextField(
          enabled: enabled,
          controller: controller.description,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.l10n.taskComment,
            hintText: context.l10n.taskCommentHint,
            prefixIcon: const Icon(LucideIcons.alignLeft),
          ),
        ),
      ],
    );
  }
}
