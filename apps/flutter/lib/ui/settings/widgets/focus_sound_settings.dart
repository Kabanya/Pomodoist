import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadOption, ShadSelect;
import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/settings/view_models/focus_sound_settings_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class FocusSoundSettings extends ConsumerStatefulWidget {
  const FocusSoundSettings({required this.active, super.key});
  final bool active;

  @override
  ConsumerState<FocusSoundSettings> createState() => _FocusSoundSettingsState();
}

class _FocusSoundSettingsState extends ConsumerState<FocusSoundSettings> {
  @override
  void didUpdateWidget(covariant FocusSoundSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      unawaited(
        ref.read(focusSoundSettingsViewModelProvider.notifier).stopPreview(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(focusSoundSettingsViewModelProvider);
    final controller = ref.read(focusSoundSettingsViewModelProvider.notifier);
    return SettingsRow(
      title: l10n.settingsFocusSoundTitle,
      subtitle: l10n.settingsFocusSoundSubtitle,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: l10n.settingsFocusSoundTitle,
            child: ShadSelect<FocusSoundSet>(
              key: ValueKey(state.soundSet),
              initialValue: state.soundSet,
              enabled: widget.active && !state.isSaving,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              options: [
                for (final soundSet in FocusSoundSet.values)
                  ShadOption(
                    value: soundSet,
                    child: Text(soundSet.displayName),
                  ),
              ],
              selectedOptionBuilder: (context, soundSet) =>
                  Text(soundSet.displayName),
              onChanged: (value) {
                if (value != null) {
                  unawaited(
                    saveSetting(context, controller.setSoundSet(value)),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          ShadButton.outline(
            height: 48,
            onPressed: widget.active && !state.isSaving
                ? controller.preview
                : null,
            leading: const Icon(LucideIcons.volume2, size: 18),
            child: Text(l10n.settingsFocusSoundPreview),
          ),
          if (state.previewFailed) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.settingsFocusSoundPreviewError,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.appColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
