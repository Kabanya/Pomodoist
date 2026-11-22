import 'package:pomodoist/domain/models/voice/whisper_model.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/config/voice_task_route.dart';
import 'support/test_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/settings/widgets/voice_transcription_settings_card.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(loadTestAppResources);
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
    final disabled = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Cloud'),
    );
    expect(disabled.onSelected, isNull);
    expect(
      find.text(
        'Cloud transcription requires signing in with an active Pro plan.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Pomodoist sends audio to OpenRouter for transcription. An internet connection is required.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(_app(signedIn: true, managedAccess: false));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cloud'))
          .onSelected,
      isNull,
    );

    await tester.pumpWidget(_app(signedIn: true));
    await tester.pump();
    final enabled = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Cloud'),
    );
    expect(enabled.onSelected, isNotNull);

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

  testWidgets('Windows settings show both transcription choices', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_app(signedIn: true));

    expect(find.text('Voice transcription'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Built-in'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Cloud'), findsOneWidget);
    final picker = find.byType(DropdownButton<WhisperPreference>);
    expect(
      tester.widget<DropdownButton<WhisperPreference>>(picker).value,
      WhisperPreference.automatic,
    );
    for (final choice in [
      ...WhisperPreference.values.skip(1),
      WhisperPreference.automatic,
    ]) {
      await tester.tap(picker);
      await tester.pumpAndSettle();
      final label = choice == WhisperPreference.automatic
          ? 'Default (Tiny)'
          : '${choice.model.label} · ${choice.model.megabytes} MB';
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      final reloaded = ProviderContainer();
      final repository = reloaded.read(voicePreferencesRepositoryProvider);
      await repository.ready;
      expect(repository.state.whisper, choice);
      reloaded.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _app({required bool signedIn, bool managedAccess = true}) =>
    ProviderScope(
      overrides: [
        managedVoiceAccessProvider.overrideWithValue(managedAccess),
        checkWhisperModelProvider.overrideWithValue(
          (model) async => model == WhisperModel.tiny,
        ),
      ],
      child: MaterialApp(
        builder: testAppBuilder,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VoiceTranscriptionSettingsCard(signedIn: signedIn),
        ),
      ),
    );
