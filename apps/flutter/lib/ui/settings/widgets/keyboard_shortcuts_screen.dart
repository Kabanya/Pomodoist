// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadSwitch;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';
import 'package:pomodoist/domain/models/settings/app_shortcut.dart';
import 'package:pomodoist/ui/settings/view_models/keyboard_shortcuts_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

class KeyboardShortcutsScreen extends ConsumerStatefulWidget {
  const KeyboardShortcutsScreen({super.key});

  @override
  ConsumerState<KeyboardShortcutsScreen> createState() =>
      _KeyboardShortcutsScreenState();
}

class _KeyboardShortcutsScreenState
    extends ConsumerState<KeyboardShortcutsScreen> {
  late final TargetPlatform _targetPlatform;
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
    _targetPlatform = ref.read(keyboardShortcutsViewModelProvider).platform;
    if (_supportsGlobalShortcut) {
      unawaited(_loadGlobalShortcut());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final state = ref.watch(keyboardShortcutsViewModelProvider);
    final bindings = state.bindings;
    return SettingsSurface(
      child: ListView(
        key: const Key('keyboard-shortcuts-list'),
        padding: EdgeInsets.zero,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.commonBack,
                onPressed: () => _goBack(context),
                icon: const Icon(LucideIcons.arrowLeft),
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
          SettingsGroup(
            children: [
              for (final command in AppShortcutCommand.values)
                _ShortcutRow(
                  key: Key('shortcut-row-${command.storageKey}'),
                  title: appShortcutLabel(l10n, command),
                  shortcut: bindings[command]!.labelFor(_platform),
                  buttonKey: Key('shortcut-binding-${command.storageKey}'),
                  onTap: () => _recordAppShortcut(command),
                ),
              if (_supportsGlobalShortcut)
                _ShortcutRow(
                  key: const Key('shortcut-row-global'),
                  title: l10n.settingsShortcutsGlobalQuickAdd,
                  subtitle: state.global.registrationError == null
                      ? l10n.settingsShortcutsGlobalQuickAddSubtitle
                      : l10n.settingsShortcutsGlobalError,
                  shortcut: state.global.binding.labelFor(_platform),
                  loading: _loadingGlobalShortcut,
                  buttonKey: const Key('shortcut-binding-global'),
                  leading: ShadSwitch(
                    key: const Key('global-quick-add-enabled'),
                    enabled: !_loadingGlobalShortcut,
                    duration: AppMotion.duration(context, AppMotion.state),
                    value: state.global.enabled,
                    onChanged: _loadingGlobalShortcut
                        ? null
                        : _setGlobalQuickAddEnabled,
                  ),
                  onTap: !state.global.enabled ? null : _recordGlobalShortcut,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ShadButton.ghost(
              height: 48,
              key: const Key('shortcuts-reset-all'),
              onPressed: _resetAll,
              leading: const Icon(LucideIcons.rotateCcw),
              child: Text(l10n.settingsShortcutsResetAll),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGlobalShortcut() async {
    setState(() => _loadingGlobalShortcut = true);
    try {
      await ref
          .read(keyboardShortcutsViewModelProvider.notifier)
          .waitUntilReady();
    } on Object {
      // A missing native host leaves the macOS-only row unavailable.
    } finally {
      if (mounted) setState(() => _loadingGlobalShortcut = false);
    }
  }

  Future<void> _setGlobalQuickAddEnabled(bool enabled) async {
    try {
      await ref
          .read(keyboardShortcutsViewModelProvider.notifier)
          .setGlobalEnabled(enabled);
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
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
        reverseDuration: AppMotion.duration(context, AppMotion.popup),
        curve: AppMotion.curve,
      ),
      barrierDismissible: false,
      builder: (dialogContext) => _ShortcutRecorderDialog(
        onSubmit: (binding) async {
          final conflictMessage = context.l10n.settingsShortcutsConflict;
          final viewModel = ref.read(
            keyboardShortcutsViewModelProvider.notifier,
          );
          if (viewModel.conflictsWithZoom(binding)) return conflictMessage;
          if (viewModel.conflictsWithGlobal(binding)) {
            return conflictMessage;
          }
          final conflict = await viewModel.setBinding(command, binding);
          return conflict == null ? null : conflictMessage;
        },
      ),
    );
  }

  Future<void> _recordGlobalShortcut() {
    if (_platform != TargetPlatform.macOS) {
      return showDialog<void>(
        context: context,
        animationStyle: AnimationStyle(
          duration: AppMotion.duration(context, AppMotion.popup),
          reverseDuration: AppMotion.duration(context, AppMotion.popup),
          curve: AppMotion.curve,
        ),
        barrierDismissible: false,
        builder: (dialogContext) => _ShortcutRecorderDialog(
          onSubmit: (binding) async {
            final viewModel = ref.read(
              keyboardShortcutsViewModelProvider.notifier,
            );
            if (viewModel.conflictsWithZoom(binding)) {
              return context.l10n.settingsShortcutsConflict;
            }
            final candidate = viewModel.globalFromShortcut(binding);
            if (viewModel.conflictsWithApp(candidate)) {
              return context.l10n.settingsShortcutsConflict;
            }
            final globalError = context.l10n.settingsShortcutsGlobalError;
            try {
              await viewModel.setGlobalShortcut(candidate);
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
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
        reverseDuration: AppMotion.duration(context, AppMotion.popup),
        curve: AppMotion.curve,
      ),
      barrierDismissible: false,
      builder: (dialogContext) => _GlobalShortcutRecorderDialog(
        viewModel: ref.read(keyboardShortcutsViewModelProvider.notifier),
      ),
    );
  }

  Future<void> _resetAll() async {
    try {
      await ref.read(keyboardShortcutsViewModelProvider.notifier).resetAll();
    } on Object {
      if (_supportsGlobalShortcut) {
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
    if (!popped && context.mounted) context.go('/settings?section=general');
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
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      control: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          ?leading,
          if (loading)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            ShadButton.outline(
              key: buttonKey,
              height: 48,
              enabled: onTap != null,
              onPressed: onTap,
              child: Text(shortcut ?? '—', style: AppTheme.monoTextStyle),
            ),
        ],
      ),
    );
  }
}

class _ShortcutRecorderDialog extends StatefulWidget {
  const _ShortcutRecorderDialog({required this.onSubmit});

  final Future<String?> Function(ShortcutBinding binding) onSubmit;

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
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: AlertDialog(
        scrollable: true,
        constraints: const BoxConstraints(maxWidth: 560),
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
          ShadButton.ghost(
            height: 48,
            enabled: !_busy,
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
    final binding = shortcutBindingFromEvent(event, HardwareKeyboard.instance);
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
    final binding = shortcutBindingFromRawEvent(event);
    if (!binding.isValid) {
      setState(() => _error = context.l10n.settingsShortcutsInvalid);
      return;
    }
    unawaited(_submit(binding));
  }

  Future<void> _submit(ShortcutBinding binding) async {
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
  const _GlobalShortcutRecorderDialog({required this.viewModel});

  final KeyboardShortcutsViewModel viewModel;

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
      unawaited(widget.viewModel.cancelGlobalShortcutCapture());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      constraints: const BoxConstraints(maxWidth: 560),
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
      actions: [
        ShadButton.ghost(onPressed: _cancel, child: Text(l10n.commonCancel)),
      ],
    );
  }

  Future<void> _capture() async {
    while (mounted && !_finished) {
      try {
        final candidate = await widget.viewModel.captureGlobalShortcut();
        if (!mounted || _finished) return;
        if (widget.viewModel.conflictsWithApp(candidate)) {
          setState(() => _error = context.l10n.settingsShortcutsConflict);
          continue;
        }
        await widget.viewModel.setGlobalShortcut(candidate);
        if (!mounted || _finished) return;
        _finished = true;
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
      await widget.viewModel.cancelGlobalShortcutCapture();
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
