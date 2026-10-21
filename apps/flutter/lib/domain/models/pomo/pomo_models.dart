enum PomoEmotion { calm, focus, rest, tired, greeting, happy, sad, surprised }

/// Device-local companion preferences. No account or server state is stored here.
class PomoPreferences {
  const PomoPreferences({
    this.enabled = false,
    this.dismissed = false,
    this.focusOnly = false,
    this.quiet = false,
    this.reduceMotion = false,
    this.showTimer = true,
    this.scale = 1,
    this.x,
    this.y,
    this.displayId,
  });
  final bool enabled, dismissed, focusOnly, quiet, reduceMotion, showTimer;
  final double scale;
  static double normalizeScale(Object? value) =>
      value is num && value.isFinite ? value.toDouble().clamp(.25, 2.5) : 1;
  final double? x, y;
  final String? displayId;

  bool shouldShow({required bool hasRun, bool explicitShow = false}) =>
      enabled && !dismissed && (!focusOnly || hasRun || explicitShow);

  PomoPreferences copyWith({
    bool? enabled,
    bool? dismissed,
    bool? focusOnly,
    bool? quiet,
    bool? reduceMotion,
    bool? showTimer,
    double? scale,
    double? x,
    double? y,
    String? displayId,
    bool resetPosition = false,
  }) => PomoPreferences(
    enabled: enabled ?? this.enabled,
    dismissed: dismissed ?? this.dismissed,
    focusOnly: focusOnly ?? this.focusOnly,
    quiet: quiet ?? this.quiet,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    showTimer: showTimer ?? this.showTimer,
    scale: normalizeScale(scale ?? this.scale),
    x: resetPosition ? null : x ?? this.x,
    y: resetPosition ? null : y ?? this.y,
    displayId: resetPosition ? null : displayId ?? this.displayId,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'dismissed': dismissed,
    'focusOnly': focusOnly,
    'quiet': quiet,
    'reduceMotion': reduceMotion,
    'showTimer': showTimer,
    'scale': scale,
    'x': x,
    'y': y,
    'displayId': displayId,
  };

  factory PomoPreferences.fromJson(Map<String, dynamic> json) {
    double? coordinate(Object? v) =>
        v is num && v.isFinite ? v.toDouble() : null;
    final x = coordinate(json['x']), y = coordinate(json['y']);
    return PomoPreferences(
      enabled: json['enabled'] == true,
      dismissed: json['dismissed'] == true,
      focusOnly: json['focusOnly'] == true,
      quiet: json['quiet'] == true,
      reduceMotion: json['reduceMotion'] == true,
      showTimer: json['showTimer'] != false,
      scale: normalizeScale(json['scale']),
      x: x != null && y != null ? x : null,
      y: x != null && y != null ? y : null,
      displayId: json['displayId'] is String
          ? json['displayId'] as String
          : null,
    );
  }
}
