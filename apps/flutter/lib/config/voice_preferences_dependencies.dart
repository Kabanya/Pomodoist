import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/data/services/voice/voice_transcription_policy.dart';

final voiceTranscriptionModeSelectionSupportedProvider = Provider<bool>(
  (ref) => supportsVoiceTranscriptionModeSelection(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  ),
);

final voicePreferencesRepositoryProvider = Provider((ref) {
  final repository = VoicePreferencesRepository(
    ref.watch(preferencesServiceProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
final voiceTranscriptionModeProvider = Provider<VoiceTranscriptionMode>((ref) {
  final repository = ref.watch(voicePreferencesRepositoryProvider);
  repository.addListener(ref.invalidateSelf);
  ref.onDispose(() => repository.removeListener(ref.invalidateSelf));
  return repository.mode;
});
