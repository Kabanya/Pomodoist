import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/voice/whisper_model.dart';

final whisperModelSettingsProvider = Provider(
  (ref) => (
    supported: ref.watch(downloadableVoiceModelProvider),
    choice: ref.watch(
      voicePreferencesStateProvider.select((value) => value.whisper),
    ),
  ),
);

final whisperReadyProvider = FutureProvider.autoDispose
    .family<bool, WhisperModel>(
      (ref, model) => ref.watch(checkWhisperModelProvider)(model),
    );

final whisperModelActionsProvider = Provider((ref) => WhisperModelActions(ref));

class WhisperModelActions {
  WhisperModelActions(this._ref);
  final Ref _ref;

  Future<void> select(WhisperPreference choice) async {
    (await _ref.read(voicePreferencesRepositoryProvider).setWhisper(choice))
        .getOrThrow();
  }

  Future<void> download(
    WhisperModel model,
    void Function(double) progress,
  ) async {
    await _ref.read(downloadWhisperModelProvider)(model, progress);
    if (_ref.mounted) _ref.invalidate(whisperReadyProvider(model));
  }
}
