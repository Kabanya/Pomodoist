import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/repositories/settings/theme_image_repository.dart';
import 'package:pomodoist/data/repositories/settings/stored_theme_image_repository.dart';
import 'package:pomodoist/data/services/local/theme_image_store.dart';
import 'package:pomodoist/ui/core/themes/theme_image_preparation.dart';

final appThemePreferencesProvider = Provider<PreferencesRepository>(
  (ref) => ref.watch(preferencesRepositoryProvider),
);
final themeImageRepositoryProvider = Provider<ThemeImageRepository>(
  (ref) => StoredThemeImageRepository(createThemeImageStore()),
);
final themeImagePreparerProvider =
    Provider<Future<Uint8List> Function(Uint8List)>((ref) => prepareThemeImage);
