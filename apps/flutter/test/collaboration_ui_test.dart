import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/sync/sync_queue_repository.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_api.dart';
import 'package:pomodoist/features/collaboration/data/collaboration_repository.dart';
import 'package:pomodoist/features/collaboration/presentation/collaboration_inbox_dialog.dart';
import 'package:pomodoist/features/collaboration/presentation/collaboration_providers.dart';
import 'package:pomodoist/features/collaboration/presentation/share_project_dialog.dart';
import 'package:pomodoist/features/collaboration/presentation/task_collaboration_section.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

import 'support/test_app.dart';

const _actor = localUserId;
const _memberId = 'member-2';
const _scopeId = 'scope-1';
const _projectId = 'project-1';
const _taskId = 'task-1';
final _publicToken = List.filled(64, 'a').join();

class _Harness {
  _Harness(this.db, this.calls);

  final AppDatabase db;
  final List<Map<String, dynamic>> calls;

  Iterable<Map<String, dynamic>> callsFor(String action) =>
      calls.where((call) => call['action'] == action);
}

Map<String, dynamic> _scopeJson({
  String role = 'administrator',
  String ownerId = _actor,
  String? publicToken,
}) => {
  'id': _scopeId,
  'rootProjectId': _projectId,
  'ownerId': ownerId,
  'role': role,
  'revision': 4,
  'historyUnlimited': true,
  'publicToken': ?publicToken,
  'members': [
    {'userId': ownerId, 'role': 'administrator', 'displayName': 'Owner Name'},
    {'userId': _memberId, 'role': 'member', 'displayName': 'Alice'},
  ],
};

ProjectItem _project() => ProjectItem(
  id: _projectId,
  userId: _actor,
  name: 'Shared project',
  orderKey: 'a',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

TaskItem _task({List<String> assignees = const []}) => TaskItem(
  scopeId: _scopeId,
  assigneeIds: assignees,
  id: _taskId,
  userId: _actor,
  content: 'Shared task',
  projectId: _projectId,
  priority: 4,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: 'a',
  isDeleted: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<void> _seedScope(
  AppDatabase db, {
  String role = 'administrator',
  String ownerId = _actor,
  String? publicToken,
}) => db
    .into(db.sharedScopes)
    .insertOnConflictUpdate(
      SharedScopesCompanion.insert(
        id: _scopeId,
        dataJson: jsonEncode(
          _scopeJson(role: role, ownerId: ownerId, publicToken: publicToken),
        ),
      ),
    );

Future<void> _seedSharedTask(AppDatabase db) => db
    .into(db.tasks)
    .insertOnConflictUpdate(
      TasksCompanion.insert(
        id: _taskId,
        userId: _actor,
        content: 'Shared task',
        projectId: _projectId,
        scopeId: const Value(_scopeId),
        orderKey: 'a',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

Future<void> _seedComment(
  AppDatabase db, {
  String id = 'comment-1',
  String body = 'Existing comment',
  String createdBy = _actor,
}) => db
    .into(db.sharedEntities)
    .insertOnConflictUpdate(
      SharedEntitiesCompanion.insert(
        scopeId: _scopeId,
        entityType: 'comment',
        entityId: id,
        dataJson: jsonEncode({
          'id': id,
          'scopeId': _scopeId,
          'taskId': _taskId,
          'body': body,
          'createdBy': createdBy,
          'createdAt': '2026-09-14T10:00:00Z',
        }),
      ),
    );

Future<_Harness> _pumpCollaborationApp(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function(
    String action,
    Map<String, dynamic> args,
  )
  handler,
  Future<void> Function(AppDatabase db)? onSynchronize,
  required Widget Function(BuildContext context) build,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final calls = <Map<String, dynamic>>[];
  final repository = CollaborationRepository(
    db: db,
    api: CollaborationApi((body) async {
      final action = body['action'] as String? ?? '';
      final args = Map<String, dynamic>.from(body)..remove('action');
      calls.add({'action': action, ...args});
      return handler(action, args);
    }),
    queue: DriftSyncQueueRepository(db),
    synchronize: () async => onSynchronize?.call(db),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        collaborationRepositoryProvider.overrideWithValue(repository),
        collaborationActorIdProvider.overrideWith((ref) async => _actor),
      ],
      child: MaterialApp(
        builder: testAppBuilder,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: build)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(db, calls);
}

Future<void> _drainSnackBarsAndDispose(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  setUpAll(loadTestAppResources);

  group('share project dialog', () {
    testWidgets('shares a personal project and opens member management', (
      tester,
    ) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'share' => {'scope': _scopeJson()},
          'members' => {
            'members': _scopeJson()['members'],
            'invitations': const [],
          },
          _ => {'ok': true},
        },
        onSynchronize: (db) => _seedScope(db),
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collaboration-share-start')), findsOne);
      expect(find.text('Alice'), findsNothing);

      await tester.tap(find.byKey(const Key('collaboration-share-start')));
      await tester.pumpAndSettle();

      expect(harness.callsFor('share'), hasLength(1));
      expect(harness.callsFor('share').single['rootProjectId'], _projectId);
      expect(find.byKey(const Key('collaboration-invite-email')), findsOne);
      expect(find.text('Alice'), findsOne);
      expect(find.text('Owner Name'), findsOne);
      expect(find.byKey(const Key('collaboration-share-confirmed')), findsOne);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('shows progress while the share request is in flight', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gate = Completer<Map<String, dynamic>>();
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'share' => gate.future,
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('collaboration-share-progress')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('collaboration-share-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.callsFor('share'), hasLength(1));
      expect(find.byKey(const Key('collaboration-share-progress')), findsOne);
      expect(find.text(l10n.collaborationShareInProgress), findsOne);
      expect(find.byType(LinearProgressIndicator), findsOne);

      gate.complete({'scope': _scopeJson()});
      await tester.pumpAndSettle();

      expect(harness.callsFor('share'), hasLength(1));
      expect(
        find.byKey(const Key('collaboration-share-progress')),
        findsNothing,
      );
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('reports unavailability when the function is not deployed', (
      tester,
    ) async {
      await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'share' => {
            'error': 'Requested function was not found',
            'code': 'function_not_found',
          },
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collaboration-share-start')));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.collaborationUnavailable), findsOne);
      expect(find.text(l10n.collaborationSignedOut), findsNothing);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('asks to sign in when the session is rejected', (tester) async {
      await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'share' => {
            'error': 'Authentication required',
            'code': 'unauthenticated',
          },
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collaboration-share-start')));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.collaborationSignedOut), findsOne);
      expect(find.text(l10n.collaborationUnavailable), findsNothing);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('invites by email and lists pending invitations', (
      tester,
    ) async {
      late _Harness harness;
      harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'members' => {
            'members': _scopeJson()['members'],
            'invitations': [
              if (harness.callsFor('invite').isNotEmpty)
                {
                  'id': 'inv-1',
                  'email': 'dana@example.test',
                  'role': 'member',
                  'expiresAt': '2026-09-20T10:00:00Z',
                },
            ],
          },
          'invite' => {
            'id': 'inv-1',
            'token': 'token-1',
            'email': 'dana@example.test',
            'role': 'member',
            'url': 'https://web.test/shared/join/token-1',
            'emailDelivery': 'sent',
          },
          _ => {'ok': true},
        },
        onSynchronize: (db) async {},
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );
      await harness.db
          .into(harness.db.sharedScopes)
          .insertOnConflictUpdate(
            SharedScopesCompanion.insert(
              id: _scopeId,
              dataJson: jsonEncode(_scopeJson()),
            ),
          );

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('collaboration-invite-email')),
        'dana@example.test',
      );
      await tester.tap(find.byKey(const Key('collaboration-invite-submit')));
      await tester.pumpAndSettle();

      final invite = harness.callsFor('invite').single;
      expect(invite['scopeId'], _scopeId);
      expect(invite['email'], 'dana@example.test');
      expect(invite['role'], 'member');
      expect(find.byKey(const Key('collaboration-revoke-inv-1')), findsOne);
      expect(
        find.widgetWithText(ListTile, 'dana@example.test'),
        findsOneWidget,
      );
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('removes a member after confirmation', (tester) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'members' => {
            'members': _scopeJson()['members'],
            'invitations': const [],
          },
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );
      await _seedScope(harness.db);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collaboration-member-menu-$_memberId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collaboration-remove-$_memberId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collaboration-confirm')));
      await tester.pumpAndSettle();

      final remove = harness.callsFor('remove').single;
      expect(remove['scopeId'], _scopeId);
      expect(remove['userId'], _memberId);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('toggles the public link and copies the capability url', (
      tester,
    ) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'members' => {
            'members': _scopeJson()['members'],
            'invitations': const [],
          },
          'publicLink' => {
            'token': _publicToken,
            'url': 'https://web.test/shared/public/$_publicToken',
          },
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );
      await _seedScope(harness.db);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collaboration-public-link-switch')),
      );
      await tester.pumpAndSettle();

      expect(harness.callsFor('publicLink').single['enabled'], isTrue);
      expect(find.text('Link copied'), findsOne);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('member leaves the shared project', (tester) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'members' => {'members': const [], 'invitations': const []},
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );
      await _seedScope(harness.db, role: 'member', ownerId: _memberId);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collaboration-delete')), findsNothing);
      await tester.tap(find.byKey(const Key('collaboration-leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collaboration-confirm')));
      await tester.pumpAndSettle();

      expect(harness.callsFor('leave').single['scopeId'], _scopeId);
      expect(find.byKey(const Key('collaboration-leave')), findsNothing);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('owner deletes the shared project', (tester) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'members' => {'members': const [], 'invitations': const []},
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-share'),
            onPressed: () => showShareProjectDialog(context, _project()),
            child: const Text('open'),
          ),
        ),
      );
      await _seedScope(harness.db);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collaboration-leave')), findsNothing);
      await tester.tap(find.byKey(const Key('collaboration-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collaboration-confirm')));
      await tester.pumpAndSettle();

      expect(harness.callsFor('delete').single['scopeId'], _scopeId);
      await _drainSnackBarsAndDispose(tester);
    });
  });

  group('collaboration inbox', () {
    testWidgets('accepts a pending invitation', (tester) async {
      var accepted = false;
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => switch (action) {
          'state' => {
            'invitations': accepted
                ? const []
                : [
                    {
                      'id': 'inv-1',
                      'scopeId': _scopeId,
                      'role': 'member',
                      'token': 'token-1',
                      'expiresAt': '2026-09-20T10:00:00Z',
                    },
                  ],
            'notifications': accepted
                ? const []
                : [
                    {
                      'id': 'note-1',
                      'kind': 'invitation',
                      'readAt': null,
                      'createdAt': '2026-09-14T10:00:00Z',
                    },
                  ],
          },
          'accept' => {'scope': _scopeJson()},
          _ => {'ok': true},
        },
        build: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-inbox'),
            onPressed: () => showCollaborationInboxDialog(context),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-inbox')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collaboration-invitation-inv-1')), findsOne);
      expect(find.text('Invitation to a shared project'), findsOne);

      accepted = true;
      await tester.tap(
        find.byKey(const Key('collaboration-inbox-accept-inv-1')),
      );
      await tester.pumpAndSettle();

      expect(harness.callsFor('accept').single['token'], 'token-1');
      expect(
        find.byKey(const Key('collaboration-invitation-inv-1')),
        findsNothing,
      );
      await _drainSnackBarsAndDispose(tester);
    });
  });

  group('task collaboration section', () {
    testWidgets('shows assignees and posts a comment', (tester) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => {'ok': true},
        build: (context) => SingleChildScrollView(
          child: TaskCollaborationSection(task: _task(assignees: [_memberId])),
        ),
      );
      await _seedScope(harness.db);
      await _seedSharedTask(harness.db);
      await _seedComment(harness.db);
      await tester.pumpAndSettle();

      expect(find.text('Assignees'), findsOne);
      expect(find.text('Alice'), findsOne);
      expect(find.text('Existing comment'), findsOne);
      expect(find.text('Owner Name'), findsOne);

      await tester.enterText(
        find.byKey(const Key('task-comment-input')),
        'New comment',
      );
      await tester.tap(find.byKey(const Key('task-comment-send')));
      await tester.pumpAndSettle();

      final comments = await (harness.db.select(
        harness.db.sharedEntities,
      )..where((row) => row.entityType.equals('comment'))).get();
      expect(comments.where((row) => !row.isDeleted), hasLength(2));
      expect(
        comments.any((row) => row.dataJson.contains('New comment')),
        isTrue,
      );
      final commands = await harness.db.select(harness.db.syncCommands).get();
      expect(commands.any((row) => row.type == 'comment.create'), isTrue);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('deletes an authored comment', (tester) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => {'ok': true},
        build: (context) => SingleChildScrollView(
          child: TaskCollaborationSection(task: _task()),
        ),
      );
      await _seedScope(harness.db);
      await _seedSharedTask(harness.db);
      await _seedComment(harness.db);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('task-comment-delete-comment-1')));
      await tester.pumpAndSettle();

      final comment = await (harness.db.select(
        harness.db.sharedEntities,
      )..where((row) => row.entityId.equals('comment-1'))).getSingle();
      expect(comment.isDeleted, isTrue);
      await _drainSnackBarsAndDispose(tester);
    });

    testWidgets('observers cannot edit assignees or comments', (tester) async {
      final harness = await _pumpCollaborationApp(
        tester,
        handler: (action, args) async => {'ok': true},
        build: (context) => SingleChildScrollView(
          child: TaskCollaborationSection(task: _task()),
        ),
      );
      await _seedScope(harness.db, role: 'observer');
      await _seedSharedTask(harness.db);
      await _seedComment(harness.db);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-assignees-edit')), findsNothing);
      expect(find.byKey(const Key('task-comment-input')), findsNothing);
      expect(
        find.byKey(const Key('task-comment-delete-comment-1')),
        findsNothing,
      );
      await _drainSnackBarsAndDispose(tester);
    });
  });
}
