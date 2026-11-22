import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

typedef VoicePreferences = ({
  VoiceTranscriptionMode mode,
  bool smartMode,
  WhisperPreference whisper,
});
