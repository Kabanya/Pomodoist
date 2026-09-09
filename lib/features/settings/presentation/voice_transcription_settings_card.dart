import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'settings_components.dart';
import '../../voice/data/voice_transcription_mode.dart';

class VoiceTranscriptionSettingsCard extends ConsumerWidget {
  const VoiceTranscriptionSettingsCard({required this.signedIn, super.key});

  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!supportsVoiceTranscriptionModeSelection(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(voiceTranscriptionModeProvider);
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
                              .read(voiceTranscriptionModeProvider.notifier)
                              .setMode(option),
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
