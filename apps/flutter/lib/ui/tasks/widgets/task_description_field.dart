import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

/// Plain-text formatting stays portable in descriptions, exports and sync.
TextEditingValue formatTaskDescription(
  TextEditingValue value,
  String before,
  String after,
) {
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  final selected = value.text.substring(selection.start, selection.end);
  final replacement = before == '- '
      ? '- ${selected.replaceAll('\n', '\n- ')}'
      : '$before$selected$after';
  return TextEditingValue(
    text: value.text.replaceRange(selection.start, selection.end, replacement),
    selection: TextSelection(
      baseOffset: selection.start + before.length,
      extentOffset: selection.start + replacement.length - after.length,
    ),
  );
}

class TaskDescriptionField extends StatefulWidget {
  const TaskDescriptionField({
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.onChanged,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final ValueChanged<String>? onChanged;

  @override
  State<TaskDescriptionField> createState() => _TaskDescriptionFieldState();
}

class _TaskDescriptionFieldState extends State<TaskDescriptionField> {
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  void _format(String before, String after) {
    widget.controller.value = formatTaskDescription(
      widget.controller.value,
      before,
      after,
    );
    widget.onChanged?.call(widget.controller.text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget action(String label, IconData icon, String before, String after) =>
        IconButton(
          tooltip: label,
          onPressed: widget.enabled && !widget.readOnly
              ? () => _format(before, after)
              : null,
          icon: Icon(icon, size: 18),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.readOnly) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                children: [
                  action(l10n.taskFormatBold, LucideIcons.bold, '**', '**'),
                  action(l10n.taskFormatItalic, LucideIcons.italic, '*', '*'),
                  action(l10n.taskFormatList, LucideIcons.list, '- ', ''),
                  action(
                    l10n.taskFormatLink,
                    LucideIcons.link,
                    '[',
                    '](https://)',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.appColors.border),
          ],
          TextField(
            key: const Key('task-description-input'),
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            minLines: 4,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.7),
            decoration: InputDecoration(
              hintText: l10n.taskDescriptionHint,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.appColors.accent,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
