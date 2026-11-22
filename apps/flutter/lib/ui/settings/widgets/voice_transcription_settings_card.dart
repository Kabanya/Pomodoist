import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'package:pomodoist/ui/voice/view_models/whisper_model_view_model.dart';
import 'package:pomodoist/ui/voice/widgets/whisper_model_controls.dart';
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
    final signedIn = this.signedIn ?? state.signedIn;
    final mode = signedIn ? state.mode : VoiceTranscriptionMode.system;
    final whisper = ref.watch(whisperModelSettingsProvider);
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
          if (whisper.supported) ...[
            const SizedBox(height: 12),
            DropdownButton<WhisperPreference>(
              isExpanded: true,
              value: whisper.choice,
              items: [
                for (final choice in WhisperPreference.values)
                  DropdownMenuItem(
                    value: choice,
                    child: Text(
                      choice == WhisperPreference.automatic
                          ? l10n.whisperDefault
                          : '${choice.model.label} · ${l10n.whisperSize(choice.model.megabytes)}',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  saveSetting(
                    context,
                    ref.read(whisperModelActionsProvider).select(value),
                  );
                }
              },
            ),
            Text(switch (whisper.choice.model) {
              WhisperModel.tiny => l10n.whisperFast,
              WhisperModel.base => l10n.whisperBalanced,
              WhisperModel.small => l10n.whisperAccuracy,
            }),
            const WhisperModelStatus(),
          ],
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
