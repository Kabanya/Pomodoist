enum WhisperModel {
  tiny('Whisper Tiny', 104),
  base('Whisper Base', 161),
  small('Whisper Small', 375);

  const WhisperModel(this.label, this.megabytes);
  final String label;
  final int megabytes;
}

enum WhisperPreference {
  automatic('default', WhisperModel.tiny),
  tiny('tiny', WhisperModel.tiny),
  base('base', WhisperModel.base),
  small('small', WhisperModel.small);

  const WhisperPreference(this.storageValue, this.model);
  final String storageValue;
  final WhisperModel model;

  static WhisperPreference fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => automatic,
  );
}
