import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/settings/theme_settings_repository.dart';
import 'package:pomodoist/utils/result.dart';

final class LocalThemeSettingsRepository implements ThemeSettingsRepository {
  LocalThemeSettingsRepository(this._preferences);

  final PreferencesService _preferences;

  @override
  Future<Result<String?>> read({bool reload = false}) =>
      Result.capture(() async {
        final values = (await _preferences.read(const [
          appThemeSettingsPreferenceKey,
        ], reload: reload)).getOrThrow();
        final raw = values[appThemeSettingsPreferenceKey];
        return raw is String ? raw : null;
      });

  @override
  Future<Result<String?>> readBackup() => Result.capture(() async {
    final values = (await _preferences.read(const [
      appThemeSettingsLegacyBackupKey,
    ])).getOrThrow();
    final raw = values[appThemeSettingsLegacyBackupKey];
    return raw is String ? raw : null;
  });

  @override
  Future<Result<void>> write(String value) =>
      _preferences.write({appThemeSettingsPreferenceKey: value});

  @override
  Future<Result<void>> writeBackup(String value) =>
      _preferences.write({appThemeSettingsLegacyBackupKey: value});
}
