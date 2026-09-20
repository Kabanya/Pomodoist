import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_details_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_view_model.dart';
import 'package:pomodoist/utils/clock.dart';

void main() {
  test('retained instances keep independent drafts', () async {
    final container = _container();
    addTearDown(container.dispose);
    final firstIdentity = Object();
    final secondIdentity = Object();
    final firstListener = container.listen(
      quickAddViewModelProvider(firstIdentity),
      (_, _) {},
      fireImmediately: true,
    );
    final secondListener = container.listen(
      quickAddViewModelProvider(secondIdentity),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(firstListener.close);
    addTearDown(secondListener.close);
    final first = container.read(
      quickAddViewModelProvider(firstIdentity).notifier,
    );
    final second = container.read(
      quickAddViewModelProvider(secondIdentity).notifier,
    );

    first.updateDraft('Buy milk');
    second.updateDraft('Plan the day');
    expect(first.state.draft, 'Buy milk');
    expect(second.state.draft, 'Plan the day');

    first.clearDraft();
    expect(first.state.draft, isEmpty);
    expect(second.state.draft, 'Plan the day');

    firstListener.close();
    await pumpEventQueue();
    expect(
      container.read(quickAddViewModelProvider(firstIdentity)).draft,
      isEmpty,
    );
    expect(
      container.read(quickAddViewModelProvider(secondIdentity)).draft,
      'Plan the day',
    );
  });

  test('shared persisted values are visible to every Quick Add view', () async {
    final projects = StreamController<List<ProjectItem>>();
    addTearDown(projects.close);
    final container = _container(projects: projects.stream);
    addTearDown(container.dispose);
    final firstIdentity = Object();
    final secondIdentity = Object();
    final firstListener = container.listen(
      quickAddViewModelProvider(firstIdentity),
      (_, _) {},
      fireImmediately: true,
    );
    final secondListener = container.listen(
      quickAddViewModelProvider(secondIdentity),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(firstListener.close);
    addTearDown(secondListener.close);
    final detailsListener = container.listen(
      quickAddDetailsViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(detailsListener.close);
    container
        .read(quickAddViewModelProvider(firstIdentity).notifier)
        .updateDraft('First draft');
    container
        .read(quickAddViewModelProvider(secondIdentity).notifier)
        .updateDraft('Second draft');

    projects.add([_project('p1'), _project('p2', archived: true)]);
    await pumpEventQueue();
    final details = container.read(quickAddDetailsViewModelProvider);
    expect(details.allProjects.map((project) => project.id), ['p1', 'p2']);
    expect(details.projects.map((project) => project.id), ['p1']);
    expect(
      container.read(quickAddViewModelProvider(firstIdentity)).draft,
      'First draft',
    );
    expect(
      container.read(quickAddViewModelProvider(secondIdentity)).draft,
      'Second draft',
    );
  });
}

ProviderContainer _container({Stream<List<ProjectItem>>? projects}) {
  final now = DateTime(2026, 9, 20, 9);
  return ProviderContainer(
    overrides: [
      projectsProvider.overrideWith(
        (ref) => projects ?? Stream.value(const <ProjectItem>[]),
      ),
      labelsProvider.overrideWith((ref) => Stream.value(const <LabelItem>[])),
      quickAddParserProvider.overrideWithValue(const QuickAddParser()),
      focusTickerProvider.overrideWith((ref) => Stream.value(now)),
      clockProvider.overrideWithValue(FixedClock(now)),
    ],
  );
}

ProjectItem _project(String id, {bool archived = false}) => ProjectItem(
  id: id,
  userId: 'user',
  name: id,
  isArchived: archived,
  orderKey: id,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
