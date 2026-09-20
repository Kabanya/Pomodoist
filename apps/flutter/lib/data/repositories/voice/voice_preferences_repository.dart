import 'package:pomodoist/domain/models/voice/voice_preferences.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/utils/result.dart';

/// Persisted voice transcription mode and smart-mode selection.
///
/// [state] is the current snapshot; [watch] delivers later updates. The owner
/// calls [dispose] to close the source stream.
abstract interface class VoicePreferencesRepository {
  /// Completes after the initial persisted value has been hydrated.
  Future<Result<void>> get ready;

  VoiceTranscriptionMode get mode;

  bool get smartMode;

  VoicePreferences get state;

  Stream<VoicePreferences> watch();

  Future<Result<void>> setMode(VoiceTranscriptionMode value);

  Future<Result<void>> setSmartMode(bool value);

  void dispose();
}
