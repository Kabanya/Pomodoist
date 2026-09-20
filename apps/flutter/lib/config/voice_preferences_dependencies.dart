import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository_impl.dart';
import 'package:pomodoist/domain/models/voice/voice_preferences.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/data/services/voice/voice_transcription_policy.dart';

final voiceTranscriptionModeSelectionSupportedProvider = Provider<bool>(
  (ref) => supportsVoiceTranscriptionModeSelection(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  ),
);

final voicePreferencesRepositoryProvider = Provider<VoicePreferencesRepository>(
  (ref) {
    final repository = LocalVoicePreferencesRepository(
      ref.watch(preferencesServiceProvider),
    );
    ref.onDispose(repository.dispose);
    return repository;
  },
);

final voicePreferencesStateProvider = Provider<VoicePreferences>((ref) {
  final repository = ref.watch(voicePreferencesRepositoryProvider);
  final subscription = repository.watch().listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return repository.state;
});

final voiceTranscriptionModeProvider = Provider<VoiceTranscriptionMode>(
  (ref) => ref.watch(voicePreferencesStateProvider).mode,
);

final voiceSmartModeProvider = Provider<bool>(
  (ref) => ref.watch(voicePreferencesStateProvider).smartMode,
);
