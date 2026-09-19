const voiceTranscriptionModePreferenceKey = 'voice.transcriptionMode';

enum VoiceTranscriptionMode {
  system('system'),
  cloud('cloud');

  const VoiceTranscriptionMode(this.storageValue);

  final String storageValue;

  static VoiceTranscriptionMode fromStorageValue(Object? value) =>
      value == VoiceTranscriptionMode.cloud.storageValue
      ? VoiceTranscriptionMode.cloud
      : VoiceTranscriptionMode.system;
}
