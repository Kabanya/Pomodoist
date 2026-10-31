part of 'quick_add_bar.dart';

class _QuickAddCommentButton extends StatelessWidget {
  const _QuickAddCommentButton({
    required this.controller,
    required this.expanded,
    required this.enabled,
    required this.onPressed,
    this.touchTargets = false,
    this.iconsOnly = false,
  });

  final TextEditingController controller;
  final bool expanded;
  final bool enabled;
  final VoidCallback onPressed;
  final bool touchTargets;
  final bool iconsOnly;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      final hasComment = value.text.trim().isNotEmpty;
      final colors = context.appColors;
      final style = colors.quickAddStyle(colors.quickAddNoteColor);
      final foreground = style.color!;
      return Tooltip(
        message: hasComment
            ? '${context.l10n.taskComment}: ${value.text.trim()}'
            : context.l10n.taskComment,
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            label: iconsOnly ? context.l10n.taskComment : null,
            expanded: expanded,
            value: hasComment ? value.text.trim() : null,
            child: ShadButton.outline(
              key: const Key('quick-add-comment-toggle'),
              size: ShadButtonSize.sm,
              height: touchTargets ? 48 : 40,
              width: iconsOnly ? 40 : null,
              padding: iconsOnly ? EdgeInsets.zero : null,
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
              leading: iconsOnly && hasComment
                  ? Badge(
                      backgroundColor: foreground,
                      smallSize: 6,
                      child: const Icon(LucideIcons.messageSquare, size: 18),
                    )
                  : const Icon(LucideIcons.messageSquare, size: 18),
              trailing: hasComment && !iconsOnly
                  ? const Icon(LucideIcons.check, size: 14)
                  : null,
              child: iconsOnly
                  ? null
                  : Flexible(
                      child: Text(
                        context.l10n.taskComment,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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

  void _finish() {
    if (enabled && controller.value.composing.isCollapsed) onClose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!enabled ||
        event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        !controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (keyboard.isShiftPressed) {
      final value = controller.value;
      final range = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      controller.value = TextEditingValue(
        text: value.text.replaceRange(range.start, range.end, '\n'),
        selection: TextSelection.collapsed(offset: range.start + 1),
      );
      onChanged();
    } else {
      _finish();
    }
    return KeyEventResult.handled;
  }

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
              ShortcutHintsScope(
                hints: [ShortcutHint(context.l10n.commonDone, 'Enter')],
                enabled: enabled,
                child: Focus(
                  canRequestFocus: false,
                  onKeyEvent: _onKeyEvent,
                  child: TextField(
                    key: const Key('quick-add-comment-input'),
                    controller: controller,
                    enabled: enabled,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.done,
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (_) => onChanged(),
                    // Keep IME composition intact until completion is accepted.
                    onEditingComplete: () {},
                    onSubmitted: (_) => _finish(),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
