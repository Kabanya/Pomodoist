import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/utils/result.dart';

/// The platform preference handle is kept behind this I/O boundary.
class PreferencesService {
  PreferencesService(this._open);
  final Future<SharedPreferences?> Function() _open;

  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) => Result.capture(() async {
    final preferences = await _open();
    if (reload) await preferences?.reload();
    return {
      for (final key in keys)
        if (preferences?.get(key) case final Object value) key: value,
    };
  });

  Future<Result<void>> write(Map<String, Object?> values) =>
      Result.capture(() async {
        final preferences = await _open();
        if (preferences == null) return;
        for (final entry in values.entries) {
          final saved = switch (entry.value) {
            bool value => await preferences.setBool(entry.key, value),
            int value => await preferences.setInt(entry.key, value),
            double value => await preferences.setDouble(entry.key, value),
            String value => await preferences.setString(entry.key, value),
            List<String> value => await preferences.setStringList(
              entry.key,
              value,
            ),
            null => await preferences.remove(entry.key),
            _ => throw ArgumentError(
              'Unsupported preference value for ${entry.key}',
            ),
          };
          if (!saved) throw StateError('Could not save ${entry.key}');
        }
      });
}
