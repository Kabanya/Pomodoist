import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_blocking.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:timezone/data/latest.dart' as tz;

final today = DateTime.utc(2026, 11, 2, 12);
TaskItem task(
  String id, {
  List<String> needs = const [],
  int priority = 4,
  String? parent,
  String? scope,
  String project = 'inbox',
  List<String> assignees = const [],
  bool done = false,
  bool deleted = false,
  TaskSchedule? schedule,
}) => TaskItem(
  id: id,
  userId: 'me',
  content: id,
  projectId: project,
  priority: priority,
  status: done ? 'completed' : 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: deleted,
  createdAt: today,
  updatedAt: today,
  parentId: parent,
  scopeId: scope,
  assigneeIds: assignees,
  prerequisiteIds: needs,
  dueJson: schedule?.toJsonString(),
);
TaskBlockingPolicy policy(
  List<TaskItem> tasks, {
  bool cascade = false,
  Map<String, UrgentTaskSelection> urgent = const {},
  String zone = 'UTC',
}) => TaskBlockingPolicy(
  tasks: tasks,
  actorId: 'me',
  now: today,
  priorityCascadeEnabled: cascade,
  urgentSelections: urgent,
  timeZone: zone,
);

void main() {
  setUpAll(tz.initializeTimeZones);
  test('all predecessors and inherited parent dependencies are required', () {
    final p = policy([
      task('a'),
      task('b', needs: ['a']),
      task('c', parent: 'b'),
    ]);
    expect(p.availability('b').blockingTaskIds, ['a']);
    expect(p.availability('c').canComplete, isFalse);
    expect(p.availability('c').canStartFocus, isTrue);
    expect(p.availability('a').canStartFocus, isTrue);
  });
  test('Focus still rejects missing, deleted and completed tasks', () {
    final p = policy([
      task('deleted', deleted: true),
      task('done', done: true),
    ]);
    for (final id in ['missing', 'deleted', 'done']) {
      expect(p.availability(id).canStartFocus, isFalse);
    }
  });
  test('deleted and completed predecessors release dependencies', () {
    final p = policy([
      task('a', deleted: true),
      task('b', done: true),
      task('c', needs: ['a', 'b']),
    ]);
    expect(p.availability('c').canComplete, isTrue);
  });
  test('validates cycles, ancestor links and shared project boundaries', () {
    final p = policy([
      task('a'),
      task('b', needs: ['a']),
      task('c', parent: 'a'),
      task('s', scope: 'scope', project: 'shared', assignees: ['me']),
    ]);
    expect(() => p.validateDependencies('a', ['b']), throwsArgumentError);
    expect(() => p.validateDependencies('a', ['c']), throwsArgumentError);
    expect(() => p.validateDependencies('s', ['a']), throwsArgumentError);
    expect(() => p.validateDependencies('a', ['missing']), throwsArgumentError);
  });
  test('cascade promotes prerequisites without changing stored priority', () {
    final p = policy([
      task(
        'p1',
        priority: 1,
        needs: ['p4'],
        schedule: TaskSchedule.allDay(today),
      ),
      task('p4'),
      task('p2', priority: 2, schedule: TaskSchedule.allDay(today)),
      task('future'),
    ], cascade: true);
    expect(p.availability('p4').canStartFocus, isTrue);
    expect(p.availability('p2').reasons, contains(TaskBlockReason.priority));
    expect(p.availability('p2').canStartFocus, isTrue);
    expect(p.availability('p2').canComplete, isFalse);
    expect(p.availability('future').canStartFocus, isTrue);
    expect(p.tasks['p4']!.priority, 4);
  });
  test('cascade skips a P1 waiting on another assignee', () {
    final p = policy([
      task(
        'p1',
        scope: 's',
        project: 'work',
        assignees: ['me'],
        priority: 1,
        needs: ['other'],
        schedule: TaskSchedule.allDay(today),
      ),
      task('other', scope: 's', project: 'work', assignees: ['colleague']),
      task(
        'p2',
        scope: 's',
        project: 'work',
        assignees: ['me'],
        priority: 2,
        schedule: TaskSchedule.allDay(today),
      ),
    ], cascade: true);
    expect(p.availability('p1').canComplete, isFalse);
    expect(p.availability('p1').canStartFocus, isTrue);
    expect(p.availability('p2').canStartFocus, isTrue);
  });
  test(
    'personal urgent blocks completion but permits Focus with or without a task',
    () {
      final p = policy(
        [
          task('hot', needs: ['step']),
          task('step'),
          task('other', project: 'elsewhere'),
        ],
        urgent: {'personal': const UrgentTaskSelection(taskId: 'hot')},
      );
      expect(p.availability('step').canStartFocus, isTrue);
      expect(p.availability('other').reasons, contains(TaskBlockReason.urgent));
      expect(p.availability(null).canStartFocus, isTrue);
      expect(p.availability('other').canStartFocus, isTrue);
      expect(p.availability('other').canComplete, isFalse);
    },
  );
  test('shared urgent affects only actor assigned tasks in that project', () {
    final p = policy(
      [
        task('hot', scope: 's', project: 'work', assignees: ['me', 'them']),
        task('mine', scope: 's', project: 'work', assignees: ['me']),
        task('theirs', scope: 's', project: 'work', assignees: ['them']),
        task('personal'),
      ],
      urgent: {'project:work': const UrgentTaskSelection(taskId: 'hot')},
    );
    expect(p.availability('mine').canComplete, isFalse);
    expect(p.availability('mine').canStartFocus, isTrue);
    expect(p.availability('theirs').canStartFocus, isTrue);
    expect(p.availability('personal').canStartFocus, isTrue);
    expect(p.availability(null).canStartFocus, isTrue);
  });
  test(
    'future urgent stays dormant and recurring selection follows series',
    () {
      final recurrence = TaskRecurrence(
        seriesId: 'series',
        interval: 1,
        unit: TaskRecurrenceUnit.day,
      );
      final p = policy(
        [
          task(
            'old',
            done: true,
            schedule: TaskSchedule.allDay(today, recurrence: recurrence),
          ),
          task(
            'next',
            schedule: TaskSchedule.allDay(
              today.add(const Duration(days: 1)),
              recurrence: recurrence,
            ),
          ),
          task('other'),
        ],
        urgent: {
          'personal': const UrgentTaskSelection(
            taskId: 'old',
            seriesId: 'series',
          ),
        },
      );
      expect(p.availability('other').canStartFocus, isTrue);
      expect(p.selectionFor(p.tasks['next']!), isNotNull);
    },
  );
  test('completion may satisfy internal dependencies atomically', () {
    final p = policy([
      task('root'),
      task('a', parent: 'root'),
      task('b', parent: 'root', needs: ['a']),
    ]);
    expect(p.availability('b').canComplete, isFalse);
    expect(p.availability('root').canComplete, isTrue);
    final outside = policy([
      task('root'),
      task('a', parent: 'root', needs: ['external']),
      task('external'),
    ]);
    expect(outside.availability('root').canComplete, isFalse);
  });
  test('calendar boundaries use the account timezone', () {
    final p = policy(
      [
        task('hot', schedule: TaskSchedule.allDay(DateTime(2026, 11, 3))),
        task('other'),
      ],
      zone: 'Pacific/Auckland',
      urgent: {'personal': const UrgentTaskSelection(taskId: 'hot')},
    );
    expect(p.availability('other').canComplete, isFalse);
  });
  test(
    'completing urgent occurrence does not wait for its next overdue occurrence',
    () {
      final schedule = TaskSchedule.allDay(
        today.subtract(const Duration(days: 2)),
        recurrence: const TaskRecurrence(
          interval: 1,
          unit: TaskRecurrenceUnit.day,
          seriesId: 's',
        ),
      );
      final p = policy(
        [
          task('first', schedule: schedule),
          task('next', schedule: schedule.nextOccurrence()),
        ],
        urgent: {
          'personal': const UrgentTaskSelection(taskId: 'first', seriesId: 's'),
        },
      );
      expect(p.availability('first').canComplete, isTrue);
      expect(p.availability('next').canComplete, isFalse);
      final after = policy(
        [
          task('first', schedule: schedule, done: true),
          task('next', schedule: schedule.nextOccurrence()),
        ],
        urgent: {
          'personal': const UrgentTaskSelection(taskId: 'first', seriesId: 's'),
        },
      );
      expect(after.selectionFor(after.tasks['next']!), isNotNull);
    },
  );

  test(
    'shared urgency waits for colleagues and remains private to the choosing actor',
    () {
      final tasks = [
        task(
          'urgent',
          scope: 's',
          project: 'p',
          assignees: ['me', 'them'],
          needs: ['colleague'],
        ),
        task('colleague', scope: 's', project: 'p', assignees: ['them']),
        task('other', scope: 's', project: 'p', assignees: ['me', 'them']),
      ];
      final p = policy(
        tasks,
        cascade: true,
        urgent: {'project:p': const UrgentTaskSelection(taskId: 'urgent')},
      );
      expect(p.availability('other').canComplete, isFalse);
      expect(p.availability('urgent').blockingTaskIds, contains('colleague'));
      final colleague = TaskBlockingPolicy(
        tasks: tasks,
        actorId: 'them',
        now: today,
      );
      expect(colleague.availability('other').canStartFocus, isTrue);
      final unassigned = policy(
        [task('urgent', scope: 's', project: 'p'), tasks.last],
        urgent: {'project:p': const UrgentTaskSelection(taskId: 'urgent')},
      );
      expect(unassigned.availability('other').canStartFocus, isTrue);
    },
  );
}
