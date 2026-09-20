import 'package:pomodoist/utils/result.dart';

const keyboardShortcutsPreferenceKey = 'keyboard.shortcuts.v1';

/// Persisted shortcut bindings as their plain JSON encoding.
///
/// The UI layer owns binding parsing and migration; this repository owns the
/// preference key and the raw read/write.
abstract interface class KeyboardShortcutsRepository {
  Future<Result<String?>> read();
  Future<Result<void>> write(String json);
}
