import 'package:pomodoist/utils/result.dart';

const appThemeSettingsPreferenceKey = 'app.themeSettings';
const appThemeSettingsLegacyBackupKey = 'app.themeSettings.v1Backup';

/// Persisted custom theme settings as plain JSON.
///
/// Color/palette conversion stays in the UI layer; this repository owns the
/// preference keys, the version-1 backup and the raw writes.
abstract interface class ThemeSettingsRepository {
  Future<Result<String?>> read({bool reload = false});
  Future<Result<String?>> readBackup();
  Future<Result<void>> write(String value);
  Future<Result<void>> writeBackup(String value);
}
