import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/domain/models/settings/app_shortcut.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/view_models/shell_view_model.dart';
import 'package:pomodoist/ui/core/view_models/shortcut_hints_controller.dart';

class ShortcutHint {
  const ShortcutHint(
    this.label,
    this.keys, {
    this.navigation = false,
    this.release = true,
    this.icon,
  });
  final String label;
  final String keys;
  final bool navigation;
  final bool release;
  final IconData? icon;
}

ShortcutHint? commandHint(
  AppLocalizations l10n,
  ShellKeyboardState keyboard,
  AppShortcutCommand command, {
  String? label,
  bool navigation = false,
}) {
  final keys = {
    for (final candidate in [
      command,
      if (command == AppShortcutCommand.focus)
        AppShortcutCommand.focusAlternate,
    ])
      if (keyboard.shortcuts[candidate] case final binding?)
        binding.labelFor(keyboard.platform),
  };
  return keys.isEmpty
      ? null
      : ShortcutHint(
          label ?? appShortcutLabel(l10n, command),
          keys.join(' / '),
          navigation: navigation,
          release: false,
          icon: switch (command) {
            AppShortcutCommand.quickAdd => LucideIcons.plus,
            AppShortcutCommand.toggleSidebar => LucideIcons.panelLeft,
            AppShortcutCommand.search => LucideIcons.search,
            AppShortcutCommand.focus ||
            AppShortcutCommand.focusAlternate => LucideIcons.timer,
            _ => null,
          },
        );
}

List<ShortcutHint> shellShortcutHints(
  AppLocalizations l10n,
  ShellKeyboardState keyboard, {
  required bool focusLocation,
}) => [
  ?commandHint(l10n, keyboard, AppShortcutCommand.quickAdd),
  ?commandHint(l10n, keyboard, AppShortcutCommand.toggleSidebar),
  ?commandHint(l10n, keyboard, AppShortcutCommand.search, navigation: true),
  ?commandHint(
    l10n,
    keyboard,
    AppShortcutCommand.focus,
    navigation: true,
    label: focusLocation ? l10n.shortcutHintsSwitchFocusView : null,
  ),
];

bool shortcutHintsSupported(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// One observer per Flutter view; never consumes hardware events.
class ShortcutHintsHost extends StatefulWidget {
  const ShortcutHintsHost({super.key, required this.child});
  final Widget child;
  @override
  State<ShortcutHintsHost> createState() => _ShortcutHintsHostState();
}

class _ShortcutHintsHostState extends State<ShortcutHintsHost>
    with WidgetsBindingObserver {
  final controller = ShortcutHintsController();
  final scopes = <_ShortcutHintsScopeState>[];
  _ShortcutHintsScopeState? active;
  Object? _identity;
  bool _focused = true;
  bool get supported => shortcutHintsSupported(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    FocusManager.instance.addListener(_sync);
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _focused = event.state == ViewFocusState.focused;
    controller.setFocused(_focused);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setFocused(state == AppLifecycleState.resumed && _focused);
  }

  bool get _primaryPressed => defaultTargetPlatform == TargetPlatform.macOS
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  void reset() {
    controller.reset();
    if (!_primaryPressed) controller.key(primary: false);
  }

  void _sync() {
    if (!mounted) return;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final focusedScope = focusContext
        ?.getInheritedWidgetOfExactType<_ScopeData>()
        ?.scope;
    final route = focusContext == null ? null : ModalRoute.of(focusContext);
    final modal = scopes
        .where((scope) => scope.widget.modal && scope.route?.isCurrent != false)
        .lastOrNull;
    var next =
        focusedScope?.host == this && focusedScope?.route?.isCurrent != false
        ? focusedScope
        : null;
    while (next != null && !next.widget.enabled && !next.widget.modal) {
      next = next.parent;
    }
    if (modal != null && (next == null || !next.isInside(modal))) next = modal;
    next ??= scopes
        .where(
          (scope) => scope.widget.fallback && scope.route?.isCurrent != false,
        )
        .lastOrNull;
    // A dialog without registered commands must never expose the shell beneath it.
    if (route is PopupRoute && next?.route != route) next = null;
    final identity = next?.widget.identity;
    if (next != active || identity != _identity) {
      active = next;
      _identity = identity;
    }
    controller.setContext((
      next,
      identity,
    ), enabled: next?.widget.enabled == true && next!.widget.hints.isNotEmpty);
  }

  bool _key(KeyEvent event) {
    if (!supported) return false;
    _sync();
    final keyboard = HardwareKeyboard.instance;
    final apple = defaultTargetPlatform == TargetPlatform.macOS;
    final primary = apple ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (!_focused ||
        (FocusManager.instance.primaryFocus?.context != null &&
            View.maybeOf(
                  FocusManager.instance.primaryFocus!.context!,
                )?.viewId !=
                View.of(context).viewId) ||
        active == null ||
        !active!.widget.enabled ||
        active!.widget.hints.isEmpty) {
      controller.reset();
      if (!primary) controller.key(primary: false);
      return false;
    }
    final key = event.logicalKey;
    final primaryKey = apple
        ? key == LogicalKeyboardKey.metaLeft ||
              key == LogicalKeyboardKey.metaRight
        : key == LogicalKeyboardKey.controlLeft ||
              key == LogicalKeyboardKey.controlRight;
    final modifiers = <LogicalKeyboardKey>{
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    final modifier = modifiers.contains(key);
    final ordinaryHeld = keyboard.logicalKeysPressed.any(
      (key) => !modifiers.contains(key),
    );
    controller.key(
      primary: primary,
      primaryDown: primaryKey && event is KeyDownEvent,
      ordinaryDown:
          ordinaryHeld ||
          (!modifier && (event is KeyDownEvent || event is KeyRepeatEvent)),
      otherModifier:
          keyboard.isShiftPressed ||
          keyboard.isAltPressed ||
          (apple ? keyboard.isControlPressed : keyboard.isMetaPressed),
      repeat: event is KeyRepeatEvent,
    );
    return false;
  }

  bool shows(_ShortcutHintsScopeState? scope) =>
      supported &&
      controller.visible &&
      active == scope &&
      scope?.widget.enabled == true;

  @override
  void dispose() {
    FocusManager.instance.removeListener(_sync);
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _HostData(host: this, child: widget.child);
}

class _HostData extends InheritedNotifier<ShortcutHintsController> {
  _HostData({required this.host, required super.child})
    : super(notifier: host.controller);
  final _ShortcutHintsHostState host;
}

class _ScopeData extends InheritedWidget {
  const _ScopeData({required this.scope, required super.child});
  final _ShortcutHintsScopeState scope;
  @override
  bool updateShouldNotify(_ScopeData oldWidget) => oldWidget.scope != scope;
}

/// Local scopes replace shell commands only while focused, or for a modal's lifetime.
class ShortcutHintsScope extends StatefulWidget {
  const ShortcutHintsScope({
    super.key,
    required this.hints,
    required this.child,
    this.identity,
    this.fallback = false,
    this.modal = false,
    this.enabled = true,
  });
  final List<ShortcutHint> hints;
  final Widget child;
  final Object? identity;
  final bool fallback;
  final bool modal;
  final bool enabled;
  @override
  State<ShortcutHintsScope> createState() => _ShortcutHintsScopeState();
}

class _ShortcutHintsScopeState extends State<ShortcutHintsScope> {
  _ShortcutHintsHostState? host;
  _ShortcutHintsScopeState? parent;
  ModalRoute<dynamic>? route;
  bool isInside(_ShortcutHintsScopeState other) =>
      this == other || (parent?.isInside(other) ?? false);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.getInheritedWidgetOfExactType<_HostData>()?.host;
    if (next != host) {
      host?.scopes.remove(this);
      host = next;
      host?.scopes.add(this);
    }
    parent = context.getInheritedWidgetOfExactType<_ScopeData>()?.scope;
    route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => host?._sync());
  }

  @override
  void didUpdateWidget(ShortcutHintsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.modal && widget.modal) {
      host?.scopes.remove(this);
      host?.scopes.add(this);
    }
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.modal != widget.modal ||
        oldWidget.identity != widget.identity) {
      host?.reset();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => host?._sync());
  }

  @override
  void dispose() {
    host?.scopes.remove(this);
    final previous = host;
    WidgetsBinding.instance.addPostFrameCallback((_) => previous?._sync());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ScopeData(
    scope: this,
    child: Focus(canRequestFocus: false, child: widget.child),
  );
}

class ShortcutKeycap extends StatelessWidget {
  const ShortcutKeycap(this.keys, {super.key});
  final String keys;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: context.appColors.surfaceTint,
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      keys,
      style: AppTheme.monoTextStyle.copyWith(
        fontSize: 12,
        color: context.appColors.primaryText,
      ),
    ),
  );
}

Widget _reveal(BuildContext context, Widget child) => IgnorePointer(
  child: ExcludeFocus(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.duration(context, AppMotion.popup),
      curve: AppMotion.curve,
      builder: (_, value, child) => Opacity(opacity: value, child: child),
      child: child,
    ),
  ),
);

/// Overlay badges never take space from labels or task counters.
class ShortcutHintBadge extends ConsumerWidget {
  const ShortcutHintBadge({
    super.key,
    required this.command,
    required this.child,
    this.alignment = Alignment.centerRight,
  });
  final AppShortcutCommand command;
  final Widget child;
  final Alignment alignment;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = context.dependOnInheritedWidgetOfExactType<_HostData>()?.host;
    final scope = context.getInheritedWidgetOfExactType<_ScopeData>()?.scope;
    final keyboard = ref.watch(shellKeyboardViewModelProvider);
    final hint = commandHint(context.l10n, keyboard, command);
    return Stack(
      clipBehavior: Clip.none,
      alignment: alignment,
      children: [
        child,
        if (host?.shows(scope) == true && hint != null)
          Positioned.fill(
            child: Align(
              alignment: alignment,
              child: _reveal(context, ShortcutKeycap(hint.keys)),
            ),
          ),
      ],
    );
  }
}

String get _primaryLabel =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';

/// Compact local hints next to dialog actions; its reserved height prevents jumps.
class ShortcutHintsBar extends StatelessWidget {
  const ShortcutHintsBar({super.key});
  @override
  Widget build(BuildContext context) {
    final host = context.dependOnInheritedWidgetOfExactType<_HostData>()?.host;
    final scope = context.getInheritedWidgetOfExactType<_ScopeData>()?.scope;
    if (host?.supported != true) return const SizedBox.shrink();
    final active = host?.active;
    final visible =
        active != null &&
        scope != null &&
        active.isInside(scope) &&
        host?.shows(active) == true;
    final local = active != null && scope != null && active.isInside(scope);
    final hints =
        (local ? active : scope)?.widget.hints ?? const <ShortcutHint>[];
    return Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: KeyedSubtree(
        key: ValueKey(visible),
        child: _reveal(
          context,
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    for (final hint in hints)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShortcutKeycap(hint.keys),
                          const SizedBox(width: 6),
                          Flexible(child: Text(hint.label)),
                        ],
                      ),
                  ],
                ),
                if (hints.any((hint) => hint.release))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.l10n.shortcutHintsRelease(_primaryLabel),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact help for the independently positioned voice capsule.
class ShortcutHintsCompactHelp extends StatelessWidget {
  const ShortcutHintsCompactHelp({super.key});
  @override
  Widget build(BuildContext context) {
    final host = context.dependOnInheritedWidgetOfExactType<_HostData>()?.host;
    final scope = context.getInheritedWidgetOfExactType<_ScopeData>()?.scope;
    final active = host?.active;
    if (active == null ||
        scope == null ||
        !active.isInside(scope) ||
        host?.shows(active) != true) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.appColors.border),
        ),
        child: const ShortcutHintsBar(),
      ),
    );
  }
}
