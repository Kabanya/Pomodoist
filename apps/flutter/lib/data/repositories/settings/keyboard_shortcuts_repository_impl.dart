import 'package:pomodoist/data/repositories/settings/keyboard_shortcuts_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/utils/result.dart';

final class LocalKeyboardShortcutsRepository
    implements KeyboardShortcutsRepository {
  LocalKeyboardShortcutsRepository(this._preferences);

  final PreferencesService _preferences;

  @override
  Future<Result<String?>> read() => Result.capture(() async {
    final values = (await _preferences.read(const [
      keyboardShortcutsPreferenceKey,
    ])).getOrThrow();
    final saved = values[keyboardShortcutsPreferenceKey];
    return saved is String ? saved : null;
  });

  @override
  Future<Result<void>> write(String json) =>
      _preferences.write({keyboardShortcutsPreferenceKey: json});
}
