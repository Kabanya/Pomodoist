import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/voice/data/voice_transcription_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Apple devices default to system transcription', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      expect(
        effectiveVoiceTranscriptionMode(
          isWeb: false,
          platform: platform,
          preferred: VoiceTranscriptionMode.system,
          signedIn: true,
        ),
        VoiceTranscriptionMode.system,
      );
    }
  });

  test('Apple devices use cloud only while signed in', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      expect(
        effectiveVoiceTranscriptionMode(
          isWeb: false,
          platform: platform,
          preferred: VoiceTranscriptionMode.cloud,
          signedIn: true,
        ),
        VoiceTranscriptionMode.cloud,
      );
      expect(
        effectiveVoiceTranscriptionMode(
          isWeb: false,
          platform: platform,
          preferred: VoiceTranscriptionMode.cloud,
          signedIn: false,
        ),
        VoiceTranscriptionMode.system,
      );
    }
  });

  test('non-Apple runtimes always use cloud transcription', () {
    for (final platform in TargetPlatform.values) {
      expect(
        effectiveVoiceTranscriptionMode(
          isWeb: true,
          platform: platform,
          preferred: VoiceTranscriptionMode.system,
          signedIn: false,
        ),
        VoiceTranscriptionMode.cloud,
      );
    }
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        effectiveVoiceTranscriptionMode(
          isWeb: false,
          platform: platform,
          preferred: VoiceTranscriptionMode.system,
          signedIn: false,
        ),
        VoiceTranscriptionMode.cloud,
      );
    }
  });

  test('cloud fallback is offered only for Apple speech failures', () {
    for (final code in [
      'speech_authorization_denied',
      'speech_permission_denied',
      'speech_authorization_restricted',
      'speech_dictation_disabled',
      'speech_unavailable',
      'speech_recognition_failed',
      'speech_locale_unsupported',
      'speech_network_unavailable',
    ]) {
      expect(
        canOfferCloudTranscriptionFallback(
          isWeb: false,
          platform: TargetPlatform.macOS,
          mode: VoiceTranscriptionMode.system,
          signedIn: true,
          errorCode: code,
        ),
        isTrue,
      );
    }
    for (final code in [
      null,
      'microphone_denied',
      'microphone_restricted',
      'speech_canceled',
    ]) {
      expect(
        canOfferCloudTranscriptionFallback(
          isWeb: false,
          platform: TargetPlatform.iOS,
          mode: VoiceTranscriptionMode.system,
          signedIn: true,
          errorCode: code,
        ),
        isFalse,
      );
    }
    expect(
      canOfferCloudTranscriptionFallback(
        isWeb: false,
        platform: TargetPlatform.iOS,
        mode: VoiceTranscriptionMode.cloud,
        signedIn: true,
        errorCode: 'speech_unavailable',
      ),
      isFalse,
    );
    expect(
      canOfferCloudTranscriptionFallback(
        isWeb: false,
        platform: TargetPlatform.iOS,
        mode: VoiceTranscriptionMode.system,
        signedIn: false,
        errorCode: 'speech_unavailable',
      ),
      isFalse,
    );
    expect(
      canOfferCloudTranscriptionFallback(
        isWeb: false,
        platform: TargetPlatform.android,
        mode: VoiceTranscriptionMode.system,
        signedIn: true,
        errorCode: 'speech_unavailable',
      ),
      isFalse,
    );
  });

  test(
    'stored mode is restored and invalid values fall back to system',
    () async {
      SharedPreferences.setMockInitialValues({
        voiceTranscriptionModePreferenceKey: 'cloud',
      });
      final saved = ProviderContainer();
      addTearDown(saved.dispose);

      expect(
        saved.read(voiceTranscriptionModeProvider),
        VoiceTranscriptionMode.system,
      );
      await saved.read(voiceTranscriptionModeProvider.notifier).ready;
      expect(
        saved.read(voiceTranscriptionModeProvider),
        VoiceTranscriptionMode.cloud,
      );

      SharedPreferences.setMockInitialValues({
        voiceTranscriptionModePreferenceKey: 'unknown',
      });
      final invalid = ProviderContainer();
      addTearDown(invalid.dispose);
      invalid.read(voiceTranscriptionModeProvider);
      await invalid.read(voiceTranscriptionModeProvider.notifier).ready;
      expect(
        invalid.read(voiceTranscriptionModeProvider),
        VoiceTranscriptionMode.system,
      );
    },
  );

  test('selected mode is persisted', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(voiceTranscriptionModeProvider.notifier)
        .setMode(VoiceTranscriptionMode.cloud);

    expect(
      (await SharedPreferences.getInstance()).getString(
        voiceTranscriptionModePreferenceKey,
      ),
      'cloud',
    );
  });

  test('a setting with the wrong type safely defaults to system', () async {
    SharedPreferences.setMockInitialValues({
      voiceTranscriptionModePreferenceKey: true,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(voiceTranscriptionModeProvider.notifier).ready;

    expect(
      container.read(voiceTranscriptionModeProvider),
      VoiceTranscriptionMode.system,
    );
  });
}
