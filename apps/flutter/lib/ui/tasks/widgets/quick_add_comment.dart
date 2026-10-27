part of 'quick_add_bar.dart';

class _QuickAddCommentButton extends StatelessWidget {
  const _QuickAddCommentButton({
    required this.controller,
    required this.expanded,
    required this.enabled,
    required this.onPressed,
    this.touchTargets = false,
  });

  final TextEditingController controller;
  final bool expanded;
  final bool enabled;
  final VoidCallback onPressed;
  final bool touchTargets;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasComment = value.text.trim().isNotEmpty;
          final colors = context.appColors;
          final style = colors.quickAddStyle(colors.quickAddNoteColor);
          final foreground = style.color!;
          return Semantics(
            expanded: expanded,
            value: hasComment ? value.text.trim() : null,
            child: ShadButton.outline(
              key: const Key('quick-add-comment-toggle'),
              size: ShadButtonSize.sm,
              height: touchTargets ? 48 : 40,
              enabled: enabled,
              onPressed: enabled ? onPressed : null,
              foregroundColor: foreground,
              hoverForegroundColor: foreground,
              pressedForegroundColor: foreground,
              backgroundColor: style.backgroundColor,
              hoverBackgroundColor: colors.quickAddBackground(
                foreground,
                emphasized: true,
              ),
              pressedBackgroundColor: colors.quickAddBackground(
                foreground,
                emphasized: true,
              ),
              decoration: ShadDecoration(
                border: ShadBorder.all(
                  color: colors.quickAddBorder(foreground, active: expanded),
                  radius: BorderRadius.circular(8),
                ),
              ),
              leading: const Icon(LucideIcons.messageSquare, size: 18),
              trailing: hasComment
                  ? const Icon(LucideIcons.check, size: 14)
                  : null,
              child: Flexible(
                child: Text(
                  context.l10n.taskComment,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      );
}

class _QuickAddCommentField extends StatelessWidget {
  const _QuickAddCommentField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceTint,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            end: 4,
            bottom: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.messageSquare,
                    size: 16,
                    color: colors.secondaryText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.taskComment,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.commonClose,
                    onPressed: enabled ? onClose : null,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(LucideIcons.x, size: 16),
                  ),
                ],
              ),
              TextField(
                key: const Key('quick-add-comment-input'),
                controller: controller,
                enabled: enabled,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  hintText: context.l10n.taskCommentHint,
                  contentPadding: const EdgeInsets.all(8),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.accent, width: 2),
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
