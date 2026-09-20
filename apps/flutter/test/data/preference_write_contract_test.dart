import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository_impl.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/utils/result.dart';

class FailedPreferences extends PreferencesService {
  FailedPreferences() : super(() async => null);
  @override
  Future<Result<void>> write(Map<String, Object?> values) async =>
      Failure(StateError('disk failure'), StackTrace.current);
}

class DelayedPreferences extends PreferencesService {
  DelayedPreferences() : super(() async => null);
  final pending = Completer<Result<Map<String, Object>>>();
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) => pending.future;
  @override
  Future<Result<void>> write(Map<String, Object?> values) async =>
      const Success(null);
}

void main() {
  test('focus settings report a failed preference write', () async {
    final repo = StoredFocusPreferencesRepository(FailedPreferences());
    addTearDown(repo.dispose);
    expect(await repo.setViewMode(FocusViewMode.full), isA<Failure<void>>());
  });
  test('changing voice mode does not discard hydrated smart mode', () async {
    final prefs = DelayedPreferences();
    final repo = LocalVoicePreferencesRepository(prefs);
    addTearDown(repo.dispose);
    await repo.setMode(VoiceTranscriptionMode.system);
    prefs.pending.complete(const Success({voiceSmartModePreferenceKey: true}));
    (await repo.ready).getOrThrow();
    expect(repo.smartMode, isTrue);
  });
}
