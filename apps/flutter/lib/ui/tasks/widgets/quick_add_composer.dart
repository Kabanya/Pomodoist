part of 'quick_add_bar.dart';

class QuickAddComposer extends ConsumerStatefulWidget {
  const QuickAddComposer({
    required this.onCompleted,
    required this.onCancel,
    this.initialText = '',
    this.defaultDate,
    this.projectId,
    this.labelId,
    this.onVoiceModeChanged,
    this.onEditorModeChanged,
    this.onCommentExpandedChanged,
    this.onVoiceSessionChanged,
    this.onPreferredWidthChanged,
    this.compact = false,
    this.focusNode,
    super.key,
  });

  final VoidCallback onCompleted;
  final VoidCallback onCancel;
  final String initialText;
  final DateTime? defaultDate;
  final String? projectId;
  final String? labelId;
  final ValueChanged<bool>? onVoiceModeChanged;
  final Future<void> Function(bool)? onEditorModeChanged;
  final ValueChanged<bool>? onCommentExpandedChanged;
  final ValueChanged<bool>? onVoiceSessionChanged;
  final ValueChanged<double>? onPreferredWidthChanged;
  final bool compact;
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
  final _ownedInputFocus = FocusNode();
  FocusNode get _inputFocus => widget.focusNode ?? _ownedInputFocus;
  bool _editorOpen = false;
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
    final details = QuickAddDetails(
      controller: _controller,
      defaultDate: widget.defaultDate,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _cancel,
              },
              child: Focus(
                child: widget.compact
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: context.appColors.border,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Semantics(
                                          namesRoute: true,
                                          header: true,
                                          child: Text(
                                            l10n.addTask,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: l10n.commonClose,
                                        onPressed: _busy ? null : _cancel,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 48,
                                              height: 48,
                                            ),
                                        icon: const Icon(LucideIcons.x),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      IconButton(
                                        tooltip: l10n.taskExpandEditor,
                                        onPressed: _busy ? null : _openEditor,
                                        icon: const Icon(LucideIcons.listPlus),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: input),
                                    ],
                                  ),
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
                      )
                    : Semantics(
                        scopesRoute: true,
                        namesRoute: true,
                        explicitChildNodes: true,
                        label: l10n.addTask,
                        child: Column(
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
                                  children: [
                                    IconButton(
                                      key: const Key('quick-add-open-editor'),
                                      tooltip: l10n.taskExpandEditor,
                                      onPressed: _busy ? null : _openEditor,
                                      icon: Icon(
                                        LucideIcons.listPlus,
                                        color: context.appColors.secondaryText,
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
                            Divider(height: 1, color: context.appColors.border),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: footerMaxHeight,
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: math.min(
                                    12,
                                    (footerMaxHeight - 40) / 2,
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
                        ),
                      ),
              ),
            ),
          ),
          const ShortcutHintsBar(),
        ],
      ),
    );
  }

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
        defaultDate: widget.defaultDate,
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
          defaultDate: widget.defaultDate,
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
