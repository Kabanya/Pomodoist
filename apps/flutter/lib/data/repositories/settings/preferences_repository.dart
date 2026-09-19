import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/utils/result.dart';

class PreferencesRepository {
  const PreferencesRepository(this._service);

  final PreferencesService _service;

  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) => _service.read(keys, reload: reload);

  Future<Result<void>> write(Map<String, Object?> values) =>
      _service.write(values);
}
