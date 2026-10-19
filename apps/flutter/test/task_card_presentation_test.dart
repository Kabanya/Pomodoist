import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/calendar_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/collaboration/view_models/task_collaboration_view_model.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';

class _Tasks implements TaskRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'comment timestamps are localized, include date, and omit missing time',
    () async {
      await initializeDateFormatting();
      final date = DateTime(2026, 9, 29, 16, 42);
      expect(collaborationCommentTime(null, 'ru'), isEmpty);
      expect(collaborationCommentTime(date, 'ru'), contains('16:42'));
      expect(collaborationCommentTime(date, 'ru'), contains('2026'));
      expect(
        collaborationCommentTime(date, 'en_US'),
        matches(RegExp(r'4:42\sPM')),
      );
      expect(
        collaborationCommentTime(date, 'ru'),
        isNot(collaborationCommentTime(date, 'en_US')),
      );
    },
  );

  test(
    'comment menu permissions exclude observers and another member author',
    () {
      final comment = CollaborationComment(
        id: 'c',
        scopeId: 's',
        taskId: 't',
        body: 'Text',
        createdBy: 'author',
      );
      for (final role in ['observer', 'member', 'administrator']) {
        final scope = SharedScope.fromJson({
          'id': 's',
          'rootProjectId': 'p',
          'ownerId': 'owner',
          'role': role,
        });
        final other = TaskCollaborationState(scope: scope, actorId: 'reader');
        expect(other.canDeleteComment(comment), role == 'administrator');
        final author = TaskCollaborationState(scope: scope, actorId: 'author');
        expect(author.canDeleteComment(comment), role != 'observer');
      }
    },
  );

  test(
    'task card follows live project names and counts and drops shared comments on personal task',
    () async {
      final now = DateTime(2026, 9, 29);
      TaskItem task(String? scope) => TaskItem(
        id: 't',
        userId: 'u',
        content: 'Task',
        projectId: 'p',
        priority: 2,
        status: 'open',
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        orderKey: 'a',
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
        scopeId: scope,
      );
      ProjectItem project(String name) => ProjectItem(
        id: 'p',
        userId: 'u',
        name: name,
        orderKey: 'a',
        createdAt: now,
        updatedAt: now,
      );
      final tasks = StreamController<TaskItem?>();
      final projects = StreamController<List<ProjectItem>>();
      final files = StreamController<int>();
      addTearDown(tasks.close);
      addTearDown(projects.close);
      addTearDown(files.close);
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(_Tasks()),
          taskProvider.overrideWith((ref, id) => tasks.stream),
          projectsProvider.overrideWith((ref) => projects.stream),
          taskDetailFileCountProvider.overrideWith((ref, id) => files.stream),
          taskPreferencesStateProvider.overrideWithValue(TaskPreferences()),
          focusPresetsProvider.overrideWith((ref) => Stream.value([])),
          activeFocusRunProvider.overrideWith((ref) => Stream.value(null)),
          activeFocusIntervalProvider.overrideWith((ref) => Stream.value(null)),
          lastFocusPresetIdProvider.overrideWithValue(null),
          calendarLinksProvider.overrideWith((ref, id) => Stream.value([])),
          googleCalendarLinkProvider.overrideWith(
            (ref, id) => Stream.value(null),
          ),
          collaborationCommentsProvider.overrideWith(
            (ref, query) => Stream.value([
              CollaborationComment(
                id: 'c',
                scopeId: query.scopeId,
                taskId: query.taskId!,
                body: 'Comment',
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = taskDetailViewModelProvider('t');
      container.listen(provider, (_, _) {});
      tasks.add(task('s'));
      projects.add([project('Launch')]);
      files.add(2);
      await pumpEventQueue();
      expect(container.read(provider).projectName, 'Launch');
      expect(container.read(provider).fileCount, 2);
      expect(container.read(provider).commentCount, 1);
      projects.add([project('Renamed')]);
      files.add(0);
      tasks.add(task(null));
      await pumpEventQueue();
      expect(container.read(provider).projectName, 'Renamed');
      expect(container.read(provider).fileCount, 0);
      expect(container.read(provider).commentCount, 0);
    },
  );
}
