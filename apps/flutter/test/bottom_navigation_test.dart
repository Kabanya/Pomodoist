import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/settings/view_models/bottom_navigation_view_model.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_layout.dart';
import 'package:pomodoist/ui/core/widgets/app_bottom_navigation.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test('replacing a tab preserves count, order, style and the original', () {
    for (var count = 1; count <= bottomNavigationMaxDestinations; count++) {
      final original = BottomNavigationPreferences(
        style: BottomNavigationStyle.labels,
        destinations: BottomNavigationPreferences.defaultDestinations.take(
          count,
        ),
      );
      for (final current in original.destinations) {
        for (final replacement in BottomNavigationDestination.values) {
          final edited = original.replace(current, replacement);
          final expected = [...original.destinations];
          final index = expected.indexOf(current);
          final existing = expected.indexOf(replacement);
          expected[index] = replacement;
          if (existing >= 0) expected[existing] = current;
          expect(edited.destinations, expected);
          expect(edited.destinations.toSet(), hasLength(count));
          expect(edited.style, BottomNavigationStyle.labels);
          expect(
            original.destinations,
            BottomNavigationPreferences.defaultDestinations.take(count),
          );
        }
      }
    }
  });

  test('replacing an absent tab never adds one or unhides an empty panel', () {
    for (final preferences in [
      BottomNavigationPreferences(),
      BottomNavigationPreferences(destinations: []),
    ]) {
      expect(
        preferences.replace(
          BottomNavigationDestination.search,
          BottomNavigationDestination.calendar,
        ),
        same(preferences),
      );
    }
  });

  test('an empty navigation leaves no panel or motion in the shell', () {
    final navigation = AppBottomNavigation(
      preferences: BottomNavigationPreferences(destinations: []),
      selected: BottomNavigationDestination.today,
      onSelected: (_) => fail('An empty navigation cannot select a route.'),
    );
    final panel = navigation.build(_UnusedContext()) as SizedBox;
    expect(panel.width, 0);
    expect(panel.height, 0);
    expect(panel.child, isNull);
  });
  test('habits can be selected without changing previous bottom tabs', () {
    final existing = BottomNavigationPreferences.decode(
      '{"destinations":["focus","calendar"]}',
    );
    expect(existing.destinations, [
      BottomNavigationDestination.focus,
      BottomNavigationDestination.calendar,
    ]);
    final selected = existing.add(BottomNavigationDestination.habits);
    expect(
      BottomNavigationPreferences.decode(
        selected.encode(),
      ).selectedFor('/habits'),
      BottomNavigationDestination.habits,
    );
    expect(
      BottomNavigationPreferences.defaultDestinations,
      isNot(contains(BottomNavigationDestination.habits)),
    );
  });
  test(
    'motion keeps the panel equal to its buttons and reveals both labels',
    () {
      final from = BottomNavigationFrame(widths: [120, 44], labels: [1, 0]);
      final to = BottomNavigationFrame(widths: [44, 100], labels: [0, 1]);
      final tween = BottomNavigationTween(begin: from, end: to);
      final middle = tween.lerp(.5);
      expect(middle.widths, [82, 72]);
      expect(middle.labels, [.5, .5]);
      expect(middle.contentWidth, 154);
      expect(tween.lerp(0), from);
      expect(tween.lerp(1), to);
      // Rebuilding with the same target must not restart a running transition.
      expect(to, BottomNavigationFrame(widths: [44, 100], labels: [0, 1]));
      final reversed = BottomNavigationTween(begin: middle, end: from);
      expect(reversed.lerp(0), middle);
      expect(reversed.lerp(.5).widths, [101, 58]);
    },
  );

  test('navigation motion preserves touch widths and full panel size', () {
    for (var count = 1; count <= 5; count++) {
      final from = BottomNavigationFrame(
        widths: [100, ...List.filled(count - 1, 44.0)],
        labels: [1, ...List.filled(count - 1, 0.0)],
        accentWidth: 100,
        accentOpacity: 1,
      );
      final to = BottomNavigationFrame(
        widths: [...List.filled(count - 1, 44.0), 100],
        labels: [...List.filled(count - 1, 0.0), 1],
        accentStart: (count - 1) * 44.0,
        accentWidth: 100,
        accentOpacity: 1,
      );
      for (final t in [0.0, .1, .5, .9, 1.0]) {
        final frame = BottomNavigationTween(begin: from, end: to).lerp(t);
        expect(frame.widths.every((width) => width >= 44), isTrue);
        expect(frame.contentWidth, closeTo(from.contentWidth, .000001));
        expect(frame.accentStart, greaterThanOrEqualTo(0));
        expect(
          frame.accentStart + frame.accentWidth,
          lessThanOrEqualTo(frame.contentWidth + .000001),
        );
      }
    }
  });

  test('sliding accent moves with widths and retargets the visible frame', () {
    final from = BottomNavigationFrame(
      widths: [120, 44],
      labels: [1, 0],
      accentStart: 0,
      accentWidth: 120,
      accentOpacity: 1,
    );
    final to = BottomNavigationFrame(
      widths: [44, 100],
      labels: [0, 1],
      accentStart: 44,
      accentWidth: 100,
      accentOpacity: 1,
    );
    final tween = BottomNavigationTween(begin: from, end: to);
    final middle = tween.lerp(.5);
    expect(middle.accentStart, 22);
    expect(middle.accentWidth, 110);
    expect(middle.accentOpacity, 1);
    expect(
      middle.accentStart + middle.accentWidth,
      lessThan(middle.contentWidth),
    );
    expect(tween.lerp(0), from);
    expect(tween.lerp(1), to);

    final reversed = BottomNavigationTween(begin: middle, end: from);
    expect(reversed.lerp(0), middle);
    expect(reversed.lerp(.5).accentStart, 11);
    expect(reversed.lerp(.5).accentWidth, 115);
    expect(
      middle,
      isNot(
        BottomNavigationFrame(widths: middle.widths, labels: middle.labels),
      ),
    );
  });

  test(
    'accent fades on unpinned routes and initial frames snap to the target',
    () {
      final selected = BottomNavigationFrame(
        widths: [44, 100],
        labels: [0, 1],
        accentStart: 44,
        accentWidth: 100,
        accentOpacity: 1,
      );
      final unpinned = BottomNavigationFrame(widths: [72, 72], labels: [0, 0]);
      final tween = BottomNavigationTween(begin: selected, end: unpinned);
      expect(tween.lerp(.5).accentOpacity, .5);
      expect(tween.lerp(1).accentOpacity, 0);
      expect(tween.lerp(1).accentWidth, 0);
      final initial = BottomNavigationTween(end: selected);
      expect(initial.lerp(0), selected);
      expect(initial.lerp(.5), selected);
    },
  );

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

class _UnusedContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Empty navigation must not read the shell context.');
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
