import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/config/voice_task_route.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

final class VoiceSettingsState {
  const VoiceSettingsState({
    required this.mode,
    required this.supported,
    required this.signedIn,
    required this.managedAccess,
  });
  final VoiceTranscriptionMode mode;
  final bool supported;
  final bool signedIn;
  final bool managedAccess;
}

final voiceSettingsViewModelProvider =
    NotifierProvider<VoiceSettingsViewModel, VoiceSettingsState>(
      VoiceSettingsViewModel.new,
    );

class VoiceSettingsViewModel extends Notifier<VoiceSettingsState> {
  @override
  VoiceSettingsState build() {
    ref.watch(accountSessionProvider);
    return VoiceSettingsState(
      mode: ref.watch(voiceTranscriptionModeProvider),
      supported: ref.watch(voiceTranscriptionModeSelectionSupportedProvider),
      signedIn: ref.watch(accountSignedInProvider),
      managedAccess: ref.watch(managedVoiceAccessProvider),
    );
  }

  Future<void> setMode(VoiceTranscriptionMode mode, {bool? signedIn}) async {
    if (mode == VoiceTranscriptionMode.cloud &&
        (!(signedIn ?? state.signedIn) || !state.managedAccess)) {
      return;
    }
    (await ref.read(voicePreferencesRepositoryProvider).setMode(mode))
        .getOrThrow();
  }
}
