import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'dart:async';

import 'package:pomodoist/data/repositories/voice/voice_preferences_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/voice/voice_preferences.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/utils/result.dart';

const voiceSmartModePreferenceKey = 'voice.smartMode';

const whisperPreferenceKey = 'voice.whisperModel';

class LocalVoicePreferencesRepository implements VoicePreferencesRepository {
  LocalVoicePreferencesRepository(
    this._preferences, {
    VoiceTranscriptionMode defaultMode = VoiceTranscriptionMode.system,
  }) : _mode = defaultMode,
       _defaultMode = defaultMode {
    ready = _load();
  }
  final PreferencesService _preferences;
  @override
  late final Future<Result<void>> ready;
  final _states = StreamController<VoicePreferences>.broadcast(sync: true);
  final VoiceTranscriptionMode _defaultMode;
  VoiceTranscriptionMode _mode;
  @override
  VoiceTranscriptionMode get mode => _mode;
  WhisperPreference _whisper = WhisperPreference.automatic;
  bool _smartMode = false;
  @override
  bool get smartMode => _smartMode;
  @override
  VoicePreferences get state =>
      (mode: _mode, smartMode: _smartMode, whisper: _whisper);
  @override
  Stream<VoicePreferences> watch() => _states.stream;
  bool _modeEdited = false;
  bool _smartModeEdited = false;
  bool _disposed = false;
  Future<Result<void>> _load() => Result.capture(() async {
    final values = (await _preferences.read([
      voiceTranscriptionModePreferenceKey,
      voiceSmartModePreferenceKey,
      whisperPreferenceKey,
    ])).getOrThrow();
    if (_disposed) return;
    _whisper = WhisperPreference.fromStorage(values[whisperPreferenceKey]);
    if (!_modeEdited) {
      final stored = values[voiceTranscriptionModePreferenceKey];
      _mode = stored == null
          ? _defaultMode
          : VoiceTranscriptionMode.fromStorageValue(stored);
    }
    if (!_smartModeEdited) {
      _smartMode = values[voiceSmartModePreferenceKey] as bool? ?? false;
    }
    _states.add(state);
  });
  @override
  Future<Result<void>> setMode(VoiceTranscriptionMode value) async {
    if (_disposed) return const Result.ok(null);
    _modeEdited = true;
    final result = await _preferences.write({
      voiceTranscriptionModePreferenceKey: value.storageValue,
    });
    if (result is Success<void> && !_disposed) {
      _mode = value;
      _states.add(state);
    } else if (result is Failure<void>) {
      _modeEdited = false;
    }
    return result;
  }

  @override
  Future<Result<void>> setSmartMode(bool value) async {
    if (_disposed) return const Result.ok(null);
    _smartModeEdited = true;
    final result = await _preferences.write({
      voiceSmartModePreferenceKey: value,
    });
    if (result is Success<void> && !_disposed) {
      _smartMode = value;
      _states.add(state);
    } else if (result is Failure<void>) {
      _smartModeEdited = false;
    }
    return result;
  }

  @override
  Future<Result<void>> setWhisper(WhisperPreference value) async {
    await ready;
    if (_disposed) return const Result.ok(null);
    final result = await _preferences.write({
      whisperPreferenceKey: value.storageValue,
    });
    if (result is Success<void> && !_disposed) {
      _whisper = value;
      _states.add(state);
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _states.close();
  }
}
