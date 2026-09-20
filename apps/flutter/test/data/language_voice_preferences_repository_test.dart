import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/repositories/settings/language_repository_impl.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local language selection wins over a late stored value', () async {
    SharedPreferences.setMockInitialValues({
      appLanguagePreferenceKey: AppLanguage.ru.storageValue,
    });
    final open = Completer<SharedPreferences?>();
    final repository = LocalLanguageRepository(
      PreferencesService(() => open.future),
    );

    final saving = repository.setLanguage(AppLanguage.de);
    open.complete(await SharedPreferences.getInstance());

    (await saving).getOrThrow();
    (await repository.ready).getOrThrow();
    expect(repository.language, AppLanguage.de);
  });

  test('voice mode loads and persists through the repository', () async {
    SharedPreferences.setMockInitialValues({
      voiceTranscriptionModePreferenceKey:
          VoiceTranscriptionMode.cloud.storageValue,
    });
    final repository = LocalVoicePreferencesRepository(
      PreferencesService(SharedPreferences.getInstance),
    );

    (await repository.ready).getOrThrow();
    expect(repository.mode, VoiceTranscriptionMode.cloud);
    (await repository.setMode(VoiceTranscriptionMode.system)).getOrThrow();
    expect(
      (await SharedPreferences.getInstance()).getString(
        voiceTranscriptionModePreferenceKey,
      ),
      VoiceTranscriptionMode.system.storageValue,
    );
  });

  test(
    'voice smart mode persists and an explicit choice wins over hydration',
    () async {
      SharedPreferences.setMockInitialValues({
        voiceSmartModePreferenceKey: false,
      });
      final open = Completer<SharedPreferences?>();
      final repository = LocalVoicePreferencesRepository(
        PreferencesService(() => open.future),
      );

      final saving = repository.setSmartMode(true);
      open.complete(await SharedPreferences.getInstance());

      (await saving).getOrThrow();
      (await repository.ready).getOrThrow();
      expect(repository.smartMode, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          voiceSmartModePreferenceKey,
        ),
        isTrue,
      );
    },
  );
}
