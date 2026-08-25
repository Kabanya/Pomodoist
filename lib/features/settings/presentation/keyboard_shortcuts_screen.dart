// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/keyboard_shortcuts.dart';
import '../../../app/platform_quick_add.dart';
import '../../../app/theme/app_theme.dart';

class KeyboardShortcutsScreen extends ConsumerStatefulWidget {
  const KeyboardShortcutsScreen({super.key});

  @override
  ConsumerState<KeyboardShortcutsScreen> createState() =>
      _KeyboardShortcutsScreenState();
}

class _KeyboardShortcutsScreenState
    extends ConsumerState<KeyboardShortcutsScreen> {
  late final TargetPlatform _targetPlatform;
  PlatformQuickAddController? _globalQuickAddController;
  GlobalQuickAddBinding? _globalShortcut;
  bool _globalQuickAddEnabled = true;
  Object? _globalQuickAddError;
  bool _loadingGlobalShortcut = false;

  TargetPlatform get _platform => _targetPlatform;
  bool get _supportsGlobalShortcut =>
      !kIsWeb &&
      const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(_platform);

  @override
  void initState() {
    super.initState();
    _targetPlatform = ref.read(shortcutTargetPlatformProvider);
    if (_supportsGlobalShortcut) {
      final controller = ref.read(platformQuickAddControllerProvider);
      _globalQuickAddController = controller;
      _globalShortcut = controller.state.binding;
      _globalQuickAddEnabled = controller.state.enabled;
      controller.addListener(_syncGlobalQuickAddState);
      unawaited(_loadGlobalShortcut());
    }
  }

  @override
  void dispose() {
    _globalQuickAddController?.removeListener(_syncGlobalQuickAddState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final bindings = ref.watch(keyboardShortcutsProvider);
    ref.watch(keyboardShortcutsLoadedProvider);
    return SafeArea(
      child: ListView(
        key: const Key('keyboard-shortcuts-list'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.commonBack,
                onPressed: () => _goBack(context),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.settingsShortcutsTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 54),
            child: Text(
              l10n.settingsShortcutsSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
            ),
          ),
          const SizedBox(height: 20),
          for (final command in AppShortcutCommand.values) ...[
            _ShortcutRow(
              key: Key('shortcut-row-${command.storageKey}'),
              title: appShortcutLabel(l10n, command),
              shortcut: bindings[command]!.labelFor(_platform),
              buttonKey: Key('shortcut-binding-${command.storageKey}'),
              onTap: () => _recordAppShortcut(command),
            ),
            const SizedBox(height: 8),
          ],
          if (_supportsGlobalShortcut) ...[
            _ShortcutRow(
              key: const Key('shortcut-row-global'),
              title: l10n.settingsShortcutsGlobalQuickAdd,
              subtitle: _globalQuickAddError == null
                  ? l10n.settingsShortcutsGlobalQuickAddSubtitle
                  : l10n.settingsShortcutsGlobalError,
              shortcut: _globalShortcut?.labelFor(_platform),
              loading: _loadingGlobalShortcut,
              buttonKey: const Key('shortcut-binding-global'),
              leading: Switch(
                key: const Key('global-quick-add-enabled'),
                value: _globalQuickAddEnabled,
                onChanged: _loadingGlobalShortcut
                    ? null
                    : _setGlobalQuickAddEnabled,
              ),
              onTap: !_globalQuickAddEnabled || _globalShortcut == null
                  ? null
                  : _recordGlobalShortcut,
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: const Key('shortcuts-reset-all'),
              onPressed: _resetAll,
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.settingsShortcutsResetAll),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGlobalShortcut() async {
    setState(() => _loadingGlobalShortcut = true);
    try {
      final controller = _globalQuickAddController!;
      await controller.ready;
      if (mounted) _syncGlobalQuickAddState();
    } on Object {
      // A missing native host leaves the macOS-only row unavailable.
    } finally {
      if (mounted) setState(() => _loadingGlobalShortcut = false);
    }
  }

  void _syncGlobalQuickAddState() {
    if (!mounted) return;
    final state = _globalQuickAddController!.state;
    setState(() {
      _globalShortcut = state.binding;
      _globalQuickAddEnabled = state.enabled;
      _globalQuickAddError = state.registrationError;
    });
  }

  Future<void> _setGlobalQuickAddEnabled(bool enabled) async {
    try {
      await ref
          .read(platformQuickAddControllerProvider)
          .setGlobalQuickAddEnabled(enabled);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsShortcutsGlobalError)),
        );
      }
    }
  }

  Future<void> _recordAppShortcut(AppShortcutCommand command) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ShortcutRecorderDialog(
        onSubmit: (binding) async {
          final conflictMessage = context.l10n.settingsShortcutsConflict;
          if (_globalShortcut?.displaySignature == binding.displaySignature) {
            return conflictMessage;
          }
          final conflict = await ref
              .read(keyboardShortcutsProvider.notifier)
              .setBinding(command, binding);
          return conflict == null ? null : conflictMessage;
        },
      ),
    );
  }

  Future<void> _recordGlobalShortcut() {
    if (_platform != TargetPlatform.macOS) {
      return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _ShortcutRecorderDialog(
          onSubmit: (binding) async {
            final candidate = GlobalQuickAddBinding(
              keyCode: binding.physicalKeyId,
              keyLabel: binding.keyLabel,
              meta: binding.meta,
              control: binding.control,
              alt: binding.alt,
              shift: binding.shift,
            );
            if (ref
                .read(keyboardShortcutsProvider)
                .values
                .any(
                  (binding) =>
                      binding.displaySignature == candidate.displaySignature,
                )) {
              return context.l10n.settingsShortcutsConflict;
            }
            final globalError = context.l10n.settingsShortcutsGlobalError;
            try {
              await ref
                  .read(platformQuickAddControllerProvider)
                  .setGlobalShortcut(candidate);
              if (mounted) setState(() => _globalShortcut = candidate);
              return null;
            } on Object {
              return globalError;
            }
          },
        ),
      );
    }
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _GlobalShortcutRecorderDialog(
        controller: ref.read(platformQuickAddControllerProvider),
        hasConflict: (candidate) => ref
            .read(keyboardShortcutsProvider)
            .values
            .any(
              (binding) =>
                  binding.displaySignature == candidate.displaySignature,
            ),
        onSaved: (shortcut) {
          if (mounted) setState(() => _globalShortcut = shortcut);
        },
      ),
    );
  }

  Future<void> _resetAll() async {
    await ref.read(keyboardShortcutsProvider.notifier).resetAll();
    if (_supportsGlobalShortcut) {
      try {
        await ref
            .read(platformQuickAddControllerProvider)
            .setGlobalShortcut(GlobalQuickAddBinding.defaultFor(_platform));
        if (mounted) {
          setState(
            () => _globalShortcut = GlobalQuickAddBinding.defaultFor(_platform),
          );
        }
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.settingsShortcutsGlobalError)),
          );
        }
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsShortcutsResetDone)),
      );
    }
  }

  Future<void> _goBack(BuildContext context) async {
    final popped = await Navigator.of(context).maybePop();
    if (!popped && context.mounted) context.go('/settings');
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.title,
    required this.shortcut,
    required this.buttonKey,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.loading = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? shortcut;
  final Widget? leading;
  final Key buttonKey;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton(
                key: buttonKey,
                onPressed: onTap,
                child: Text(shortcut ?? '—'),
              ),
        onTap: onTap,
      ),
    );
  }
}

class _ShortcutRecorderDialog extends StatefulWidget {
  const _ShortcutRecorderDialog({required this.onSubmit});

  final Future<String?> Function(AppShortcutBinding binding) onSubmit;

  @override
  State<_ShortcutRecorderDialog> createState() =>
      _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<_ShortcutRecorderDialog> {
  final _focusNode = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    RawKeyboard.instance.addListener(_handleRawKeyEvent);
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_handleRawKeyEvent);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AlertDialog(
        key: const Key('shortcut-recorder-dialog'),
        title: Text(l10n.settingsShortcutsRecordTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsShortcutsRecordPrompt),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _busy) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return;
    }
    if (_modifierKeys.contains(event.logicalKey)) return;
    final binding = AppShortcutBinding.fromEvent(
      event,
      HardwareKeyboard.instance,
    );
    if (!binding.isValid) {
      setState(() => _error = context.l10n.settingsShortcutsInvalid);
      return;
    }
    unawaited(_submit(binding));
  }

  void _handleRawKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || event.repeat || _busy) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _busy = true;
      Navigator.of(context).pop();
      return;
    }
    if (_modifierKeys.contains(event.logicalKey)) return;
    final binding = AppShortcutBinding.fromRawEvent(event);
    if (!binding.isValid) {
      setState(() => _error = context.l10n.settingsShortcutsInvalid);
      return;
    }
    unawaited(_submit(binding));
  }

  Future<void> _submit(AppShortcutBinding binding) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(binding);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }
}

class _GlobalShortcutRecorderDialog extends StatefulWidget {
  const _GlobalShortcutRecorderDialog({
    required this.controller,
    required this.hasConflict,
    required this.onSaved,
  });

  final PlatformQuickAddController controller;
  final bool Function(MacOSGlobalShortcut shortcut) hasConflict;
  final ValueChanged<MacOSGlobalShortcut> onSaved;

  @override
  State<_GlobalShortcutRecorderDialog> createState() =>
      _GlobalShortcutRecorderDialogState();
}

class _GlobalShortcutRecorderDialogState
    extends State<_GlobalShortcutRecorderDialog> {
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_capture());
  }

  @override
  void dispose() {
    if (!_finished) {
      unawaited(widget.controller.cancelGlobalShortcutCapture());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: const Key('shortcut-recorder-dialog'),
      title: Text(l10n.settingsShortcutsRecordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsShortcutsRecordPrompt),
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [TextButton(onPressed: _cancel, child: Text(l10n.commonCancel))],
    );
  }

  Future<void> _capture() async {
    while (mounted && !_finished) {
      try {
        final candidate = await widget.controller.captureGlobalShortcut();
        if (!mounted || _finished) return;
        if (widget.hasConflict(candidate)) {
          setState(() => _error = context.l10n.settingsShortcutsConflict);
          continue;
        }
        await widget.controller.setGlobalShortcut(candidate);
        if (!mounted || _finished) return;
        _finished = true;
        widget.onSaved(candidate);
        Navigator.of(context).pop();
        return;
      } on PlatformException catch (error) {
        if (!mounted || _finished) {
          return;
        }
        if (error.code == 'shortcut_capture_cancelled') {
          _finished = true;
          Navigator.of(context).pop();
          return;
        }
        setState(
          () => _error = error.code == 'invalid_shortcut'
              ? context.l10n.settingsShortcutsInvalid
              : context.l10n.settingsShortcutsGlobalError,
        );
      }
    }
  }

  Future<void> _cancel() async {
    if (_finished) return;
    _finished = true;
    try {
      await widget.controller.cancelGlobalShortcutCapture();
    } on Object {
      // Cancellation is best effort while the dialog is closing.
    }
    if (mounted) Navigator.of(context).pop();
  }
}

final _modifierKeys = {
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.fnLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
  LogicalKeyboardKey.symbol,
  LogicalKeyboardKey.symbolLock,
};
