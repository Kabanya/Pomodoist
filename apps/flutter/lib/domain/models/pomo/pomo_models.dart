enum PomoEmotion { calm, focus, rest, tired, greeting, happy, sad, surprised }

enum PomoDisplayMode { followUser, pinned }

/// A saved position relative to one display's work area.
class PomoDisplayPosition {
  const PomoDisplayPosition({required this.x, required this.y});

  final double x, y;

  static PomoDisplayPosition? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final x = value['x'], y = value['y'];
    if (x is! num || !x.isFinite || y is! num || !y.isFinite) return null;
    return PomoDisplayPosition(x: x.toDouble(), y: y.toDouble());
  }

  Map<String, double> toJson() => {'x': x, 'y': y};
}

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
    this.displayMode = PomoDisplayMode.followUser,
    this.allowCrossDisplayDrag = true,
    this.pinnedDisplayId,
    this.displayPositions = const {},
  });
  final bool enabled, dismissed, focusOnly, quiet, reduceMotion, showTimer;
  final double scale;
  static double normalizeScale(Object? value) =>
      value is num && value.isFinite ? value.toDouble().clamp(.25, 2.5) : 1;
  final double? x, y;
  final String? displayId;
  final PomoDisplayMode displayMode;
  final bool allowCrossDisplayDrag;
  final String? pinnedDisplayId;
  final Map<String, PomoDisplayPosition> displayPositions;

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
    PomoDisplayMode? displayMode,
    bool? allowCrossDisplayDrag,
    String? pinnedDisplayId,
    Map<String, PomoDisplayPosition>? displayPositions,
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
    displayMode: displayMode ?? this.displayMode,
    allowCrossDisplayDrag: allowCrossDisplayDrag ?? this.allowCrossDisplayDrag,
    pinnedDisplayId: pinnedDisplayId ?? this.pinnedDisplayId,
    displayPositions: resetPosition
        ? const {}
        : displayPositions ?? this.displayPositions,
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
    'displayMode': displayMode.name,
    'allowCrossDisplayDrag': allowCrossDisplayDrag,
    'pinnedDisplayId': pinnedDisplayId,
    'displayPositions': displayPositions.map(
      (id, position) => MapEntry(id, position.toJson()),
    ),
  };

  factory PomoPreferences.fromJson(Map<String, dynamic> json) {
    double? coordinate(Object? v) =>
        v is num && v.isFinite ? v.toDouble() : null;
    final x = coordinate(json['x']), y = coordinate(json['y']);
    final positions = <String, PomoDisplayPosition>{};
    final savedPositions = json['displayPositions'];
    if (savedPositions is Map) {
      for (final entry in savedPositions.entries) {
        final position = PomoDisplayPosition.tryFromJson(entry.value);
        if (entry.key is String && position != null) {
          positions[entry.key as String] = position;
        }
      }
    }
    return PomoPreferences(
      displayMode: json['displayMode'] == PomoDisplayMode.pinned.name
          ? PomoDisplayMode.pinned
          : PomoDisplayMode.followUser,
      allowCrossDisplayDrag: json['allowCrossDisplayDrag'] != false,
      pinnedDisplayId: json['pinnedDisplayId'] is String
          ? json['pinnedDisplayId'] as String
          : null,
      displayPositions: Map.unmodifiable(positions),
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
