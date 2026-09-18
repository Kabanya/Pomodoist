part of 'quick_add_bar.dart';

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
    final projects = ref.watch(projectsProvider).value ?? const <ProjectItem>[];
    final labels = ref.watch(labelsProvider).value ?? const <LabelItem>[];
    final hint = ref.watch(quickAddHintTextProvider);
    final decoration = hint == null
        ? widget.decoration
        : widget.decoration.copyWith(hintText: hint);
    return RawAutocomplete<_QuickAddSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option.name,
      optionsBuilder: (value) {
        if (_hiddenForText == value.text) {
          _lastValueWithSuggestions = null;
          return const <_QuickAddSuggestion>[];
        }
        final suggestions = _suggestions(value, projects, labels).toList();
        _lastValueWithSuggestions = suggestions.isEmpty ? null : value;
        return suggestions;
      },
      onSelected: _insertSuggestion,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) {
              return KeyEventResult.ignored;
            }
            final suggestions = _suggestions(
              controller.value,
              projects,
              labels,
            );
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
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == index;
                  return ListTile(
                    key: ValueKey(
                      'quick-add-suggestion-${option.marker}${option.name}',
                    ),
                    dense: true,
                    leading: Text(option.marker),
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

  Iterable<_QuickAddSuggestion> _suggestions(
    TextEditingValue value,
    List<ProjectItem> projects,
    List<LabelItem> labels,
  ) {
    final token = _ActiveQuickAddToken.from(value);
    if (token == null) {
      return const <_QuickAddSuggestion>[];
    }
    final query = token.query.toLowerCase();
    final names = isQuickAddProjectMarker(token.marker)
        ? projects
              .where(
                (project) =>
                    project.id != inboxProjectId && !project.isArchived,
              )
              .map((project) => project.name)
        : labels.map((label) => label.name);
    return names
        .where((name) => name.toLowerCase().startsWith(query))
        .take(6)
        .map((name) => _QuickAddSuggestion(token.marker, name));
  }

  void _insertSuggestion(_QuickAddSuggestion suggestion) {
    final value =
        _valueBeforeSelection ??
        _lastValueWithSuggestions ??
        widget.controller.value;
    _valueBeforeSelection = null;
    final token = _ActiveQuickAddToken.from(value);
    if (token == null) {
      return;
    }
    final replacement =
        '${suggestion.marker}${_quickAddTokenValue(suggestion.name)} ';
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

class _ActiveQuickAddToken {
  const _ActiveQuickAddToken({
    required this.marker,
    required this.query,
    required this.start,
    required this.end,
  });

  final String marker;
  final String query;
  final int start;
  final int end;

  static _ActiveQuickAddToken? from(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final text = value.text;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      return null;
    }
    var start = cursor;
    while (start > 0 && text[start - 1].trim().isNotEmpty) {
      start--;
    }
    var end = cursor;
    while (end < text.length && text[end].trim().isNotEmpty) {
      end++;
    }
    final beforeCursor = text.substring(start, cursor);
    if (beforeCursor.isEmpty) {
      return null;
    }
    final marker = beforeCursor[0];
    if (!isQuickAddProjectMarker(marker) && marker != '@') {
      return null;
    }
    final query = beforeCursor.length > 1 && beforeCursor[1] == '"'
        ? beforeCursor.substring(2)
        : beforeCursor.substring(1);
    return _ActiveQuickAddToken(
      marker: marker,
      query: query,
      start: start,
      end: end,
    );
  }
}

class _QuickAddSuggestion {
  const _QuickAddSuggestion(this.marker, this.name);

  final String marker;
  final String name;
}

String _quickAddTokenValue(String name) {
  return RegExp(r'[\s"\\]').hasMatch(name)
      ? quickAddQuotedMetadataValue(name)
      : name;
}
