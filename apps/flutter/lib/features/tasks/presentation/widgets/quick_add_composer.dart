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

  @override
  ConsumerState<QuickAddComposer> createState() => _QuickAddComposerState();
}

class _QuickAddComposerState extends ConsumerState<QuickAddComposer> {
  final _controller = QuickAddTextController();
  bool _busy = false;

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
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: Focus(
        autofocus: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuickAddInput(
              textFieldKey: const Key('sidebar-quick-add-input'),
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.quickAddHint,
                prefixIcon: const Icon(LucideIcons.listPlus),
                suffixIcon: IconButton(
                  key: const Key('sidebar-quick-add-voice'),
                  tooltip: l10n.voiceQuickAdd,
                  onPressed: _busy ? null : _openVoiceSheet,
                  icon: const Icon(LucideIcons.mic),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            QuickAddDetails(
              controller: _controller,
              defaultDate: widget.defaultDate,
              projectId: widget.projectId,
              enabled: !_busy,
            ),
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                ShadButton.ghost(
                  enabled: !_busy,
                  onPressed: _busy ? null : _cancel,
                  child: Text(l10n.commonCancel),
                ),
                ShadButton(
                  key: const Key('sidebar-quick-add-submit'),
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
                  child: Text(l10n.commonAdd),
                ),
              ],
            ),
          ],
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
    setState(() => _busy = true);
    try {
      await ref
          .read(quickAddServiceProvider)
          .createTask(
            input,
            defaultDate: widget.defaultDate,
            projectId: widget.projectId,
            labelId: widget.labelId,
          );
      if (mounted) widget.onCompleted();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.taskCreateFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
