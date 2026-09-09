import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/settings/presentation/voice_transcription_settings_card.dart';
import 'package:pomodoist/features/voice/data/voice_transcription_mode.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Apple settings expose cloud transcription only while signed in', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_app(signedIn: false));
    await tester.pump();

    expect(find.text('Voice transcription'), findsOneWidget);
    final disabled = tester.widget<SegmentedButton<VoiceTranscriptionMode>>(
      find.byKey(const Key('settings-voice-transcription-mode')),
    );
    expect(
      disabled.segments
          .singleWhere(
            (segment) => segment.value == VoiceTranscriptionMode.cloud,
          )
          .enabled,
      isFalse,
    );
    expect(
      find.text(
        'Sign in to use cloud transcription. System transcription is active until then.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Cloud transcription sends audio to Pomodoist and requires an internet connection.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(_app(signedIn: true));
    await tester.pump();
    final enabled = tester.widget<SegmentedButton<VoiceTranscriptionMode>>(
      find.byKey(const Key('settings-voice-transcription-mode')),
    );
    expect(
      enabled.segments
          .singleWhere(
            (segment) => segment.value == VoiceTranscriptionMode.cloud,
          )
          .enabled,
      isTrue,
    );

    await tester.tap(find.text('Cloud'));
    await tester.pump();
    expect(
      (await SharedPreferences.getInstance()).getString(
        voiceTranscriptionModePreferenceKey,
      ),
      'cloud',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('non-Apple settings do not show transcription choice', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_app(signedIn: true));

    expect(find.text('Voice transcription'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _app({required bool signedIn}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: VoiceTranscriptionSettingsCard(signedIn: signedIn)),
  ),
);
