import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/focus_sound_dependencies.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';
import 'package:pomodoist/domain/services/focus_sound_preview_player.dart';

final class FocusSoundSettingsState {
  const FocusSoundSettingsState({
    required this.soundSet,
    this.isSaving = false,
    this.previewFailed = false,
  });
  final FocusSoundSet soundSet;
  final bool isSaving;
  final bool previewFailed;
}

final focusSoundSettingsViewModelProvider =
    NotifierProvider.autoDispose<
      FocusSoundSettingsViewModel,
      FocusSoundSettingsState
    >(FocusSoundSettingsViewModel.new);

class FocusSoundSettingsViewModel extends Notifier<FocusSoundSettingsState> {
  late FocusPreferencesRepository _repository;
  late FocusSoundPreviewPlayer _preview;
  int _previewGeneration = 0;
  int? _hydratingPreviewGeneration;

  @override
  FocusSoundSettingsState build() {
    _repository = ref.watch(focusPreferencesRepositoryProvider);
    _preview = ref.watch(focusSoundPreviewPlayerProvider);
    unawaited(_repository.ready);
    ref.listen(focusPreferencesStateProvider, (_, next) {
      if (next.soundSet != state.soundSet) {
        state = FocusSoundSettingsState(
          soundSet: next.soundSet,
          isSaving: state.isSaving,
        );
        if (_hydratingPreviewGeneration != _previewGeneration) {
          unawaited(stopPreview());
        }
      }
    });
    ref.onDispose(() => _previewGeneration++);
    return FocusSoundSettingsState(soundSet: _repository.state.soundSet);
  }

  Future<void> setSoundSet(FocusSoundSet soundSet) async {
    if (state.isSaving || soundSet == state.soundSet) return;
    state = FocusSoundSettingsState(soundSet: state.soundSet, isSaving: true);
    await stopPreview();
    try {
      (await _repository.setSoundSet(soundSet)).getOrThrow();
    } finally {
      if (ref.mounted) {
        state = FocusSoundSettingsState(soundSet: _repository.state.soundSet);
      }
    }
  }

  Future<void> preview() async {
    if (state.isSaving) return;
    final generation = ++_previewGeneration;
    _hydratingPreviewGeneration = generation;
    state = FocusSoundSettingsState(soundSet: state.soundSet);
    await _repository.ready;
    if (_hydratingPreviewGeneration == generation) {
      _hydratingPreviewGeneration = null;
    }
    if (!ref.mounted || generation != _previewGeneration) return;
    // Apply hydration now so its later notification cannot stop this sample.
    state = FocusSoundSettingsState(soundSet: _repository.state.soundSet);
    try {
      await _preview.preview(_repository.state.soundSet);
    } catch (_) {
      if (ref.mounted && generation == _previewGeneration) {
        state = FocusSoundSettingsState(
          soundSet: state.soundSet,
          previewFailed: true,
        );
      }
    }
  }

  Future<void> stopPreview() async {
    ++_previewGeneration;
    try {
      await _preview.stop();
    } catch (_) {
      // Leaving Settings must never depend on platform audio availability.
    }
    if (ref.mounted) {
      state = FocusSoundSettingsState(
        soundSet: state.soundSet,
        isSaving: state.isSaving,
      );
    }
  }
}
