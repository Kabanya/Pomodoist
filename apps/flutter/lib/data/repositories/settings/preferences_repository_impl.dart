import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/utils/result.dart';

class LocalPreferencesRepository implements PreferencesRepository {
  const LocalPreferencesRepository(this._service);

  final PreferencesService _service;

  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) => _service.read(keys, reload: reload);

  @override
  Future<Result<void>> write(Map<String, Object?> values) =>
      _service.write(values);
}
