import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/ui/settings/view_models/voice_settings_view_model.dart';

class VoiceTranscriptionSettingsCard extends ConsumerWidget {
  const VoiceTranscriptionSettingsCard({this.signedIn, super.key});

  final bool? signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceSettingsViewModelProvider);
    if (!state.supported) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final mode = state.mode;
    final signedIn = this.signedIn ?? state.signedIn;
    return SettingsRow(
      title: l10n.settingsVoiceTranscriptionTitle,
      subtitle: l10n.settingsVoiceTranscriptionSubtitle,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in VoiceTranscriptionMode.values)
                ChoiceChip(
                  label: Text(
                    option == VoiceTranscriptionMode.system
                        ? l10n.settingsVoiceTranscriptionSystem
                        : l10n.settingsVoiceTranscriptionCloud,
                  ),
                  selected: mode == option,
                  onSelected:
                      option == VoiceTranscriptionMode.cloud && !signedIn
                      ? null
                      : (_) => saveSetting(
                          context,
                          ref
                              .read(voiceSettingsViewModelProvider.notifier)
                              .setMode(option, signedIn: signedIn),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.settingsVoiceTranscriptionCloudDescription,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (!signedIn) ...[
            const SizedBox(height: 4),
            Text(
              l10n.settingsVoiceTranscriptionCloudRequiresSignIn,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
