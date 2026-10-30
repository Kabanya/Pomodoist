import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_text_controller.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/label_icon.dart';

class QuickAddInput extends ConsumerStatefulWidget {
  const QuickAddInput({
    required this.controller,
    required this.decoration,
    this.textFieldKey,
    this.focusNode,
    this.style,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
    super.key,
  });

  final QuickAddTextController controller;
  final InputDecoration decoration;
  final Key? textFieldKey;
  final FocusNode? focusNode;
  final TextStyle? style;
  final int? maxLines;
  final bool autofocus;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  ConsumerState<QuickAddInput> createState() => _QuickAddInputState();
}

class _QuickAddInputState extends ConsumerState<QuickAddInput> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  TextEditingValue? _lastValueWithSuggestions;
  TextEditingValue? _valueBeforeSelection;
  String? _hiddenForText;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant QuickAddInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
      _hiddenForText = null;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputState = ref.watch(quickAddInputViewModelProvider);
    final viewModel = ref.read(quickAddInputViewModelProvider.notifier);
    final decoration = widget.decoration.copyWith(hintText: inputState.hint);
    return RawAutocomplete<QuickAddSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option.name,
      optionsBuilder: (value) {
        if (_hiddenForText == value.text) {
          _lastValueWithSuggestions = null;
          return const <QuickAddSuggestion>[];
        }
        final suggestions = viewModel.suggestions(value).toList();
        _lastValueWithSuggestions = suggestions.isEmpty ? null : value;
        return suggestions;
      },
      onSelected: _insertSuggestion,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return ShortcutHintsScope(
          enabled:
              widget.enabled &&
              _hiddenForText != controller.text &&
              viewModel.suggestions(controller.value).isNotEmpty,
          identity:
              _hiddenForText != controller.text &&
              viewModel.suggestions(controller.value).isNotEmpty,
          hints: [
            ShortcutHint(
              context.l10n.shortcutHintsAcceptSuggestion,
              'Enter / Tab',
            ),
            ShortcutHint(context.l10n.commonClose, 'Esc'),
          ],
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }
              final suggestions = viewModel.suggestions(controller.value);
              final hasSuggestions =
                  _hiddenForText != controller.text && suggestions.isNotEmpty;
              if (event.logicalKey == LogicalKeyboardKey.escape &&
                  hasSuggestions) {
                setState(() => _hiddenForText = controller.text);
                return KeyEventResult.handled;
              }
              if ((event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                      event.logicalKey == LogicalKeyboardKey.tab) &&
                  hasSuggestions) {
                _valueBeforeSelection = controller.value;
                onFieldSubmitted();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              key: widget.textFieldKey,
              controller: controller,
              focusNode: focusNode,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: widget.maxLines,
              style: widget.style,
              textInputAction: widget.textInputAction,
              decoration: decoration,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 220,
                minWidth: 220,
                maxWidth: 360,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final option = items[index];
                  final label = option.marker == '@'
                      ? inputState.labels
                            .where((item) => item.name == option.name)
                            .firstOrNull
                      : null;
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == index;
                  return ListTile(
                    key: ValueKey(
                      'quick-add-suggestion-${option.marker}${option.name}',
                    ),
                    dense: true,
                    leading: label == null
                        ? Text(option.marker)
                        : Semantics(
                            label: option.marker,
                            child: LabelIconView(label: label, size: 18),
                          ),
                    title: Text(option.name),
                    tileColor: highlighted
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    onTap: () {
                      _valueBeforeSelection = widget.controller.value;
                      onSelected(option);
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTextChanged() {
    if (_hiddenForText != null && _hiddenForText != widget.controller.text) {
      setState(() => _hiddenForText = null);
    }
  }

  void _insertSuggestion(QuickAddSuggestion suggestion) {
    final value =
        _valueBeforeSelection ??
        _lastValueWithSuggestions ??
        widget.controller.value;
    _valueBeforeSelection = null;
    final token = ActiveQuickAddToken.from(value);
    if (token == null) {
      return;
    }
    final replacement =
        '${suggestion.marker}${quickAddTokenValue(suggestion.name)} ';
    final text = value.text.replaceRange(token.start, token.end, replacement);
    final offset = token.start + replacement.length;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    _lastValueWithSuggestions = null;
    _hiddenForText = text;
    widget.onChanged?.call(text);
  }
}
