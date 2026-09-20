import 'package:pomodoist/utils/result.dart';

/// Contract for key/value preference reads and writes.
abstract interface class PreferencesRepository {
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  });

  Future<Result<void>> write(Map<String, Object?> values);
}
