import 'package:flutter/material.dart';

import 'theme_image_store_contract.dart';

enum ThemeBackgroundMode { mainOnly, wholeApp, separate }

enum ThemeBackgroundZone { main, sidebar, quickAdd }

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
    this.mode = ThemeBackgroundMode.mainOnly,
    this.images = const {},
  });

  final ThemeBackgroundMode mode;
  final Map<String, ThemeBackgroundImage> images;

  ThemeBackgroundImage imageFor(
    ThemeBackgroundZone zone,
    Brightness brightness,
  ) =>
      images['${zone.name}.${brightness.name}'] ??
      ThemeBackgroundImage.empty(brightness);

  ThemeBackgroundImage resolve(
    ThemeBackgroundZone zone,
    Brightness brightness,
  ) => switch (mode) {
    ThemeBackgroundMode.wholeApp => imageFor(
      ThemeBackgroundZone.main,
      brightness,
    ),
    ThemeBackgroundMode.mainOnly when zone != ThemeBackgroundZone.main =>
      ThemeBackgroundImage.empty(brightness),
    _ => imageFor(zone, brightness),
  };

  ThemeBackgrounds copyWith({ThemeBackgroundMode? mode}) =>
      ThemeBackgrounds(mode: mode ?? this.mode, images: images);

  ThemeBackgrounds withImage(
    ThemeBackgroundZone zone,
    Brightness brightness,
    ThemeBackgroundImage image,
  ) => ThemeBackgrounds(
    mode: mode,
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
    return ThemeBackgrounds(
      mode: mode ?? ThemeBackgroundMode.mainOnly,
      images: Map.unmodifiable({
        for (final zone in ThemeBackgroundZone.values)
          for (final brightness in Brightness.values)
            if (raw is Map &&
                raw.containsKey('${zone.name}.${brightness.name}'))
              '${zone.name}.${brightness.name}': ThemeBackgroundImage.fromJson(
                raw['${zone.name}.${brightness.name}'],
                brightness,
              ),
      }),
    );
  }
}
