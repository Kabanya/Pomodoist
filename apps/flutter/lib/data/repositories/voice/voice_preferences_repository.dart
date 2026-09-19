import 'package:flutter/foundation.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/utils/result.dart';

class VoicePreferencesRepository extends ChangeNotifier {
  VoicePreferencesRepository(this._preferences) {
    ready = _load();
  }
  final PreferencesService _preferences;
  late final Future<Result<void>> ready;
  VoiceTranscriptionMode _mode = VoiceTranscriptionMode.system;
  VoiceTranscriptionMode get mode => _mode;
  bool _edited = false;
  bool _disposed = false;
  Future<Result<void>> _load() => Result.capture(() async {
    final values = (await _preferences.read([
      voiceTranscriptionModePreferenceKey,
    ])).getOrThrow();
    if (_disposed || _edited) return;
    _mode = VoiceTranscriptionMode.fromStorageValue(
      values[voiceTranscriptionModePreferenceKey],
    );
    notifyListeners();
  });
  Future<Result<void>> setMode(VoiceTranscriptionMode value) async {
    if (_disposed) return const Result.ok(null);
    _edited = true;
    _mode = value;
    notifyListeners();
    return _preferences.write({
      voiceTranscriptionModePreferenceKey: value.storageValue,
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
