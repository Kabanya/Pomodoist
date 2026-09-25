enum FocusViewMode {
  full('full'),
  minimal('minimal');

  const FocusViewMode(this.storageValue);

  final String storageValue;

  static FocusViewMode fromStorageValue(String? value) {
    return switch (value) {
      'full' => FocusViewMode.full,
      _ => FocusViewMode.minimal,
    };
  }
}

enum FocusTimerVisualStyle {
  bar('bar'),
  circle('circle');

  const FocusTimerVisualStyle(this.storageValue);

  final String storageValue;

  static FocusTimerVisualStyle fromStorageValue(String? value) {
    return switch (value) {
      'circle' => FocusTimerVisualStyle.circle,
      'bar' => FocusTimerVisualStyle.bar,
      _ => FocusTimerVisualStyle.circle,
    };
  }
}

/// Session rhythm presentation, independent of timer shape and detail level.
enum FocusSessionDisplay {
  compact('compact'),
  icons('icons');

  const FocusSessionDisplay(this.storageValue);
  final String storageValue;

  static FocusSessionDisplay fromStorageValue(String? value) => value == 'icons'
      ? FocusSessionDisplay.icons
      : FocusSessionDisplay.compact;
}
