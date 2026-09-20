import 'package:pomodoist/data/repositories/settings/app_zoom_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/utils/result.dart';

final class LocalAppZoomRepository implements AppZoomRepository {
  LocalAppZoomRepository(this._preferences);

  final PreferencesService _preferences;

  @override
  Future<Result<int?>> read() => Result.capture(() async {
    final values = (await _preferences.read(const [
      appZoomPreferenceKey,
    ])).getOrThrow();
    final saved = values[appZoomPreferenceKey];
    return saved is int ? saved : null;
  });

  @override
  Future<Result<void>> write(int percent) =>
      _preferences.write({appZoomPreferenceKey: percent});
}
