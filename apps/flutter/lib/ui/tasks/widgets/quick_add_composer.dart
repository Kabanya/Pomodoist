part of 'quick_add_bar.dart';

class QuickAddComposer extends ConsumerStatefulWidget {
  const QuickAddComposer({
    required this.onCompleted,
    required this.onCancel,
    this.initialText = '',
    this.defaultDate,
    this.dateInText = false,
    this.projectId,
    this.labelId,
    this.onVoiceModeChanged,
    this.onEditorModeChanged,
    this.onCommentExpandedChanged,
    this.onVoiceSessionChanged,
    this.onPreferredWidthChanged,
    this.onHeightRequirementsChanged,
    this.compact = false,
    this.expanded = false,
    this.onExpand,
    this.focusNode,
    super.key,
  });

  final VoidCallback onCompleted;
  final VoidCallback onCancel;
  final String initialText;
  final DateTime? defaultDate;
  final bool dateInText;
  final String? projectId;
  final String? labelId;
  final ValueChanged<bool>? onVoiceModeChanged;
  final Future<void> Function(bool)? onEditorModeChanged;
  final ValueChanged<bool>? onCommentExpandedChanged;
  final ValueChanged<bool>? onVoiceSessionChanged;
  final ValueChanged<double>? onPreferredWidthChanged;
  final void Function(double preferredHeight, double minimumHeight)?
  onHeightRequirementsChanged;
  final bool compact;
  final bool expanded;
  final VoidCallback? onExpand;
  final FocusNode? focusNode;

  @override
  ConsumerState<QuickAddComposer> createState() => _QuickAddComposerState();
}

class _QuickAddComposerState extends ConsumerState<QuickAddComposer> {
  final _controller = QuickAddTextController();
  final _commentController = TextEditingController();
  final _commentKey = GlobalKey();
  bool _commentExpanded = false;
  bool _hasComment = false;
  double _metadataWidth = 0;
  final _identity = Object();
  final _inputKey = GlobalKey();
  final _inputRowKey = GlobalKey();
  final _detailsKey = GlobalKey();
  final _hintsKey = GlobalKey();
  final _ownedInputFocus = FocusNode();
  FocusNode get _inputFocus => widget.focusNode ?? _ownedInputFocus;
  DateTime? get _textDefaultDate =>
      widget.dateInText ? null : widget.defaultDate;
  bool _editorOpen = false;
  Offset _headerDrag = Offset.zero;
  bool get _busy =>
      _editorOpen ||
      ref.read(quickAddViewModelProvider(_identity)).result.isLoading;

  void _syncDraft() => ref
      .read(quickAddViewModelProvider(_identity).notifier)
      .updateDraft(_controller.text, description: _commentController.text);

  @override
  void initState() {
    super.initState();
    _commentController.addListener(() {
      final hasComment = _commentController.text.trim().isNotEmpty;
      if (hasComment != _hasComment) setState(() => _hasComment = hasComment);
    });
    _controller.value = TextEditingValue(
      text: widget.initialText,
      selection: TextSelection.collapsed(offset: widget.initialText.length),
    );
  }

  @override
  void dispose() {
    _ownedInputFocus.dispose();
    _controller.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      quickAddViewModelProvider(_identity).select((state) => state.result),
    );
    return LayoutBuilder(builder: _buildComposer);
  }

  Widget _buildComposer(BuildContext context, BoxConstraints constraints) {
    final l10n = context.l10n;
    final theme = ShadTheme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final labeledWidth =
        _metadataWidth +
        quickAddLabeledButtonWidth(
          l10n.taskComment,
          theme: theme,
          textScaler: textScaler,
          textDirection: direction,
          trailingWidth: _hasComment ? 14 : 0,
        ) +
        quickAddLabeledButtonWidth(
          l10n.commonAdd,
          theme: theme,
          textScaler: textScaler,
          textDirection: direction,
          primary: true,
          trailingWidth: 16,
        ) +
        8 +
        12 +
        48;
    final iconsOnly =
        !widget.compact &&
        _metadataWidth > 0 &&
        quickAddToolbarUsesIcons(constraints.maxWidth, labeledWidth);
    if (!widget.compact &&
        _metadataWidth > 0 &&
        widget.onPreferredWidthChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPreferredWidthChanged?.call(labeledWidth);
      });
    }
    final footerMaxHeight = math.max(
      40.0,
      math.min(160.0, constraints.maxHeight * .45),
    );
    final input = QuickAddInput(
      key: _inputKey,
      focusNode: _inputFocus,
      textFieldKey: const Key('sidebar-quick-add-input'),
      controller: _controller,
      enabled: !_busy,
      autofocus: true,
      maxLines: 4,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 400)],
        color: context.appColors.primaryText,
      ),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: l10n.quickAddHint,
        hintStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w300,
          fontVariations: const [FontVariation('wght', 300)],
          color: context.appColors.secondaryText.withValues(alpha: .65),
        ),
        hintMaxLines: 2,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: context.appColors.accent),
        ),
        disabledBorder: InputBorder.none,
      ),
      onChanged: (_) => _syncDraft(),
      onSubmitted: (_) => _submit(),
    );
    if (!widget.compact && widget.onHeightRequirementsChanged != null) {
      final painter = TextPainter(
        text: TextSpan(text: ' ', style: input.style),
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      final minimumInputHeight = math.max(48.0, painter.height + 24) + 24;
      painter.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _editorOpen) return;
        final rowHeight = _inputRowKey.currentContext?.size?.height;
        final detailsHeight = _detailsKey.currentContext?.size?.height;
        final hintsHeight = _hintsKey.currentContext?.size?.height;
        if (rowHeight == null || detailsHeight == null || hintsHeight == null) {
          return;
        }
        final footerHeight = math.min(
          160.0,
          math.max(40.0, detailsHeight) + 24,
        );
        // The footer takes at most 45%; comments share the remaining flex space.
        final minimumHeight =
            math.max(
              minimumInputHeight * (_commentExpanded ? 2 : 1) +
                  1 +
                  footerHeight,
              footerHeight / .45,
            ) +
            hintsHeight;
        widget.onHeightRequirementsChanged?.call(
          math.max(rowHeight + 24 + 1 + footerHeight, footerHeight / .45) +
              hintsHeight,
          minimumHeight,
        );
      });
    }
    final details = QuickAddDetails(
      key: _detailsKey,
      controller: _controller,
      defaultDate: _textDefaultDate,
      projectId: widget.projectId,
      enabled: !_busy,
      touchTargets: widget.compact,
      desktop: !widget.compact,
      iconsOnly: iconsOnly,
      onNaturalWidthChanged: widget.compact
          ? null
          : (width) {
              if (mounted && width != _metadataWidth) {
                setState(() => _metadataWidth = width);
              }
            },
      onChanged: _syncDraft,
      trailing: _QuickAddCommentButton(
        controller: _commentController,
        expanded: _commentExpanded,
        enabled: !_busy,
        touchTargets: widget.compact,
        iconsOnly: iconsOnly,
        onPressed: _toggleComment,
      ),
    );
    final comment = _QuickAddCommentField(
      key: _commentKey,
      controller: _commentController,
      enabled: !_busy,
      onChanged: _syncDraft,
      onClose: _toggleComment,
    );
    final submit = Tooltip(
      message: l10n.commonAdd,
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          label: iconsOnly ? l10n.commonAdd : null,
          child: ShadButton(
            key: const Key('sidebar-quick-add-submit'),
            width: iconsOnly ? 40 : null,
            height: widget.compact ? 48 : 40,
            padding: iconsOnly ? EdgeInsets.zero : null,
            enabled: !_busy,
            onPressed: _busy ? null : _submit,
            leading: _busy
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.appColors.onAccent,
                    ),
                  )
                : const Icon(LucideIcons.plus),
            trailing: widget.compact || iconsOnly
                ? null
                : const Icon(LucideIcons.cornerDownLeft, size: 16),
            child: iconsOnly ? null : Text(l10n.commonAdd),
          ),
        ),
      ),
    );
    return ShortcutHintsScope(
      modal: true,
      identity: _busy,
      hints: [
        if (!_busy) ShortcutHint(context.l10n.commonClose, 'Esc'),
        if (!_busy) ShortcutHint(context.l10n.commonAdd, 'Enter'),
      ],
      child: Column(
        mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Flexible(
            fit: widget.expanded ? FlexFit.tight : FlexFit.loose,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _cancel,
              },
              child: Focus(
                child: widget.compact
                    ? Semantics(
                        scopesRoute: true,
                        namesRoute: true,
                        explicitChildNodes: true,
                        label: l10n.addTask,
                        child: Column(
                          mainAxisSize: widget.expanded
                              ? MainAxisSize.max
                              : MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _compactHeader(),
                            Flexible(
                              fit: widget.expanded
                                  ? FlexFit.tight
                                  : FlexFit.loose,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    input,
                                    details,
                                    if (_commentExpanded) comment,
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Tooltip(
                                    message: l10n.voiceQuickAdd,
                                    child: ShadButton.secondary(
                                      key: const Key('sidebar-quick-add-voice'),
                                      width: 48,
                                      height: 48,
                                      padding: EdgeInsets.zero,
                                      enabled: !_busy,
                                      onPressed: _busy ? null : _openVoiceSheet,
                                      child: Icon(
                                        LucideIcons.mic,
                                        semanticLabel: l10n.voiceQuickAdd,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: submit),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Semantics(
                        scopesRoute: true,
                        namesRoute: true,
                        explicitChildNodes: true,
                        label: l10n.addTask,
                        child: LayoutBuilder(
                          builder: (context, available) {
                            final footerHeight = math.min(
                              footerMaxHeight,
                              math.max(0.0, available.maxHeight - 1),
                            );
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Flexible(
                                  flex: 2,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      key: _inputRowKey,
                                      children: [
                                        IconButton(
                                          key: const Key(
                                            'quick-add-open-editor',
                                          ),
                                          tooltip: l10n.taskExpandEditor,
                                          onPressed: _busy ? null : _openEditor,
                                          icon: Icon(
                                            LucideIcons.listPlus,
                                            color:
                                                context.appColors.secondaryText,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(child: input),
                                        const SizedBox(width: 16),
                                        Tooltip(
                                          message: l10n.voiceQuickAdd,
                                          child: ShadButton.outline(
                                            key: const Key(
                                              'sidebar-quick-add-voice',
                                            ),
                                            width: 40,
                                            height: 40,
                                            padding: EdgeInsets.zero,
                                            enabled: !_busy,
                                            onPressed: _busy
                                                ? null
                                                : _openVoiceSheet,
                                            child: Icon(
                                              LucideIcons.mic,
                                              semanticLabel: l10n.voiceQuickAdd,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: context.appColors.border,
                                ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: footerHeight,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: math.min(
                                        12,
                                        math.max(0.0, (footerHeight - 40) / 2),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: SingleChildScrollView(
                                            child: details,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        submit,
                                      ],
                                    ),
                                  ),
                                ),
                                if (_commentExpanded)
                                  Flexible(
                                    flex: 2,
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      child: comment,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ),
          ),
          NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              if (widget.onHeightRequirementsChanged != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              }
              return false;
            },
            child: SizeChangedLayoutNotifier(
              child: ShortcutHintsBar(
                key: _hintsKey,
                reserveSpace:
                    widget.compact ||
                    widget.onHeightRequirementsChanged == null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _expand() {
    if (!_busy && !widget.expanded) widget.onExpand?.call();
  }

  Widget _compactHeader() => Listener(
    key: const Key('quick-add-sheet-header'),
    // Accepted pointer cancellations can also produce a recognizer drag end.
    onPointerCancel: (_) => _headerDrag = Offset.zero,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      excludeFromSemantics: true,
      onPanStart: (_) => _headerDrag = Offset.zero,
      onPanUpdate: (details) => _headerDrag += details.delta,
      onPanCancel: () => _headerDrag = Offset.zero,
      onPanEnd: (_) {
        final delta = _headerDrag;
        _headerDrag = Offset.zero;
        if (delta.dy.abs() < 48 || delta.dy.abs() <= delta.dx.abs()) return;
        if (delta.dy > 0) {
          _cancel();
        } else {
          _expand();
        }
      },
      child: SizedBox(
        height: 48,
        child: Stack(
          children: [
            Center(
              child: Semantics(
                key: const Key('quick-add-sheet-expand'),
                button: true,
                expanded: widget.expanded,
                enabled: !_busy && !widget.expanded && widget.onExpand != null,
                label: context.l10n.taskExpandEditor,
                onTap: !_busy && !widget.expanded && widget.onExpand != null
                    ? _expand
                    : null,
                child: InkWell(
                  onTap: !_busy && !widget.expanded && widget.onExpand != null
                      ? _expand
                      : null,
                  excludeFromSemantics: true,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.appColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: 20,
              top: 0,
              child: IconButton(
                tooltip: context.l10n.commonClose,
                onPressed: _busy ? null : _cancel,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                icon: const Icon(LucideIcons.x),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _toggleComment() {
    setState(() => _commentExpanded = !_commentExpanded);
    widget.onCommentExpandedChanged?.call(_commentExpanded);
    if (!_commentExpanded) _inputFocus.requestFocus();
  }

  void _cancel() {
    if (!_busy) widget.onCancel();
  }

  Future<void> _openEditor() async {
    if (_busy) return;
    _inputFocus.unfocus();
    setState(() => _editorOpen = true);
    String? task;
    try {
      await widget.onEditorModeChanged?.call(true);
      if (!mounted) return;
      task = await showTaskCreateDialog(
        context,
        title: _controller,
        description: _commentController,
        defaultDate: _textDefaultDate,
        projectId: widget.projectId,
        labelId: widget.labelId,
      );
    } finally {
      await widget.onEditorModeChanged?.call(false);
      if (mounted) setState(() => _editorOpen = false);
    }
    if (!mounted) return;
    _syncDraft();
    if (task != null) {
      widget.onCompleted();
    } else {
      _inputFocus.requestFocus();
    }
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;
    _syncDraft();
    final task = await ref
        .read(quickAddViewModelProvider(_identity).notifier)
        .submit(
          defaultDate: _textDefaultDate,
          projectId: widget.projectId,
          labelId: widget.labelId,
        );
    if (!mounted) return;
    if (task != null) {
      widget.onCompleted();
    } else if (ref.read(quickAddViewModelProvider(_identity)).result.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
    }
  }

  Future<void> _openVoiceSheet() async {
    widget.onVoiceSessionChanged?.call(true);
    final created = await showVoiceQuickAddSheet(
      context,
      ref,
      defaultDate: widget.defaultDate,
      projectId: widget.projectId,
      labelId: widget.labelId,
      onExpandedChanged: (expanded) {
        if (mounted) widget.onVoiceModeChanged?.call(expanded);
      },
    );
    if (!mounted) return;
    widget.onVoiceSessionChanged?.call(false);
    if (created != null && created.isNotEmpty) widget.onCompleted();
  }
}
