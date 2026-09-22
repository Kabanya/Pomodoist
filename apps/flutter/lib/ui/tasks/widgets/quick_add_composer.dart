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
    this.onVoiceSessionChanged,
    this.compact = false,
    super.key,
  });

  final VoidCallback onCompleted;
  final VoidCallback onCancel;
  final String initialText;
  final DateTime? defaultDate;
  final String? projectId;
  final String? labelId;
  final ValueChanged<bool>? onVoiceModeChanged;
  final ValueChanged<bool>? onVoiceSessionChanged;
  final bool compact;

  @override
  ConsumerState<QuickAddComposer> createState() => _QuickAddComposerState();
}

class _QuickAddComposerState extends ConsumerState<QuickAddComposer> {
  final _controller = QuickAddTextController();
  final _identity = Object();
  final _inputKey = GlobalKey();
  bool get _busy =>
      ref.read(quickAddViewModelProvider(_identity)).result.isLoading;

  void _syncDraft() => ref
      .read(quickAddViewModelProvider(_identity).notifier)
      .updateDraft(_controller.text);

  @override
  void initState() {
    super.initState();
    _controller.value = TextEditingValue(
      text: widget.initialText,
      selection: TextSelection.collapsed(offset: widget.initialText.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      quickAddViewModelProvider(_identity).select((state) => state.result),
    );
    final l10n = context.l10n;
    final input = QuickAddInput(
      key: _inputKey,
      textFieldKey: const Key('sidebar-quick-add-input'),
      controller: _controller,
      enabled: !_busy,
      autofocus: true,
      maxLines: 4,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 400)],
        color: context.appColors.primaryText.withValues(alpha: .45),
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
      onChanged: _syncDraft,
    );
    final submit = ShadButton(
      key: const Key('sidebar-quick-add-submit'),
      height: widget.compact ? 48 : 40,
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
      trailing: widget.compact
          ? null
          : const Icon(LucideIcons.cornerDownLeft, size: 16),
      child: Text(l10n.commonAdd),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
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
                                constraints: const BoxConstraints.tightFor(
                                  width: 48,
                                  height: 48,
                                ),
                                icon: const Icon(LucideIcons.x),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          input,
                          details,
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
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.listPlus,
                              color: context.appColors.secondaryText,
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: input),
                            const SizedBox(width: 16),
                            Tooltip(
                              message: l10n.voiceQuickAdd,
                              child: ShadButton.outline(
                                key: const Key('sidebar-quick-add-voice'),
                                width: 40,
                                height: 40,
                                padding: EdgeInsets.zero,
                                enabled: !_busy,
                                onPressed: _busy ? null : _openVoiceSheet,
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
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 12,
                        overflowSpacing: 12,
                        children: [details, submit],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _cancel() {
    if (!_busy) widget.onCancel();
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
