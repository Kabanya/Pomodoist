import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadSelect, ShadOption, ShadButton;

import 'package:pomodoist/domain/models/settings/status_item_style.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/settings/view_models/status_item_style_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

bool get statusItemStyleSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

class StatusItemStyleSettings extends ConsumerWidget {
  const StatusItemStyleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!statusItemStyleSupported) return const SizedBox.shrink();
    final state = ref.watch(statusItemStyleProvider);
    final controller = ref.read(statusItemStyleProvider.notifier);
    final l10n = context.l10n;
    String label(StatusItemStyle style) => style == StatusItemStyle.classic
        ? l10n.settingsMenuBarTimerClassic
        : l10n.settingsMenuBarTimerModern;
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l10n.settingsMenuBarTimerTitle,
          control: Semantics(
            label: l10n.settingsMenuBarTimerTitle,
            child: ShadSelect<StatusItemStyle>(
              // Reset the select's internal value after a failed native save.
              key: ObjectKey(state),
              enabled: state.style != null && !state.isBusy,
              initialValue: state.style,
              placeholder: const Text('…'),
              options: [
                for (final style in StatusItemStyle.values)
                  ShadOption(value: style, child: Text(label(style))),
              ],
              selectedOptionBuilder: (context, style) => Text(label(style)),
              onChanged: (style) {
                if (style != null) controller.select(style);
              },
            ),
          ),
        ),
        if (state.isBusy) const LinearProgressIndicator(),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.settingsMenuBarTimerError,
                    style: TextStyle(color: context.appColors.error),
                  ),
                ),
                ShadButton.ghost(
                  onPressed: state.isBusy ? null : controller.retry,
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
