import 'dart:ui';

/// Description of a user display screen.
class Display {
  const Display({
    required this.id,
    this.name,
    required this.size,
    this.visiblePosition,
    this.visibleSize,
    this.scaleFactor,
  });

  factory Display.fromJson(Map<String, dynamic> json) {
    final sizeMap = json['size'] as Map;
    final visiblePositionMap = json['visiblePosition'] as Map?;
    final visibleSizeMap = json['visibleSize'] as Map?;

    return Display(
      id: json['id'] as String,
      name: json['name'] as String?,
      size: Size((sizeMap['width'] as num).toDouble(), (sizeMap['height'] as num).toDouble()),
      visiblePosition: visiblePositionMap != null
          ? Offset((visiblePositionMap['dx'] as num).toDouble(), (visiblePositionMap['dy'] as num).toDouble())
          : null,
      visibleSize: visibleSizeMap != null
          ? Size((visibleSizeMap['width'] as num).toDouble(), (visibleSizeMap['height'] as num).toDouble())
          : null,
      scaleFactor: json['scaleFactor'] as num?,
    );
  }

  /// Unique identifier associated with the display.
  final String id;

  /// The name of the display.
  final String? name;

  /// The size of the display in logical pixels.
  final Size size;

  /// The visible area position of the display in logical pixels.
  /// Uses Flutter coordinate space (Y-down, origin at top-left of primary screen).
  final Offset? visiblePosition;

  /// The visible area size of the display in logical pixels.
  final Size? visibleSize;

  /// The scale factor of the display.
  final num? scaleFactor;
}
