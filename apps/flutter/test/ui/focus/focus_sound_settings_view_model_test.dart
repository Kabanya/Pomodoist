import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/focus_sound_dependencies.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/audio/focus_sound_preview_player.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';
import 'package:pomodoist/ui/settings/view_models/focus_sound_settings_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'first Listen waits for hydration and previews the restored family',
    () async {
      final pending = Completer<Result<Map<String, Object>>>();
      final harness = Harness(reading: pending);
      addTearDown(harness.dispose);
      final playing = harness.controller.preview();
      expect(harness.preview.families, isEmpty);
      pending.complete(const Success({'focus.soundSet': 'orbit_bloom'}));
      await playing;
      await harness.container.pump();
      expect(harness.preview.families, [FocusSoundSet.orbitBloom]);
      expect(harness.state.soundSet, FocusSoundSet.orbitBloom);
      expect(harness.preview.stops, 0);
    },
  );
  test(
    'settings saves selection and auditions it without changing preferences',
    () async {
      final harness = Harness();
      addTearDown(harness.dispose);
      await harness.controller.setSoundSet(FocusSoundSet.neonPulse);
      expect(harness.state.soundSet, FocusSoundSet.neonPulse);
      expect(harness.preferences.saved['focus.soundSet'], 'neon_pulse');
      final writes = harness.preferences.writes;
      await harness.controller.preview();
      expect(harness.preview.families, [FocusSoundSet.neonPulse]);
      expect(harness.preferences.writes, writes);
      await harness.controller.setSoundSet(FocusSoundSet.orbitBloom);
      expect(harness.preview.stops, greaterThanOrEqualTo(2));
      expect(harness.state.soundSet, FocusSoundSet.orbitBloom);
    },
  );

  test(
    'failed saving preserves the previous selection and releases controls',
    () async {
      final harness = Harness();
      addTearDown(harness.dispose);
      await harness.controller.setSoundSet(FocusSoundSet.orbitBloom);
      harness.preferences.failWrites = true;
      await expectLater(
        harness.controller.setSoundSet(FocusSoundSet.neonPulse),
        throwsStateError,
      );
      expect(harness.state.soundSet, FocusSoundSet.orbitBloom);
      expect(harness.state.isSaving, isFalse);
    },
  );

  test('preview failure is exposed and clears when changing family', () async {
    final harness = Harness();
    addTearDown(harness.dispose);
    harness.preview.failPlayback = true;
    await harness.controller.preview();
    expect(harness.state.previewFailed, isTrue);
    await harness.controller.setSoundSet(FocusSoundSet.neonPulse);
    expect(harness.state.previewFailed, isFalse);
  });

  test('leaving the section ignores a late preview failure', () async {
    final harness = Harness();
    addTearDown(harness.dispose);
    final pending = Completer<void>();
    harness.preview.pending = pending.future;
    final playing = harness.controller.preview();
    await Future<void>.delayed(Duration.zero);
    await harness.controller.stopPreview();
    pending.completeError(StateError('cancelled preparation'));
    await playing;
    expect(harness.state.previewFailed, isFalse);
    expect(harness.preview.stops, 1);
  });
}

class Harness {
  Harness({Completer<Result<Map<String, Object>>>? reading}) {
    preferences.reading = reading;
    repository = StoredFocusPreferencesRepository(preferences);
    container = ProviderContainer(
      overrides: [
        focusPreferencesRepositoryProvider.overrideWithValue(repository),
        focusSoundPreviewPlayerProvider.overrideWithValue(preview),
      ],
    );
    subscription = container.listen(
      focusSoundSettingsViewModelProvider,
      (_, _) {},
    );
  }
  final preferences = MemoryPreferences();
  final preview = RecordingPreview();
  late final StoredFocusPreferencesRepository repository;
  late final ProviderContainer container;
  late final ProviderSubscription<FocusSoundSettingsState> subscription;
  FocusSoundSettingsViewModel get controller =>
      container.read(focusSoundSettingsViewModelProvider.notifier);
  FocusSoundSettingsState get state =>
      container.read(focusSoundSettingsViewModelProvider);
  void dispose() {
    subscription.close();
    container.dispose();
    repository.dispose();
  }
}

class MemoryPreferences extends PreferencesService {
  MemoryPreferences() : super(() async => null);
  final saved = <String, Object?>{};
  int writes = 0;
  bool failWrites = false;
  Completer<Result<Map<String, Object>>>? reading;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async => reading != null
      ? reading!.future
      : Success({
          for (final entry in saved.entries)
            if (entry.value != null) entry.key: entry.value!,
        });
  @override
  Future<Result<void>> write(Map<String, Object?> values) async {
    if (failWrites) return Failure(StateError('disk full'), StackTrace.current);
    writes++;
    saved.addAll(values);
    return const Success(null);
  }
}

class RecordingPreview implements FocusSoundPreviewPlayer {
  final families = <FocusSoundSet>[];
  int stops = 0;
  bool failPlayback = false;
  Future<void>? pending;
  @override
  Future<void> preview(FocusSoundSet family) async {
    families.add(family);
    await pending;
    if (failPlayback) throw StateError('audio unavailable');
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
}
