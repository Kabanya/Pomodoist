import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/settings/theme_mode_repository.dart';
import 'package:pomodoist/utils/result.dart';

final class LocalThemeModeRepository implements ThemeModeRepository {
  LocalThemeModeRepository(this._preferences);

  final PreferencesService _preferences;

  @override
  Future<Result<String?>> read() => Result.capture(() async {
    final values = (await _preferences.read(const [
      appThemeModePreferenceKey,
    ])).getOrThrow();
    final saved = values[appThemeModePreferenceKey];
    return saved is String ? saved : null;
  });

  @override
  Future<Result<void>> write(String storageValue) =>
      _preferences.write({appThemeModePreferenceKey: storageValue});
}
