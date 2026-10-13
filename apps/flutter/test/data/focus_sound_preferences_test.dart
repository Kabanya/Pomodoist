import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final stored in [null, 'unknown', 42]) {
    test(
      'missing or invalid stored sound family defaults to kalimba: $stored',
      () async {
        SharedPreferences.setMockInitialValues({'focus.soundSet': ?stored});
        final repository = StoredFocusPreferencesRepository(
          PreferencesService(() => SharedPreferences.getInstance()),
        );
        addTearDown(repository.dispose);
        (await repository.ready).getOrThrow();
        expect(repository.state.soundSet, FocusSoundSet.softKalimba);
      },
    );
  }

  test(
    'sound family persists independently of other focus settings and clears',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = PreferencesService(() => SharedPreferences.getInstance());
      final repository = StoredFocusPreferencesRepository(service);
      addTearDown(repository.dispose);
      (await repository.ready).getOrThrow();
      (await repository.setSoundSet(FocusSoundSet.neonPulse)).getOrThrow();
      (await repository.setTimerStyle(FocusTimerVisualStyle.bar)).getOrThrow();
      (await repository.setCelebrationEnabled(false)).getOrThrow();
      expect(repository.state.soundSet, FocusSoundSet.neonPulse);
      expect(
        (await SharedPreferences.getInstance()).getString('focus.soundSet'),
        'neon_pulse',
      );
      final restored = StoredFocusPreferencesRepository(service);
      addTearDown(restored.dispose);
      (await restored.ready).getOrThrow();
      expect(restored.state.soundSet, FocusSoundSet.neonPulse);
      expect(restored.state.timerStyle, FocusTimerVisualStyle.bar);
      (await restored.clear()).getOrThrow();
      expect(restored.state.soundSet, FocusSoundSet.softKalimba);
      expect(
        (await SharedPreferences.getInstance()).containsKey('focus.soundSet'),
        isFalse,
      );
    },
  );

  test(
    'a selection made during hydration wins over the stored family',
    () async {
      final service = ControlledPreferences();
      final repository = StoredFocusPreferencesRepository(service);
      addTearDown(repository.dispose);
      final loading = repository.ready;
      (await repository.setSoundSet(FocusSoundSet.orbitBloom)).getOrThrow();
      service.reading.complete(const Success({'focus.soundSet': 'neon_pulse'}));
      (await loading).getOrThrow();
      expect(repository.state.soundSet, FocusSoundSet.orbitBloom);
    },
  );

  test(
    'failed persistence leaves the previously restored family selected',
    () async {
      final service = ControlledPreferences();
      final repository = StoredFocusPreferencesRepository(service);
      addTearDown(repository.dispose);
      service.reading.complete(
        const Success({'focus.soundSet': 'orbit_bloom'}),
      );
      (await repository.ready).getOrThrow();
      service.failWrites = true;
      expect(
        await repository.setSoundSet(FocusSoundSet.neonPulse),
        isA<Failure<void>>(),
      );
      expect(repository.state.soundSet, FocusSoundSet.orbitBloom);
    },
  );

  test('failed selection during hydration retains the stored family', () async {
    final service = ControlledPreferences()
      ..writing = Completer<Result<void>>();
    final repository = StoredFocusPreferencesRepository(service);
    addTearDown(repository.dispose);
    final loading = repository.ready;
    final saving = repository.setSoundSet(FocusSoundSet.neonPulse);
    service.reading.complete(const Success({'focus.soundSet': 'orbit_bloom'}));
    (await loading).getOrThrow();
    service.writing!.complete(
      Failure(StateError('disk full'), StackTrace.current),
    );
    expect(await saving, isA<Failure<void>>());
    expect(repository.state.soundSet, FocusSoundSet.orbitBloom);
  });
}

class ControlledPreferences extends PreferencesService {
  ControlledPreferences() : super(() async => null);
  final reading = Completer<Result<Map<String, Object>>>();
  bool failWrites = false;
  Completer<Result<void>>? writing;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) => reading.future;
  @override
  Future<Result<void>> write(Map<String, Object?> values) async =>
      writing != null
      ? writing!.future
      : failWrites
      ? Failure(StateError('disk full'), StackTrace.current)
      : const Success(null);
}
