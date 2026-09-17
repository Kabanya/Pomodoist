import 'dart:async';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/account_sync_engine.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_api.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_repository.dart';
import 'package:pomodoist/features/collaboration/presentation/collaboration_providers.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/task_detail_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

import 'support/test_app.dart';

const _actor = localUserId;
const _memberId = 'member-2';
const _scopeId = 'scope-1';
const _projectId = 'project-1';
const _taskId = 'task-1';

void main() {
  setUpAll(loadTestAppResources);

  test(
    'a member session pulled for a shared task stops in the shared cache',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final startedAt = DateTime.utc(2026, 9, 15, 9);
      final api = CollaborationApi((request) async {
        switch (request['action']) {
          case 'state':
            return {
              'scopes': [
                {
                  'id': _scopeId,
                  'rootProjectId': _projectId,
                  'ownerId': _actor,
                  'role': 'member',
                },
              ],
            };
          case 'pull':
            return {
              'changes': [
                {
                  'entityType': 'project',
                  'entityId': _projectId,
                  'serverRevision': 1,
                  'updatedAt': '2026-09-15T09:00:00Z',
                  'data': {'name': 'Shared project'},
                },
                {
                  'entityType': 'task',
                  'entityId': _taskId,
                  'serverRevision': 2,
                  'updatedAt': '2026-09-15T09:00:00Z',
                  'data': {
                    'id': _taskId,
                    'projectId': _projectId,
                    'content': 'Shared task',
                    'createdBy': _actor,
                  },
                },
                {
                  'entityType': 'focus_interval',
                  'entityId': 'peer-interval-1',
                  'serverRevision': 3,
                  'updatedAt': '2026-09-15T09:25:00Z',
                  'data': _sharedInterval(
                    id: 'peer-interval-1',
                    author: _memberId,
                    startedAt: startedAt,
                    durationSeconds: 1500,
                  ),
                },
              ],
              'nextCursor': 3,
              'hasMore': false,
            };
          default:
            throw StateError('Unexpected action ${request['action']}');
        }
      });
      final engine = AccountSyncEngine(
        db: db,
        uuid: const Uuid(),
        account: _Account(),
        collaboration: api,
      );

      await engine.syncShared();

      final cached = await (db.select(
        db.sharedEntities,
      )..where((row) => row.entityType.equals('focus_interval'))).getSingle();
      expect(cached.entityId, 'peer-interval-1');
      expect(
        jsonDecode(cached.dataJson)['createdBy'],
        _memberId,
        reason: "a member's session must stay attributed to its author",
      );
      expect(
        await db.select(db.focusIntervals).get(),
        isEmpty,
        reason: "a member's session must not become this device's own history",
      );
    },
  );

  testWidgets("focus history lists another member's completed session", (
    tester,
  ) async {
    final harness = await _pumpSharedTask(
      tester,
      sharedIntervals: [
        _sharedInterval(
          id: 'peer-interval-1',
          author: _memberId,
          startedAt: DateTime.utc(2026, 9, 15, 9),
          durationSeconds: 1500,
        ),
      ],
    );

    await _openFocusHistory(tester);

    expect(
      find.byKey(const Key('focus-history-shared-peer-interval-1')),
      findsOne,
    );
    expect(find.textContaining('Alice'), findsOne);
    expect(harness.localIntervals, isEmpty);
    await _drainAndDispose(tester);
  });

  testWidgets('an interval that is both local and shared is listed once', (
    tester,
  ) async {
    await _pumpSharedTask(
      tester,
      localIntervals: [
        _localInterval(
          id: 'own-interval',
          startedAt: DateTime.utc(2026, 9, 15, 8),
        ),
      ],
      sharedIntervals: [
        _sharedInterval(
          id: 'own-interval',
          author: _actor,
          startedAt: DateTime.utc(2026, 9, 15, 8),
          durationSeconds: 1500,
        ),
      ],
    );

    await _openFocusHistory(tester);

    expect(
      find.byKey(const Key('focus-history-interval-own-interval')),
      findsOne,
    );
    expect(
      find.byKey(const Key('focus-history-shared-own-interval')),
      findsNothing,
    );
    await _drainAndDispose(tester);
  });

  testWidgets('an empty focus history keeps its empty state', (tester) async {
    await _pumpSharedTask(tester, sharedIntervals: const []);

    await _openFocusHistory(tester);

    expect(find.text('No focus intervals yet.'), findsOne);
    await _drainAndDispose(tester);
  });
}

// Closes the drift query streams while the test's fake clock can still run the
// timers they schedule on cancellation.
Future<void> _drainAndDispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _openFocusHistory(WidgetTester tester) async {
  final title = find.text('Focus history');
  await tester.dragUntilVisible(
    title,
    find.byType(SingleChildScrollView).first,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
  await tester.tap(title);
  await tester.pumpAndSettle();
}

Future<_Harness> _pumpSharedTask(
  WidgetTester tester, {
  List<FocusIntervalItem> localIntervals = const [],
  List<Map<String, dynamic>> sharedIntervals = const [],
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await db
      .into(db.sharedScopes)
      .insertOnConflictUpdate(
        SharedScopesCompanion.insert(
          id: _scopeId,
          dataJson: jsonEncode({
            'id': _scopeId,
            'rootProjectId': _projectId,
            'ownerId': _actor,
            'role': 'administrator',
            'revision': 4,
            'members': [
              {
                'userId': _actor,
                'role': 'administrator',
                'displayName': 'Owner Name',
              },
              {'userId': _memberId, 'role': 'member', 'displayName': 'Alice'},
            ],
          }),
        ),
      );
  for (final interval in sharedIntervals) {
    await db
        .into(db.sharedEntities)
        .insertOnConflictUpdate(
          SharedEntitiesCompanion.insert(
            scopeId: _scopeId,
            entityType: 'focus_interval',
            entityId: interval['id'] as String,
            dataJson: jsonEncode(interval),
            serverRevision: const Value(7),
          ),
        );
  }
  final now = DateTime.utc(2026, 9, 15, 12);
  final task = TaskItem(
    scopeId: _scopeId,
    id: _taskId,
    userId: _actor,
    content: 'Shared task',
    projectId: _projectId,
    priority: 4,
    status: 'open',
    completedFocusIntervals: 1,
    totalFocusSeconds: 1500,
    orderKey: 'a',
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );
  final repository = CollaborationRepository(
    db: db,
    api: CollaborationApi((request) async => <String, dynamic>{}),
    queue: DriftSyncQueueRepository(db),
    synchronize: () async {},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        collaborationRepositoryProvider.overrideWithValue(repository),
        collaborationActorIdProvider.overrideWith((ref) async => _actor),
        taskProvider(_taskId).overrideWith((ref) => Stream.value(task)),
        focusRepositoryProvider.overrideWithValue(
          _FocusRepository(localIntervals),
        ),
        taskRepositoryProvider.overrideWithValue(_TaskRepository()),
        focusPresetsProvider.overrideWith(
          (ref) => Stream.value(const <FocusPresetItem>[]),
        ),
        activeFocusRunProvider.overrideWith((ref) => Stream.value(null)),
        clockProvider.overrideWithValue(FixedClock(now)),
        taskTimeTickerProvider.overrideWith((ref) => Stream.value(now)),
        googleCalendarLinkProvider(
          _taskId,
        ).overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp.router(
        builder: testAppBuilder,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  const Scaffold(body: TaskDetailScreen(taskId: _taskId)),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(db, localIntervals);
}

class _Harness {
  const _Harness(this.db, this.localIntervals);

  final AppDatabase db;
  final List<FocusIntervalItem> localIntervals;
}

Map<String, dynamic> _sharedInterval({
  required String id,
  required String author,
  required DateTime startedAt,
  required int durationSeconds,
}) => {
  'id': id,
  'scopeId': _scopeId,
  'taskId': _taskId,
  'projectId': _projectId,
  'runId': '$id-run',
  'type': 'work',
  'status': 'completed',
  'plannedSeconds': durationSeconds,
  'durationSeconds': durationSeconds,
  'startedAt': startedAt.toIso8601String(),
  'completedAt': startedAt
      .add(Duration(seconds: durationSeconds))
      .toIso8601String(),
  'pausedTotalSeconds': 0,
  'sequenceNumber': 1,
  'createdAt': startedAt.toIso8601String(),
  'updatedAt': startedAt
      .add(Duration(seconds: durationSeconds))
      .toIso8601String(),
  'isDeleted': false,
  'userId': author,
  'createdBy': author,
};

FocusIntervalItem _localInterval({
  required String id,
  required DateTime startedAt,
}) => FocusIntervalItem(
  id: id,
  runId: '$id-run',
  taskId: _taskId,
  projectId: _projectId,
  type: 'work',
  status: 'completed',
  plannedSeconds: 1500,
  startedAt: startedAt,
  pausedTotalSeconds: 0,
  completedAt: startedAt.add(const Duration(minutes: 25)),
  sequenceNumber: 1,
  createdAt: startedAt,
  updatedAt: startedAt.add(const Duration(minutes: 25)),
);

class _FocusRepository implements FocusRepository {
  _FocusRepository(this._intervals);

  final List<FocusIntervalItem> _intervals;

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId) =>
      Stream.value(_intervals);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TaskRepository implements TaskRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements AccountClient {
  @override
  String? get currentUserId => _actor;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
