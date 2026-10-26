import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton;
import 'package:pomodoist/ui/distractions/view_models/distraction_view_model.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';

class FocusExitHost extends ConsumerWidget {
  const FocusExitHost({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(distractionViewModelProvider);
    final commands = ref.watch(distractionCommandsProvider);
    final l = context.l10n;
    final notice = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.distractionExitTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                state.strictExitSeconds == 60
                    ? l.distractionExitCountdown(state.exitRemaining)
                    : l.distractionExitConfirm,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MergeSemantics(
                    child: Semantics(
                      button: true,
                      enabled: commands != null,
                      child: ShadButton.outline(
                        height: 48,
                        onPressed: commands == null
                            ? null
                            : () => unawaited(commands.cancelExit()),
                        child: Text(l.distractionExitCancel),
                      ),
                    ),
                  ),
                  if (state.strictExitSeconds == 0)
                    MergeSemantics(
                      child: Semantics(
                        button: true,
                        enabled: commands != null,
                        child: ShadButton(
                          height: 48,
                          onPressed: commands == null
                              ? null
                              : () => unawaited(commands.confirmExit()),
                          child: Text(l.distractionExitConfirmButton),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Stack(
      children: [
        child,
        if (state.available && state.active && state.local)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: Chip(label: Text(l.distractionLocal)),
                ),
              ),
            ),
          ),
        if (state.exitPending && commands != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: notice,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
