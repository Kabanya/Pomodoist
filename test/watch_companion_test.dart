import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/runtime_public_config.dart';
import 'package:pomodoist/app/watch_companion.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/notifications/notification_scheduler.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/focus/data/focus_repository_impl.dart';
import 'package:pomodoist/features/planning/data/quick_add_service.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/tasks/data/task_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftSyncQueueRepository syncQueue;
  late DriftTaskRepository taskRepository;
  late DriftProjectRepository projectRepository;
  late DriftFocusRepository focusRepository;
  late WatchCompanionController controller;
  String? selectedPresetId;

  setUp(() async {
    selectedPresetId = null;
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    syncQueue = DriftSyncQueueRepository(db);
    taskRepository = DriftTaskRepository(db, syncQueue);
    projectRepository = DriftProjectRepository(db, syncQueue);
    focusRepository = DriftFocusRepository(
      db,
      syncQueue,
      _NoopNotificationScheduler(),
    );
    controller = WatchCompanionController(
      taskRepository: taskRepository,
      projectRepository: projectRepository,
      focusRepository: focusRepository,
      quickAddService: QuickAddService(
        parser: const QuickAddParser(),
        taskRepository: taskRepository,
        projectRepository: projectRepository,
      ),
      taskDecomposer: const _FakeTaskDecomposer(),
      localeProvider: () => 'en',
      selectedFocusPresetIdProvider: () => selectedPresetId,
      now: () => DateTime(2026, 5, 1, 12),
    );
  });

  tearDown(() => db.close());

  test('watch account payload uses the resolved runtime backend', () {
    final config = RuntimePublicConfig.fromBuildTimeValues(
      environment: 'production',
      release: '0123456789abcdef0123456789abcdef01234567',
      webAppUrl: 'https://app.pomodoist.com',
      supabaseUrl: 'https://ewauihswbwduvklrozke.supabase.co',
      supabaseAnonKey: 'production-anon-key',
      googleWebClientId: 'web-client.apps.googleusercontent.com',
      turnstileSiteKey: 'turnstile-public-key',
      sentryDsn: 'https://public@o12345.ingest.sentry.io/42',
    );
    final payload = watchAccountSessionPayload(
      const AccountSession(
        userId: 'user-1',
        email: 'dev@example.com',
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ),
      config,
    );

    expect(payload['signedIn'], isTrue);
    expect(payload['environment'], 'production');
    expect(payload['release'], '0123456789abcdef0123456789abcdef01234567');
    expect(payload['webAppUrl'], 'https://app.pomodoist.com');
    expect(payload['supabaseUrl'], 'https://ewauihswbwduvklrozke.supabase.co');
    expect(payload['supabaseAnonKey'], 'production-anon-key');
    expect(payload['anonKey'], 'production-anon-key');
    expect(
      payload['googleWebClientId'],
      'web-client.apps.googleusercontent.com',
    );
    expect(payload['turnstileSiteKey'], 'turnstile-public-key');
    expect(payload['sentryDsn'], 'https://public@o12345.ingest.sentry.io/42');
  });

  test(
    'builds watch snapshot with focus, task lists, and project counts',
    () async {
      await controller.handleCommand({
        'type': watchTaskCreateQuickAdd,
        'input': 'Write report 2026-05-01 p1 #Work 2p',
      });
      await controller.handleCommand({
        'type': watchTaskCreateQuickAdd,
        'input': 'Buy coffee',
      });
      await controller.handleCommand({'type': watchFocusStartDefault});

      final snapshot = await controller.buildSnapshot();
      final focus = snapshot['focus']! as Map<String, Object?>;
      final tasks = snapshot['tasks']! as Map<String, Object?>;
      final projects = snapshot['projects']! as List<Object?>;
      final today = tasks['today']! as List<Object?>;
      final inbox = tasks['inbox']! as List<Object?>;
      final byProject = tasks['byProject']! as Map<Object?, Object?>;

      expect(focus['active'], isTrue);
      expect((focus['interval']! as Map<String, Object?>)['status'], 'running');
      expect((today.first! as Map<String, Object?>)['content'], 'Write report');
      expect((inbox.first! as Map<String, Object?>)['content'], 'Buy coffee');
      expect(
        ((byProject.values.single! as List<Object?>).first!
            as Map<String, Object?>)['content'],
        'Write report',
      );
      expect(
        projects.map((project) => project! as Map<String, Object?>),
        contains(containsPair('name', 'Work')),
      );
      expect(
        projects
            .map((project) => project! as Map<String, Object?>)
            .firstWhere(
              (project) => project['name'] == 'Work',
            )['openTaskCount'],
        1,
      );
    },
  );

  test('idle snapshot uses the selected focus preset', () async {
    selectedPresetId = deepWorkPresetId;

    final snapshot = await controller.buildSnapshot();
    final focus = snapshot['focus']! as Map<String, Object?>;
    final preset = focus['preset']! as Map<String, Object?>;

    expect(focus['active'], isFalse);
    expect(focus['presetId'], deepWorkPresetId);
    expect(focus['presetName'], 'Deep Work');
    expect(preset['workSeconds'], 50 * 60);
  });

  test('idle snapshot falls back to the default focus preset', () async {
    selectedPresetId = 'missing-preset';

    final snapshot = await controller.buildSnapshot();
    final focus = snapshot['focus']! as Map<String, Object?>;
    final preset = focus['preset']! as Map<String, Object?>;

    expect(focus['active'], isFalse);
    expect(focus['presetId'], defaultPresetId);
    expect(focus['presetName'], 'Classic');
    expect(preset['workSeconds'], 25 * 60);
  });

  test('start default focus command uses the selected focus preset', () async {
    selectedPresetId = deepWorkPresetId;

    await controller.handleCommand({'type': watchFocusStartDefault});
    final interval = await focusRepository.watchActiveInterval().first;
    final run = await focusRepository.watchActiveRun().first;

    expect(run!.presetId, deepWorkPresetId);
    expect(interval!.plannedSeconds, 50 * 60);
  });

  test('task focus derives project and estimate from the task', () async {
    final created = await controller.handleCommand({
      'type': watchTaskCreateQuickAdd,
      'input': 'Write report #Work 3p',
    });
    final taskId = created['id']! as String;
    final task = await taskRepository.watchTask(taskId).first;

    final result = await controller.handleCommand({
      'type': watchFocusStartDefault,
      'presetId': deepWorkPresetId,
      'taskId': taskId,
      'projectId': 'stale-project',
      'targetWorkIntervals': 99,
    });
    final run = await focusRepository.watchActiveRun().first;
    final interval = await focusRepository.watchActiveInterval().first;

    expect(result['ok'], isTrue);
    expect(run!.taskId, taskId);
    expect(run.projectId, task!.projectId);
    expect(run.presetId, deepWorkPresetId);
    expect(run.targetWorkIntervals, 3);
    expect(interval!.taskId, taskId);
    expect(interval.projectId, task.projectId);
    expect(interval.plannedSeconds, 50 * 60);
  });

  test('task focus replaces an active run only when confirmed', () async {
    final created = await controller.handleCommand({
      'type': watchTaskCreateQuickAdd,
      'input': 'Write report #Work 2p',
    });
    final taskId = created['id']! as String;
    await controller.handleCommand({'type': watchFocusStartDefault});

    final conflict = await controller.handleCommand({
      'type': watchFocusStartDefault,
      'taskId': taskId,
    });
    expect(conflict['conflict'], isTrue);
    expect((await focusRepository.watchActiveRun().first)!.taskId, isNull);

    final replacement = await controller.handleCommand({
      'type': watchFocusStartDefault,
      'taskId': taskId,
      'replaceActive': true,
    });
    final run = await focusRepository.watchActiveRun().first;

    expect(replacement['ok'], isTrue);
    expect(run!.taskId, taskId);
    expect(run.targetWorkIntervals, 2);
  });

  test('handles smart drafts, commit, complete, and focus commands', () async {
    final drafts = await controller.handleCommand({
      'type': watchTaskDecomposeTranscript,
      'transcript': 'plan release',
      'locale': 'en',
    });
    expect(
      ((drafts['tasks']! as List<Object?>).first!
          as Map<String, Object?>)['quickAdd'],
      'Plan release today 10:00 30m',
    );

    final commit = await controller.handleCommand({
      'type': watchTaskCommitDrafts,
      'tasks': drafts['tasks'],
    });
    final ids = commit['ids']! as List<String>;
    expect(ids, hasLength(1));
    expect(await _kanbanStatusId(db, ids.first), kanbanStatusBacklogId);

    await controller.handleCommand({
      'type': watchTaskComplete,
      'id': ids.first,
    });
    expect(
      (await taskRepository.watchTask(ids.first).first)!.isCompleted,
      isTrue,
    );
    expect(await _kanbanStatusId(db, ids.first), kanbanStatusDoneId);
    final completion = await (db.select(
      db.taskCompletions,
    )..where((row) => row.taskId.equals(ids.first))).getSingle();
    expect(
      completion.snapshotJson,
      '{"version":1,"kanban":{"previousStatusLabelId":'
      '"$kanbanStatusBacklogId"}}',
    );

    await controller.handleCommand({
      'type': watchTaskUncomplete,
      'id': ids.first,
    });
    expect(
      (await taskRepository.watchTask(ids.first).first)!.isCompleted,
      isFalse,
    );
    expect(await _kanbanStatusId(db, ids.first), kanbanStatusBacklogId);

    await controller.handleCommand({'type': watchFocusStartDefault});
    await controller.handleCommand({'type': watchFocusPause});
    var interval = await focusRepository.watchActiveInterval().first;
    expect(interval!.status, 'paused');

    await controller.handleCommand({'type': watchFocusResume});
    interval = await focusRepository.watchActiveInterval().first;
    expect(interval!.status, 'running');

    await controller.handleCommand({'type': watchFocusStop});
    expect(await focusRepository.watchActiveRun().first, isNull);
  });

  test('acks metadata and ignores duplicate watch command ids', () async {
    final command = {
      'type': watchTaskCreateQuickAdd,
      'id': 'watch-command-1',
      'createdAt': '2026-05-01T09:00:00Z',
      'occurredAt': '2026-05-01T09:00:00Z',
      'input': 'Buy milk',
    };

    final first = await controller.handleCommand(command);
    final second = await controller.handleCommand(command);
    final tasks = await db.select(db.tasks).get();
    final snapshot = first['snapshot']! as Map<String, Object?>;
    final sync = snapshot['sync']! as Map<String, Object?>;

    expect(first['appliedCommandId'], 'watch-command-1');
    expect(second['appliedCommandId'], 'watch-command-1');
    expect(sync['appliedCommandIds'], contains('watch-command-1'));
    expect(tasks.where((task) => task.content == 'Buy milk'), hasLength(1));
  });

  test('applies focus command occurredAt timestamps', () async {
    await controller.handleCommand({
      'type': watchFocusStartDefault,
      'id': 'focus-start-1',
      'createdAt': '2026-05-01T09:00:00Z',
      'occurredAt': '2026-05-01T09:00:00Z',
    });

    var run = await focusRepository.watchActiveRun().first;
    var interval = await focusRepository.watchActiveInterval().first;
    expect(run!.startedAt.toUtc(), DateTime.parse('2026-05-01T09:00:00Z'));
    expect(interval!.startedAt.toUtc(), DateTime.parse('2026-05-01T09:00:00Z'));

    await controller.handleCommand({
      'type': watchFocusPause,
      'id': 'focus-pause-1',
      'createdAt': '2026-05-01T09:05:00Z',
      'occurredAt': '2026-05-01T09:05:00Z',
    });

    interval = await focusRepository.watchActiveInterval().first;
    expect(interval!.pausedAt?.toUtc(), DateTime.parse('2026-05-01T09:05:00Z'));

    final restart = await controller.handleCommand({
      'type': watchFocusRestartInterval,
      'id': 'focus-restart-1',
      'createdAt': '2026-05-01T09:10:00Z',
      'occurredAt': '2026-05-01T09:10:00Z',
    });
    await controller.handleCommand({
      'type': watchFocusRestartInterval,
      'id': 'focus-restart-1',
      'createdAt': '2026-05-01T09:20:00Z',
      'occurredAt': '2026-05-01T09:20:00Z',
    });

    interval = await focusRepository.watchActiveInterval().first;
    expect(restart['appliedCommandId'], 'focus-restart-1');
    expect(interval!.status, 'running');
    expect(interval.startedAt.toUtc(), DateTime.parse('2026-05-01T09:10:00Z'));
    expect(interval.pausedAt, isNull);
    expect(interval.pausedTotalSeconds, 0);
  });

  test(
    'keeps mismatched focus commands pending for iPhone resolution',
    () async {
      final result = await controller.handleCommand({
        'type': watchFocusPause,
        'id': 'focus-pause-without-active-run',
        'createdAt': '2026-05-01T09:05:00Z',
        'occurredAt': '2026-05-01T09:05:00Z',
      });
      final snapshot = result['snapshot']! as Map<String, Object?>;
      final sync = snapshot['sync']! as Map<String, Object?>;

      expect(result['ok'], isFalse);
      expect(result['conflict'], isTrue);
      expect(result['keepPending'], isTrue);
      expect(
        sync['appliedCommandIds'],
        isNot(contains('focus-pause-without-active-run')),
      );

      final restart = await controller.handleCommand({
        'type': watchFocusRestartInterval,
        'id': 'focus-restart-without-active-run',
        'createdAt': '2026-05-01T09:05:00Z',
        'occurredAt': '2026-05-01T09:05:00Z',
      });
      expect(restart['ok'], isFalse);
      expect(restart['conflict'], isTrue);
      expect(restart['keepPending'], isTrue);
    },
  );
}

Future<String> _kanbanStatusId(AppDatabase db, String taskId) async {
  final assignments = await (db.select(
    db.taskLabels,
  )..where((row) => row.taskId.equals(taskId))).get();
  return assignments
      .singleWhere((row) => row.kind == labelKindKanbanStatus)
      .labelId;
}

class _FakeTaskDecomposer implements TaskDecomposer {
  const _FakeTaskDecomposer();

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) async {
    return const [
      DecomposedTaskDraft(
        quickAdd: 'Plan release today 10:00 30m',
        description: 'From watch dictation',
      ),
    ];
  }
}

class _NoopNotificationScheduler extends NotificationScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelFocusNotification() async {}

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => const {};

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelTaskStart(String taskId) async {}
}
