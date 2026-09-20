import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/kanban_board_controller.dart';

void main() {
  test(
    'selected projects preserve board order and omit missing selections',
    () {
      final now = DateTime.utc(2026);
      final a = _card('a', content: 'A', projectName: 'A').project;
      final b = _card('b', content: 'B', projectName: 'B').project;
      final c = _card('c', content: 'C', projectName: 'C').project;
      KanbanBoardSnapshot board(List<String> ids) => KanbanBoardSnapshot(
        statuses: [],
        focusedStatusId: '',
        availableProjects: [a, b, c],
        cardsByStatusId: {},
        settings: KanbanSettings(
          id: 'settings',
          userId: 'user',
          selectedProjectIds: ids,
          focusStatusLabelId: '',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final selected = container.read(
        kanbanSelectedProjectsProvider(board(['missing', c.id, a.id])),
      );
      expect(selected.map((project) => project.id), [a.id, c.id]);
      expect(() => selected.clear(), throwsUnsupportedError);
      expect(
        container.read(kanbanSelectedProjectsProvider(board([]))),
        isEmpty,
      );
      expect(
        container.read(kanbanSelectedProjectsProvider(board([b.id]))).single.id,
        b.id,
      );
    },
  );

  test('blank queries return the same card map', () {
    final cards = {
      'todo': [_card('a', content: 'Plan', projectName: 'Inbox')],
    };

    expect(filterKanbanCards(cards, '  '), same(cards));
  });

  test('filters by content and by raw or localized project name', () {
    final cards = {
      'todo': [
        _card('a', content: 'Plan release', projectName: 'Inbox'),
        _card('b', content: 'Buy milk', projectName: 'Release'),
        _card('c', content: 'Other', projectName: 'Inbox'),
      ],
    };

    expect(
      filterKanbanCards(cards, 'release')['todo']!.map((card) => card.task.id),
      ['a', 'b'],
    );
    expect(
      filterKanbanCards(
        cards,
        'входящие',
        projectTitle: (project) =>
            project.id == 'inbox' ? 'Входящие' : project.name,
      )['todo']!.map((card) => card.task.id),
      ['a', 'c'],
    );
    expect(filterKanbanCards(cards, 'missing')['todo'], isEmpty);
  });
}

KanbanCard _card(
  String id, {
  required String content,
  required String projectName,
}) {
  final now = DateTime.utc(2026);
  return KanbanCard(
    task: TaskItem(
      id: id,
      userId: 'user',
      content: content,
      projectId: projectName == 'Inbox' ? 'inbox' : 'project-$id',
      priority: 4,
      status: 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: id,
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
    ),
    project: ProjectItem(
      id: projectName == 'Inbox' ? 'inbox' : 'project-$id',
      userId: 'user',
      name: projectName,
      orderKey: id,
      createdAt: now,
      updatedAt: now,
    ),
    statusId: 'todo',
    totalSubtasks: 0,
    completedSubtasks: 0,
  );
}
