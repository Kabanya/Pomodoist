import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unset and invalid styles use modern; saved classic loads and persists',
    () async {
      for (final stored in [null, 'unknown', 'classic']) {
        SharedPreferences.setMockInitialValues({
          taskListStylePreferenceKey: ?stored,
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(taskListStyleProvider), TaskListStyle.modern);
        await container.read(sharedPreferencesProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(taskListStyleProvider),
          stored == 'classic' ? TaskListStyle.classic : TaskListStyle.modern,
        );
        await container
            .read(taskPreferencesRepositoryProvider)
            .setListStyle(TaskListStyle.classic);
        expect(
          (await SharedPreferences.getInstance()).getString(
            taskListStylePreferenceKey,
          ),
          'classic',
        );
      }
    },
  );

  test('late preference load cannot overwrite a local selection', () async {
    SharedPreferences.setMockInitialValues({
      taskListStylePreferenceKey: 'classic',
    });
    final loading = Completer<SharedPreferences?>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => loading.future),
      ],
    );
    addTearDown(container.dispose);
    container.read(taskListStyleProvider);
    final save = container
        .read(taskPreferencesRepositoryProvider)
        .setListStyle(TaskListStyle.modern);
    loading.complete(await SharedPreferences.getInstance());
    await save;
    expect(container.read(taskListStyleProvider), TaskListStyle.modern);
    expect(
      (await SharedPreferences.getInstance()).getString(
        taskListStylePreferenceKey,
      ),
      'modern',
    );
  });
}
