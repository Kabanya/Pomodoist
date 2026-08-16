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
  MacOSGlobalShortcut? _globalShortcut;
  bool _loadingGlobalShortcut = false;

  TargetPlatform get _platform => ref.read(shortcutTargetPlatformProvider);
  bool get _supportsGlobalShortcut =>
      !kIsWeb && _platform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_supportsGlobalShortcut) unawaited(_loadGlobalShortcut());
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
              title: _commandLabel(command),
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
              subtitle: l10n.settingsShortcutsGlobalQuickAddSubtitle,
              shortcut: _globalShortcut?.label,
              loading: _loadingGlobalShortcut,
              buttonKey: const Key('shortcut-binding-global'),
              onTap: _globalShortcut == null ? null : _recordGlobalShortcut,
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

  String _commandLabel(AppShortcutCommand command) {
    final l10n = context.l10n;
    return switch (command) {
      AppShortcutCommand.toggleSidebar => l10n.settingsShortcutsToggleSidebar,
      AppShortcutCommand.quickAdd => l10n.addTask,
      AppShortcutCommand.browse => l10n.navBrowse,
      AppShortcutCommand.search => l10n.navSearch,
      AppShortcutCommand.today => l10n.navToday,
      AppShortcutCommand.upcoming => l10n.navUpcoming,
      AppShortcutCommand.focus => l10n.navFocus,
      AppShortcutCommand.inbox => l10n.navInbox,
      AppShortcutCommand.priorityMatrix => l10n.navPriorityMatrix,
      AppShortcutCommand.timeline => l10n.navTimeline,
      AppShortcutCommand.kanban => l10n.navKanban,
      AppShortcutCommand.reports => l10n.navReports,
      AppShortcutCommand.settings => l10n.navSettings,
    };
  }

  Future<void> _loadGlobalShortcut() async {
    setState(() => _loadingGlobalShortcut = true);
    try {
      final shortcut = await ref
          .read(platformQuickAddControllerProvider)
          .getGlobalShortcut();
      if (mounted) setState(() => _globalShortcut = shortcut);
    } on Object {
      // A missing native host leaves the macOS-only row unavailable.
    } finally {
      if (mounted) setState(() => _loadingGlobalShortcut = false);
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
            .setGlobalShortcut(macOSDefaultGlobalShortcut);
        if (mounted) {
          setState(() => _globalShortcut = macOSDefaultGlobalShortcut);
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
    this.loading = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? shortcut;
  final Key buttonKey;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
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
