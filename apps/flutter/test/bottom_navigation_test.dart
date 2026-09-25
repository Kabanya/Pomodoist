import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/settings/view_models/bottom_navigation_view_model.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_layout.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'defaults, empty selection, invalid and duplicate stored destinations',
    () {
      final defaults = BottomNavigationPreferences();
      expect(defaults.style, BottomNavigationStyle.soft);
      expect(defaults.destinations, [
        BottomNavigationDestination.today,
        BottomNavigationDestination.upcoming,
        BottomNavigationDestination.focus,
        BottomNavigationDestination.inbox,
        BottomNavigationDestination.projects,
      ]);
      expect(
        BottomNavigationPreferences.decode(null).destinations,
        defaults.destinations,
      );
      expect(
        BottomNavigationPreferences.decode('bad').destinations,
        defaults.destinations,
      );
      expect(
        BottomNavigationPreferences.decode('{"destinations":[]}').destinations,
        isEmpty,
      );
      final restored = BottomNavigationPreferences.decode(
        jsonEncode({
          'style': 'labels',
          'destinations': [
            'calendar',
            'calendar',
            'missing',
            42,
            'focus',
            'today',
            'inbox',
            'reports',
            'search',
          ],
        }),
      );
      expect(restored.style, BottomNavigationStyle.labels);
      expect(restored.destinations.map((d) => d.name), [
        'calendar',
        'focus',
        'today',
        'inbox',
        'reports',
      ]);
      expect(
        BottomNavigationPreferences.decode(restored.encode()).destinations,
        restored.destinations,
      );
    },
  );

  test(
    'edits enforce five unique destinations and preserve the original draft',
    () {
      final original = BottomNavigationPreferences();
      expect(
        original.add(BottomNavigationDestination.calendar).destinations,
        original.destinations,
      );
      final edited = original
          .remove(BottomNavigationDestination.today)
          .add(BottomNavigationDestination.calendar)
          .move(4, 0);
      expect(edited.destinations.first, BottomNavigationDestination.calendar);
      expect(original.destinations.first, BottomNavigationDestination.today);
      expect(
        edited.add(BottomNavigationDestination.calendar).destinations.length,
        5,
      );
      expect(edited.move(0, -1).destinations, edited.destinations);
      expect(edited.copyWith(destinations: []).destinations, isEmpty);
    },
  );

  test(
    'route matching follows destination identity and exact path boundaries',
    () {
      final prefs = BottomNavigationPreferences(
        destinations: [
          BottomNavigationDestination.projects,
          BottomNavigationDestination.reports,
        ],
      );
      expect(
        prefs.selectedFor('/project/abc?task=123'),
        BottomNavigationDestination.projects,
      );
      expect(
        prefs.selectedFor('/projects'),
        BottomNavigationDestination.projects,
      );
      expect(
        prefs.selectedFor('/reports/achievements'),
        BottomNavigationDestination.reports,
      );
      expect(prefs.selectedFor('/projects-other'), isNull);
      expect(prefs.selectedFor('/today'), isNull);
      expect(
        prefs
            .remove(BottomNavigationDestination.projects)
            .selectedFor('/project/abc'),
        isNull,
      );
    },
  );

  test(
    'layout remains compact only for soft navigation with one to three items',
    () {
      for (var count = 0; count <= 5; count++) {
        final soft = bottomNavigationLayout(BottomNavigationStyle.soft, count);
        final labels = bottomNavigationLayout(
          BottomNavigationStyle.labels,
          count,
        );
        expect(soft.expands, count >= 4);
        expect(soft.labelsBelow, isFalse);
        expect(labels.expands, count > 0);
        expect(labels.labelsBelow, count >= 3);
      }
    },
  );

  test(
    'save publishes only after persistence and restores an empty panel',
    () async {
      final repository = _Preferences();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(bottomNavigationProvider.future);
      repository.pendingWrite = Completer<Result<void>>();
      final next = BottomNavigationPreferences(
        style: BottomNavigationStyle.labels,
        destinations: [],
      );
      final save = container.read(bottomNavigationProvider.notifier).save(next);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(bottomNavigationProvider).requireValue.destinations,
        hasLength(5),
      );
      repository.pendingWrite!.complete(const Result.ok(null));
      await save;
      expect(
        container.read(bottomNavigationProvider).requireValue.destinations,
        isEmpty,
      );
      final restored = _container(repository);
      addTearDown(restored.dispose);
      expect(
        (await restored.read(bottomNavigationProvider.future)).destinations,
        isEmpty,
      );
      expect(
        restored.read(bottomNavigationProvider).requireValue.style,
        BottomNavigationStyle.labels,
      );
    },
  );

  test(
    'failed save retains persisted selection and draft can be retried',
    () async {
      final repository = _Preferences()..failWrite = true;
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(bottomNavigationProvider.future);
      final draft = BottomNavigationPreferences(destinations: []);
      final controller = container.read(bottomNavigationProvider.notifier);
      await expectLater(controller.save(draft), throwsStateError);
      expect(
        container.read(bottomNavigationProvider).requireValue.destinations,
        hasLength(5),
      );
      expect(draft.destinations, isEmpty);
      repository.failWrite = false;
      await controller.save(draft);
      expect(
        container.read(bottomNavigationProvider).requireValue.destinations,
        isEmpty,
      );
    },
  );

  test('initial load cannot overwrite a newer save', () async {
    final repository = _Preferences()
      ..pendingRead = Completer<Result<Map<String, Object>>>();
    final container = _container(repository);
    addTearDown(container.dispose);
    final save = container
        .read(bottomNavigationProvider.notifier)
        .save(
          BottomNavigationPreferences(
            destinations: [BottomNavigationDestination.calendar],
          ),
        );
    repository.pendingRead!.complete(
      Result.ok({
        bottomNavigationPreferenceKey: BottomNavigationPreferences().encode(),
      }),
    );
    await save;
    expect(container.read(bottomNavigationProvider).requireValue.destinations, [
      BottomNavigationDestination.calendar,
    ]);
  });
}

ProviderContainer _container(_Preferences repository) => ProviderContainer(
  overrides: [preferencesRepositoryProvider.overrideWithValue(repository)],
);

class _Preferences implements PreferencesRepository {
  final values = <String, Object>{};
  bool failWrite = false;
  Completer<Result<Map<String, Object>>>? pendingRead;
  Completer<Result<void>>? pendingWrite;

  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async => pendingRead == null
      ? Result.ok(Map.of(values))
      : await pendingRead!.future;

  @override
  Future<Result<void>> write(Map<String, Object?> next) async {
    if (failWrite) {
      return Result.error(
        StateError('Storage unavailable'),
        StackTrace.current,
      );
    }
    if (pendingWrite != null) {
      final result = await pendingWrite!.future;
      if (result is Failure<void>) return result;
    }
    for (final entry in next.entries) {
      if (entry.value != null) values[entry.key] = entry.value!;
    }
    return const Result.ok(null);
  }
}
