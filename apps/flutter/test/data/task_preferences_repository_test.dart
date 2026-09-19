import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository_impl.dart';

void main() {
  test(
    'a late load preserves local edits and loads unrelated saved values',
    () async {
      SharedPreferences.setMockInitialValues({
        taskListStylePreferenceKey: 'classic',
        timelineHourWidthPreferenceKey: 288,
      });
      final ready = Completer<SharedPreferences?>();
      final repository = LocalTaskPreferencesRepository(
        PreferencesService(() => ready.future),
      );
      addTearDown(repository.dispose);
      final loading = repository.load();
      final saving = repository.setListStyle(TaskListStyle.modern);
      ready.complete(await SharedPreferences.getInstance());
      (await loading).getOrThrow();
      (await saving).getOrThrow();
      expect(repository.state.listStyle, TaskListStyle.modern);
      expect(repository.state.hourWidth, 288);
      (await repository.setVisibleHours(60, 120)).getOrThrow();
      (await repository.setVisibleHours(120, 60)).getOrThrow();
      expect(
        repository.state.visibleHours,
        const TimelineVisibleHours(startMinutes: 60, endMinutes: 120),
      );
      (await repository.toggleCollapsedProject('work')).getOrThrow();
      expect(
        () => repository.state.collapsedProjectIds.add('other'),
        throwsUnsupportedError,
      );
    },
  );
}
