import 'package:pomodoist/data/repositories/focus/focus_preferences_repository.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/focus/focus_completion_repository_impl.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'late preference restore preserves choices made while loading',
    () async {
      SharedPreferences.setMockInitialValues({
        focusViewModePreferenceKey: 'full',
        focusTimerVisualStylePreferenceKey: 'bar',
        lastFocusPresetIdPreferenceKey: 'old-preset',
      });
      final pending = Completer<SharedPreferences?>();
      final repository = StoredFocusPreferencesRepository(
        PreferencesService(() => pending.future),
      );
      addTearDown(repository.dispose);
      final loading = repository.load();
      final selection = repository.setPresetId('new-preset');
      final mode = repository.setViewMode(FocusViewMode.minimal);
      pending.complete(await SharedPreferences.getInstance());
      (await loading).getOrThrow();
      (await selection).getOrThrow();
      (await mode).getOrThrow();
      expect(repository.state.lastPresetId, 'new-preset');
      expect(repository.state.viewMode, FocusViewMode.minimal);
      expect(repository.state.timerStyle, FocusTimerVisualStyle.bar);
    },
  );

  test('preference load cannot publish after disposal', () async {
    final pending = Completer<SharedPreferences?>();
    final repository = StoredFocusPreferencesRepository(
      PreferencesService(() => pending.future),
    );
    var publications = 0;
    final subscription = repository
        .watch()
        .skip(1)
        .listen((_) => publications++);
    addTearDown(subscription.cancel);
    final loading = repository.load();
    repository.dispose();
    pending.complete(null);
    (await loading).getOrThrow();
    await Future<void>.delayed(Duration.zero);
    expect(publications, 0);
  });

  test('completion is shared, single-flight and never replayed', () {
    final repository = DefaultFocusCompletionRepository();
    addTearDown(repository.dispose);
    FocusRunCompletionEvent event(String id) => FocusRunCompletionEvent(
      runId: id,
      completedWorkIntervals: 4,
      targetWorkIntervals: 4,
      completedAt: DateTime.utc(2026, 9, 19),
    );
    repository.present(event('a'));
    expect(repository.tryBeginAction('a'), isTrue);
    expect(repository.tryBeginAction('a'), isFalse);
    repository.present(event('b'));
    repository.dismiss(runId: 'a');
    expect(repository.state?.runId, 'b');
    repository.endAction('a');
    expect(repository.tryBeginAction('b'), isTrue);
    repository.endAction('b');
    repository.dismiss(runId: 'b');
    repository.present(event('a'));
    repository.present(event('b'));
    expect(repository.state, isNull);
  });
}
