import 'dart:typed_data';

import 'package:pomodoist/data/repositories/settings/theme_image_repository.dart';
import 'package:pomodoist/data/repositories/settings/theme_settings_repository.dart';

/// Coordinates settings and image persistence as one protected operation.
final class ThemeSettingsStorageUseCase {
  const ThemeSettingsStorageUseCase(this._settings, this._images);

  final ThemeSettingsRepository _settings;
  final ThemeImageRepository _images;

  Future<Uint8List?> readImage(String id) => _images.read(id);

  Future<void> save({
    required String value,
    required Set<String> retainedImageIds,
    required Map<String, Uint8List> pendingImages,
    String? legacyBackup,
    bool verifyRetainedImages = false,
  }) => _images.protect(() async {
    if (legacyBackup != null &&
        (await _settings.readBackup()).getOrThrow() == null) {
      (await _settings.writeBackup(legacyBackup)).getOrThrow();
    }
    for (final id in retainedImageIds) {
      final bytes = pendingImages[id];
      if (bytes != null) {
        await _images.write(id, bytes);
      } else if (verifyRetainedImages && await _images.read(id) == null) {
        throw StateError('A background image is no longer available');
      }
    }
    (await _settings.write(value)).getOrThrow();
    try {
      await _images.retain(retainedImageIds);
    } catch (_) {
      // Cleanup cannot invalidate settings that were already persisted.
    }
  });
}
