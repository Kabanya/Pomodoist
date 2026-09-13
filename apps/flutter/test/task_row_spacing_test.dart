import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Replace disk writes to exercise the same persistence failure path as themes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> loadedContainer() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(taskRowSpacingProvider);
    await container.read(sharedPreferencesProvider.future);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  test('missing and invalid preferences default to comfortable', () async {
    for (final stored in [null, 'unknown', 42]) {
      SharedPreferences.setMockInitialValues({
        taskRowSpacingPreferenceKey: ?stored,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(taskRowSpacingProvider),
        TaskRowSpacing.comfortable,
      );
      await container.read(sharedPreferencesProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(taskRowSpacingProvider),
        TaskRowSpacing.comfortable,
      );
    }
  });

  test(
    'every spacing choice is saved and restored in a new container',
    () async {
      final container = await loadedContainer();
      for (final spacing in TaskRowSpacing.values) {
        await container
            .read(taskRowSpacingProvider.notifier)
            .setSpacing(spacing);
        expect(container.read(taskRowSpacingProvider), spacing);
        expect(
          (await SharedPreferences.getInstance()).getString(
            taskRowSpacingPreferenceKey,
          ),
          spacing.name,
        );
        expect((await loadedContainer()).read(taskRowSpacingProvider), spacing);
      }
    },
  );

  test(
    'late preference load cannot replace an explicit default choice',
    () async {
      SharedPreferences.setMockInitialValues({
        taskRowSpacingPreferenceKey: 'compact',
      });
      final loading = Completer<SharedPreferences?>();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => loading.future),
        ],
      );
      addTearDown(container.dispose);
      container.read(taskRowSpacingProvider);
      final save = container
          .read(taskRowSpacingProvider.notifier)
          .setSpacing(TaskRowSpacing.comfortable);
      loading.complete(await SharedPreferences.getInstance());
      await save;
      expect(
        container.read(taskRowSpacingProvider),
        TaskRowSpacing.comfortable,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          taskRowSpacingPreferenceKey,
        ),
        'comfortable',
      );
    },
  );

  test(
    'spacing and row style remain independent when changed and restored',
    () async {
      final container = await loadedContainer();
      final styles = container.read(taskListStyleProvider.notifier);
      await styles.setStyle(TaskListStyle.classic);
      await container
          .read(taskRowSpacingProvider.notifier)
          .setSpacing(TaskRowSpacing.spacious);
      expect(container.read(taskListStyleProvider), TaskListStyle.classic);
      await styles.setStyle(TaskListStyle.modern);
      expect(container.read(taskRowSpacingProvider), TaskRowSpacing.spacious);
      final restored = await loadedContainer();
      restored.read(taskListStyleProvider);
      await Future<void>.delayed(Duration.zero);
      expect(restored.read(taskListStyleProvider), TaskListStyle.modern);
      expect(restored.read(taskRowSpacingProvider), TaskRowSpacing.spacious);
    },
  );

  test(
    'failed writes report an error, retain the choice, and allow retry',
    () async {
      final container = await loadedContainer();
      final originalStore = SharedPreferencesStorePlatform.instance;
      final store = _FailingStore(await originalStore.getAll());
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = originalStore,
      );
      final controller = container.read(taskRowSpacingProvider.notifier);

      await expectLater(
        controller.setSpacing(TaskRowSpacing.compact),
        throwsStateError,
      );
      expect(container.read(taskRowSpacingProvider), TaskRowSpacing.compact);
      expect(
        (await store.getAll())['flutter.$taskRowSpacingPreferenceKey'],
        isNull,
      );
      store.fail = false;
      await controller.setSpacing(TaskRowSpacing.compact);
      expect(
        (await store.getAll())['flutter.$taskRowSpacingPreferenceKey'],
        'compact',
      );
    },
  );

  test('spacing remains usable without a preferences plugin', () async {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);
    await container
        .read(taskRowSpacingProvider.notifier)
        .setSpacing(TaskRowSpacing.spacious);
    expect(container.read(taskRowSpacingProvider), TaskRowSpacing.spacious);
  });

  test(
    'a read failure keeps the default and later save errors propagate',
    () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith(
            (ref) async => throw StateError('Storage unavailable'),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(taskRowSpacingProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(taskRowSpacingProvider),
        TaskRowSpacing.comfortable,
      );
      await expectLater(
        container
            .read(taskRowSpacingProvider.notifier)
            .setSpacing(TaskRowSpacing.spacious),
        throwsStateError,
      );
      expect(container.read(taskRowSpacingProvider), TaskRowSpacing.spacious);
    },
  );
}

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore(super.data) : super.withData();
  bool fail = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail && key == 'flutter.$taskRowSpacingPreferenceKey') return false;
    return super.setValue(valueType, key, value);
  }
}
