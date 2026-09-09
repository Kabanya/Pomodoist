import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsVoiceTranscriptionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsVoiceTranscriptionSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<VoiceTranscriptionMode>(
              key: const Key('settings-voice-transcription-mode'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: VoiceTranscriptionMode.system,
                  label: Text(l10n.settingsVoiceTranscriptionSystem),
                ),
                ButtonSegment(
                  value: VoiceTranscriptionMode.cloud,
                  enabled: signedIn,
                  label: Text(l10n.settingsVoiceTranscriptionCloud),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => unawaited(
                ref
                    .read(voiceTranscriptionModeProvider.notifier)
                    .setMode(selection.single),
              ),
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
      ),
    );
  }
}
