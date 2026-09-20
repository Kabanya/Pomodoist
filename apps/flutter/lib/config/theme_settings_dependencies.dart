import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/theme_image_repository.dart';
import 'package:pomodoist/data/repositories/settings/theme_image_import_repository.dart';
import 'package:pomodoist/data/repositories/settings/theme_image_import_repository_impl.dart';
import 'package:pomodoist/data/repositories/settings/stored_theme_image_repository.dart';
import 'package:pomodoist/data/repositories/settings/theme_settings_repository.dart';
import 'package:pomodoist/data/repositories/settings/theme_settings_repository_impl.dart';
import 'package:pomodoist/data/services/local/theme_image_store.dart';
import 'package:pomodoist/data/services/platform/theme_image_file_service.dart';
import 'package:pomodoist/domain/use_cases/settings/theme_settings_storage_use_case.dart';
import 'package:pomodoist/ui/core/themes/theme_image_preparation.dart';

final themeSettingsRepositoryProvider = Provider<ThemeSettingsRepository>(
  (ref) => LocalThemeSettingsRepository(ref.watch(preferencesServiceProvider)),
);
final themeImageRepositoryProvider = Provider<ThemeImageRepository>(
  (ref) => StoredThemeImageRepository(createThemeImageStore()),
);
final themeImagePreparerProvider =
    Provider<Future<Uint8List> Function(Uint8List)>((ref) => prepareThemeImage);
final themeImageImportRepositoryProvider = Provider<ThemeImageImportRepository>(
  (ref) => FileThemeImageImportRepository(
    ThemeImageFileService(ref.watch(themeImagePreparerProvider)),
  ),
);
final themeSettingsStorageUseCaseProvider =
    Provider<ThemeSettingsStorageUseCase>(
      (ref) => ThemeSettingsStorageUseCase(
        ref.watch(themeSettingsRepositoryProvider),
        ref.watch(themeImageRepositoryProvider),
      ),
    );
