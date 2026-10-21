import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/settings/view_models/app_icon_settings_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class AppIconSettings extends ConsumerWidget {
  const AppIconSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appIconSettingsProvider);
    final controller = ref.read(appIconSettingsProvider.notifier);
    final l10n = context.l10n;
    final hint = kIsWeb
        ? l10n.appIconWebHint
        : defaultTargetPlatform == TargetPlatform.macOS
        ? l10n.appIconMacosHint
        : [
            TargetPlatform.windows,
            TargetPlatform.linux,
          ].contains(defaultTargetPlatform)
        ? l10n.appIconDesktopHint
        : null;
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l10n.appIconTitle,
          subtitle: hint,
          controlWidth: 320,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in AppIconChoice.values)
                Semantics(
                  selected: state.isLoaded && state.choice == choice,
                  child: SizedBox(
                    width: 156,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                        minimumSize: const Size(0, 128),
                        side: BorderSide(
                          color: state.isLoaded && state.choice == choice
                              ? context.appColors.accent
                              : context.appColors.border,
                        ),
                      ),
                      onPressed: state.isLoaded && !state.isSaving
                          ? () => controller.select(choice)
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/branding/app_icons/generated/${appFlavor.name}/${choice.id}.png',
                                width: 64,
                                height: 64,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${state.isLoaded && state.choice == choice ? "✓ " : ""}${choice == AppIconChoice.pomo ? l10n.appIconPomo : l10n.appIconClassic}',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (state.isSaving || (!state.isLoaded && state.error == null))
          const LinearProgressIndicator(),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.appIconError,
                    style: TextStyle(color: context.appColors.error),
                  ),
                ),
                if (!state.isLoaded)
                  TextButton(
                    onPressed: state.isSaving ? null : controller.load,
                    child: Text(l10n.commonRetry),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
