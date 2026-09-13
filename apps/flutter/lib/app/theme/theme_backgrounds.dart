import 'package:flutter/material.dart';

import 'theme_image_store_contract.dart';

enum ThemeBackgroundMode { mainOnly, wholeApp, separate }

enum ThemeBackgroundZone { main, sidebar, quickAdd }

enum ThemeBackgroundType { color, photo, macosGlass }

class ThemeBackgroundImage {
  const ThemeBackgroundImage({this.imageId, required this.dim, this.blur = 0});

  final String? imageId;
  final double dim;
  final double blur;

  factory ThemeBackgroundImage.empty(Brightness brightness) =>
      ThemeBackgroundImage(dim: brightness == Brightness.light ? .4 : .5);

  ThemeBackgroundImage copyWith({
    String? imageId,
    bool clearImage = false,
    double? dim,
    double? blur,
  }) => ThemeBackgroundImage(
    imageId: clearImage ? null : imageId ?? this.imageId,
    dim: dim ?? this.dim,
    blur: blur ?? this.blur,
  );

  Map<String, Object> toJson() => {
    'imageId': ?imageId,
    'dim': dim,
    'blur': blur,
  };

  factory ThemeBackgroundImage.fromJson(Object? json, Brightness brightness) {
    final fallback = ThemeBackgroundImage.empty(brightness);
    if (json is! Map) return fallback;
    final id = json['imageId'];
    double number(String key, double defaultValue, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(0, max)
          : defaultValue;
    }

    return ThemeBackgroundImage(
      imageId: id is String && isThemeImageId(id) ? id : null,
      dim: number('dim', fallback.dim, 1),
      blur: number('blur', 0, 20),
    );
  }
}

class ThemeBackgrounds {
  const ThemeBackgrounds({
    this.type = ThemeBackgroundType.color,
    this.mode = ThemeBackgroundMode.mainOnly,
    this.images = const {},
    this.glassLightDim = .4,
    this.glassDarkDim = .5,
  });

  final ThemeBackgroundType type;
  final ThemeBackgroundMode mode;
  final Map<String, ThemeBackgroundImage> images;
  final double glassLightDim;
  final double glassDarkDim;

  double glassDim(Brightness brightness) =>
      brightness == Brightness.light ? glassLightDim : glassDarkDim;

  ThemeBackgroundType effectiveType({
    required bool isMacOS,
    required bool glassReady,
    bool reduceTransparency = false,
  }) =>
      type == ThemeBackgroundType.macosGlass &&
          (!isMacOS || !glassReady || reduceTransparency)
      ? ThemeBackgroundType.color
      : type;

  ThemeBackgroundImage imageFor(
    ThemeBackgroundZone zone,
    Brightness brightness,
  ) =>
      images['${zone.name}.${brightness.name}'] ??
      ThemeBackgroundImage.empty(brightness);

  ThemeBackgroundImage resolve(
    ThemeBackgroundZone zone,
    Brightness brightness,
  ) => type != ThemeBackgroundType.photo
      ? ThemeBackgroundImage.empty(brightness)
      : switch (mode) {
          ThemeBackgroundMode.wholeApp => imageFor(
            ThemeBackgroundZone.main,
            brightness,
          ),
          ThemeBackgroundMode.mainOnly when zone != ThemeBackgroundZone.main =>
            ThemeBackgroundImage.empty(brightness),
          _ => imageFor(zone, brightness),
        };

  ThemeBackgrounds copyWith({
    ThemeBackgroundType? type,
    ThemeBackgroundMode? mode,
    Map<String, ThemeBackgroundImage>? images,
    double? glassLightDim,
    double? glassDarkDim,
  }) => ThemeBackgrounds(
    type: type ?? this.type,
    mode: mode ?? this.mode,
    images: images ?? this.images,
    glassLightDim: _dim(glassLightDim, this.glassLightDim),
    glassDarkDim: _dim(glassDarkDim, this.glassDarkDim),
  );

  ThemeBackgrounds withImage(
    ThemeBackgroundZone zone,
    Brightness brightness,
    ThemeBackgroundImage image,
  ) => copyWith(
    images: Map.unmodifiable({
      ...images,
      '${zone.name}.${brightness.name}': image,
    }),
  );

  Set<String> get imageIds => {
    for (final image in images.values)
      if (image.imageId != null) image.imageId!,
  };

  Map<String, Object> toJson() => {
    'type': type.name,
    'glassLightDim': glassLightDim,
    'glassDarkDim': glassDarkDim,
    'mode': mode.name,
    'images': {
      for (final entry in images.entries) entry.key: entry.value.toJson(),
    },
  };

  factory ThemeBackgrounds.fromJson(Object? json) {
    if (json is! Map) return const ThemeBackgrounds();
    final mode = ThemeBackgroundMode.values
        .where((mode) => mode.name == json['mode'])
        .firstOrNull;
    final raw = json['images'];
    final images = Map<String, ThemeBackgroundImage>.unmodifiable({
      for (final zone in ThemeBackgroundZone.values)
        for (final brightness in Brightness.values)
          if (raw is Map && raw.containsKey('${zone.name}.${brightness.name}'))
            '${zone.name}.${brightness.name}': ThemeBackgroundImage.fromJson(
              raw['${zone.name}.${brightness.name}'],
              brightness,
            ),
    });
    final type = ThemeBackgroundType.values
        .where((type) => type.name == json['type'])
        .firstOrNull;
    return ThemeBackgrounds(
      type:
          type ??
          (!json.containsKey('type') &&
                  images.values.any((image) => image.imageId != null)
              ? ThemeBackgroundType.photo
              : ThemeBackgroundType.color),
      mode: mode ?? ThemeBackgroundMode.mainOnly,
      images: images,
      glassLightDim: _dim(json['glassLightDim'], .4),
      glassDarkDim: _dim(json['glassDarkDim'], .5),
    );
  }

  static double _dim(Object? value, double fallback) =>
      value is num && value.isFinite ? value.toDouble().clamp(0, 1) : fallback;
}
