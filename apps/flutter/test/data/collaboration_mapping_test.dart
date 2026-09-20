import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/collaboration/drift_collaboration_repository.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  group('domain transport models', () {
    test('a malformed scope role is rejected, a missing one is observer', () {
      expect(
        () => SharedScope.fromJson({
          'id': 'scope',
          'rootProjectId': 'project',
          'ownerId': 'owner',
          'role': 'owner',
        }),
        throwsA(
          isA<CollaborationException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
      final observer = SharedScope.fromJson({
        'id': 'scope',
        'rootProjectId': 'project',
        'ownerId': 'owner',
      });
      expect(observer.role, CollaborationRole.observer);
      expect(observer.canEdit, isFalse);
      expect(observer.canManage, isFalse);
    });

    test(
      'unknown member roles, duplicate members and missing ids are rejected',
      () {
        expect(
          () => CollaborationMembers.fromJson({
            'members': [
              {'userId': 'u1', 'role': 'editor'},
            ],
            'invitations': const [],
          }),
          throwsA(
            isA<CollaborationException>().having(
              (error) => error.code,
              'code',
              'invalid_response',
            ),
          ),
        );
        expect(
          () => CollaborationMembers.fromJson({
            'members': [
              {'userId': 'u1', 'role': 'member'},
              {'userId': 'u1', 'role': 'administrator'},
            ],
            'invitations': const [],
          }),
          throwsA(isA<CollaborationException>()),
        );
        expect(
          () => CollaborationMembers.fromJson({
            'members': [
              {'role': 'member'},
            ],
            'invitations': const [],
          }),
          throwsA(isA<CollaborationException>()),
        );
      },
    );

    test('expired, revoked and accepted invitations are not pending', () {
      final pending = CollaborationInvitation.fromJson({
        'id': 'pending',
        'email': 'a@example.test',
        'role': 'member',
        'expiresAt': '2026-09-20T10:00:00Z',
        'revokedAt': null,
        'acceptedAt': null,
      });
      expect(pending.isPending(DateTime.utc(2026, 9, 19)), isTrue);
      expect(pending.isPending(DateTime.utc(2026, 9, 21)), isFalse);

      for (final overrides in [
        {'expiresAt': '2020-01-01T00:00:00Z'},
        {'revokedAt': '2026-09-19T00:00:00Z'},
        {'acceptedAt': '2026-09-19T00:00:00Z'},
      ]) {
        final invitation = CollaborationInvitation.fromJson({
          'id': 'invitation',
          'email': 'a@example.test',
          'role': 'member',
          'expiresAt': '2999-01-01T00:00:00Z',
          'revokedAt': null,
          'acceptedAt': null,
          ...overrides,
        });
        expect(invitation.isPending(DateTime.utc(2026, 9, 19)), isFalse);
      }
    });

    test('comments and focus contributions expose typed fields', () {
      final comment = CollaborationComment.fromJson({
        'id': 'comment-1',
        'scopeId': 'scope',
        'taskId': 'task',
        'body': 'Hello',
        'createdBy': 'member-1',
        'createdAt': '2026-09-14T10:00:00Z',
      });
      expect(comment.body, 'Hello');
      expect(comment.createdBy, 'member-1');
      expect(comment.createdAt, DateTime.utc(2026, 9, 14, 10));

      final contribution = CollaborationFocusContribution.fromJson({
        'id': 'focus-1',
        'type': 'work',
        'status': 'completed',
        'createdBy': 'member-1',
        'durationSeconds': 1500,
        'startedAt': '2026-09-14T09:00:00Z',
      });
      expect(contribution.startedAt, DateTime.utc(2026, 9, 14, 9));
      expect(contribution.authorId, 'member-1');
      expect(contribution.seconds, 1500);

      final millis = CollaborationFocusContribution.fromJson({
        'id': 'focus-2',
        'startedAt': 1757840400000,
        'plannedSeconds': 60,
      });
      expect(millis.startedAt, isNotNull);
      expect(millis.seconds, 60);
    });
  });

  group('repository transport mapping', () {
    late AppDatabase db;
    late DriftCollaborationRepository repository;
    late Map<String, dynamic> Function(String action) respond;
    var synchronizations = 0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      synchronizations = 0;
      respond = (_) => const {};
      repository = DriftCollaborationRepository(
        db: db,
        api: CollaborationApi((body) async {
          return respond(body['action'] as String? ?? '');
        }),
        queue: DriftOutboxService(db),
        synchronize: () async => synchronizations++,
      );
    });
    tearDown(() => db.close());

    test('maps public, state, members, invite and accept payloads', () async {
      respond = (action) => switch (action) {
        'publicRead' => {
          'projects': [
            {'id': 'project-1', 'name': 'Launch plan'},
          ],
          'tasks': const [],
          'comments': const [],
        },
        'state' => {
          'invitations': [
            {
              'id': 'inv-1',
              'scopeId': 'scope',
              'role': 'member',
              'token': 'token-1',
              'expiresAt': '2026-09-20T10:00:00Z',
            },
          ],
          'notifications': [
            {
              'id': 'note-1',
              'kind': 'invitation',
              'readAt': null,
              'createdAt': '2026-09-14T10:00:00Z',
            },
          ],
          'personalRevision': 12,
        },
        'members' => {
          'members': [
            {'userId': 'u1', 'role': 'administrator', 'displayName': 'Ada'},
            {'userId': 'u2', 'role': 'observer'},
          ],
          'invitations': [
            {
              'id': 'inv-1',
              'email': 'a@example.test',
              'role': 'member',
              'expiresAt': '2999-01-01T00:00:00Z',
              'revokedAt': null,
              'acceptedAt': null,
            },
          ],
        },
        'invite' => {
          'id': 'inv-2',
          'email': 'b@example.test',
          'role': 'observer',
          'emailDelivery': 'failed',
        },
        'accept' => {
          'scope': {
            'id': 'scope',
            'rootProjectId': 'project-1',
            'ownerId': 'u1',
            'role': 'member',
          },
        },
        _ => const {},
      };

      final project = (await repository.publicRead('a' * 64)).getOrThrow();
      expect(project.sections.single.name, 'Launch plan');

      final state = (await repository.state()).getOrThrow();
      expect(state.personalRevision, 12);
      expect(state.invitations.single.role, CollaborationRole.member);
      expect(state.notifications.single.isUnread, isTrue);

      final members = (await repository.members('scope')).getOrThrow();
      expect(members.members.map((member) => member.userId), ['u1', 'u2']);
      expect(members.members.first.role, CollaborationRole.administrator);
      expect(members.members.last.role.canEdit, isFalse);
      expect(members.invitations.single.isPending(DateTime.utc(2026)), isTrue);

      final outcome = (await repository.invite(
        'scope',
        email: 'b@example.test',
        role: CollaborationRole.observer,
      )).getOrThrow();
      expect(outcome.id, 'inv-2');
      expect(outcome.role, CollaborationRole.observer);
      expect(outcome.emailDelivery, CollaborationEmailDelivery.failed);

      final scope = (await repository.acceptInvitation('token')).getOrThrow();
      expect(scope.rootProjectId, 'project-1');
      expect(scope.role, CollaborationRole.member);
      expect(synchronizations, 2);
    });

    test('malformed permission payloads return a failure', () async {
      respond = (action) => switch (action) {
        'members' => {
          'members': [
            {'userId': 'u1', 'role': 'superuser'},
          ],
          'invitations': const [],
        },
        'state' => {
          'invitations': [
            {'id': 'inv-1', 'role': 'superuser', 'token': 'token-1'},
          ],
        },
        _ => const {},
      };

      final members = await repository.members('scope');
      expect(members, isA<Failure<CollaborationMembers>>());
      expect(
        (members as Failure).error,
        isA<CollaborationException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      );

      final state = await repository.state();
      expect(state, isA<Failure<CollaborationState>>());

      final accept = await repository.acceptInvitation('token');
      expect(accept, isA<Failure<SharedScope>>());
    });

    test(
      'resolving a conflict uses the remote revision for a local retry',
      () async {
        await db
            .into(db.sharedScopes)
            .insert(
              SharedScopesCompanion.insert(
                id: 'scope',
                dataJson: jsonEncode({
                  'id': 'scope',
                  'rootProjectId': 'project',
                  'ownerId': 'owner',
                  'role': 'administrator',
                }),
                cursor: const Value(9),
              ),
            );
        final now = DateTime.utc(2026, 9, 14);
        await db
            .into(db.syncCommands)
            .insert(
              SyncCommandsCompanion.insert(
                id: 'command-1',
                uuid: 'uuid-1',
                type: 'task.update',
                payloadJson: '{}',
                createdAt: now,
                updatedAt: now,
                scopeId: const Value('scope'),
                clientId: const Value('task-1'),
                baseRevision: const Value(3),
                status: const Value('conflict'),
                lastError: Value(
                  jsonEncode({
                    'serverRevision': 7,
                    'entityType': 'task',
                    'entityId': 'task-1',
                  }),
                ),
              ),
            );
        final command = CollaborationConflict(
          id: 'command-1',
          scopeId: 'scope',
          type: 'task.update',
          clientId: 'task-1',
          lastError: jsonEncode({
            'serverRevision': 7,
            'entityType': 'task',
            'entityId': 'task-1',
          }),
          baseRevision: 3,
        );
        expect(command.serverRevision, 7);
        expect(command.entityType, 'task');
        expect(command.entityId, 'task-1');

        (await repository.resolveConflict(
          command,
          keepLocal: true,
        )).getOrThrow();

        final row = await db.select(db.syncCommands).getSingle();
        expect(row.status, 'pending');
        expect(row.baseRevision, 7);
        expect(row.lastError, isNull);
        expect(row.uuid, isNot('uuid-1'));
        final scope = await db.select(db.sharedScopes).getSingle();
        expect(scope.cursor, 0);
        expect(synchronizations, 1);
      },
    );

    test('using the server conflicts deletes the local command', () async {
      final now = DateTime.utc(2026, 9, 14);
      await db
          .into(db.syncCommands)
          .insert(
            SyncCommandsCompanion.insert(
              id: 'command-2',
              uuid: 'uuid-2',
              type: 'task.update',
              payloadJson: '{}',
              createdAt: now,
              updatedAt: now,
              scopeId: const Value('scope'),
              clientId: const Value('task-2'),
              baseRevision: const Value(4),
              status: const Value('conflict'),
            ),
          );
      final command = CollaborationConflict(
        id: 'command-2',
        scopeId: 'scope',
        type: 'task.update',
        clientId: 'task-2',
        lastError: null,
        baseRevision: 4,
      );

      (await repository.resolveConflict(
        command,
        keepLocal: false,
      )).getOrThrow();

      expect(await db.select(db.syncCommands).get(), isEmpty);
      expect(command.label, 'task.update · task-2');
      expect(synchronizations, 1);
    });
  });
}
