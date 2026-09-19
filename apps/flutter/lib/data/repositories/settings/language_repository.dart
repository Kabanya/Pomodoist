import 'package:flutter/foundation.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/utils/result.dart';

class LanguageRepository extends ChangeNotifier {
  LanguageRepository(this._preferences, {AppLanguage? linked}) {
    ready = _load(linked);
  }
  final PreferencesService _preferences;
  late final Future<Result<void>> ready;
  AppLanguage _language = AppLanguage.system;
  AppLanguage get language => _language;
  bool _edited = false;
  bool _disposed = false;
  Future<Result<void>> _load(AppLanguage? linked) => Result.capture(() async {
    final values = (await _preferences.read([
      appLanguagePreferenceKey,
    ])).getOrThrow();
    if (_disposed || _edited) return;
    _language =
        linked ??
        AppLanguage.fromStorageValue(
          values[appLanguagePreferenceKey] as String?,
        );
    notifyListeners();
    if (linked != null) {
      (await _preferences.write({
        appLanguagePreferenceKey: linked.storageValue,
      })).getOrThrow();
    }
  });
  Future<Result<void>> setLanguage(AppLanguage value) async {
    if (_disposed) return const Result.ok(null);
    _edited = true;
    _language = value;
    notifyListeners();
    return _preferences.write({appLanguagePreferenceKey: value.storageValue});
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
