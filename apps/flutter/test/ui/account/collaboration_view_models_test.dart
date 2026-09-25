import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_conflict.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';
import 'package:pomodoist/domain/models/collaboration/public_project.dart';
import 'package:pomodoist/ui/collaboration/view_models/collaboration_join_view_model.dart';
import 'package:pomodoist/ui/collaboration/view_models/public_project_view_model.dart';
import 'package:pomodoist/ui/collaboration/view_models/share_project_view_model.dart';
import 'package:pomodoist/utils/result.dart';

final _scopesProvider = StreamProvider<List<SharedScope>>(
  (ref) => const Stream.empty(),
);

SharedScope _scope(String id) => SharedScope.fromJson({
  'id': id,
  'rootProjectId': 'project',
  'ownerId': 'owner-1',
  'role': 'administrator',
});

CollaborationInvitation _invitation(
  String id,
  String email, {
  String expiresAt = '2030-01-02T00:00:00Z',
  String? acceptedAt,
  String? revokedAt,
}) => CollaborationInvitation(
  id: id,
  role: CollaborationRole.member,
  email: email,
  expiresAt: DateTime.parse(expiresAt),
  acceptedAt: acceptedAt == null ? null : DateTime.parse(acceptedAt),
  revokedAt: revokedAt == null ? null : DateTime.parse(revokedAt),
);

class _Repository implements CollaborationRepository {
  var publicCalls = 0;
  var accepts = 0;
  var conflictReads = 0;
  Completer<Result<SharedScope>>? pendingAccept;
  Result<PublicProject> publicResponse = Success(PublicProject(const []));
  Result<CollaborationState> stateResponse = Success(
    CollaborationState(invitations: const [], notifications: const []),
  );
  final membersByScope = <String, Future<Result<CollaborationMembers>>>{};
  final memberCalls = <String>[];
  @override
  Stream<List<CollaborationConflict>> watchConflicts() {
    conflictReads++;
    return Stream.value(const []);
  }

  @override
  Future<Result<PublicProject>> publicRead(String token) async {
    publicCalls++;
    return publicResponse;
  }

  @override
  Future<Result<CollaborationState>> state() async => stateResponse;
  @override
  Future<Result<SharedScope>> acceptInvitation(String token) {
    accepts++;
    return pendingAccept?.future ?? Future.value(Success(_scope('scope')));
  }

  @override
  Future<Result<CollaborationMembers>> members(String scopeId) {
    memberCalls.add(scopeId);
    return membersByScope[scopeId] ??
        Future.value(
          Success(
            CollaborationMembers(members: const [], invitations: const []),
          ),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('sharing reads members without subscribing to sync conflicts', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWithValue(repository),
        collaborationActorIdProvider.overrideWith((_) async => 'owner-1'),
        sharedScopeForProjectProvider.overrideWith((_, _) => _scope('scope')),
      ],
    );
    addTearDown(container.dispose);
    final provider = shareProjectViewModelProvider('project');
    container.listen(provider, (_, _) {});
    await _settle();
    await _settle();
    expect(container.read(provider).scope!.ownerId, 'owner-1');
    expect(repository.memberCalls, ['scope']);
    expect(repository.conflictReads, 0);
  });

  test(
    'invalid public tokens never request data; revoked tokens do not retry',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          publicCollaborationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final invalid = publicProjectViewModelProvider('invalid');
      final keepInvalid = container.listen(invalid, (_, _) {});
      addTearDown(keepInvalid.close);
      await _settle();
      expect(container.read(invalid).failure, PublicProjectFailure.unavailable);
      expect(repository.publicCalls, 0);
      repository.publicResponse = Failure(
        const CollaborationException('42501'),
        StackTrace.current,
      );
      final valid = publicProjectViewModelProvider('a' * 64);
      final keepValid = container.listen(valid, (_, _) {});
      addTearDown(keepValid.close);
      await _settle();
      expect(repository.publicCalls, 1);
      expect(container.read(valid).failure, PublicProjectFailure.unavailable);
    },
  );

  test(
    'invitation acceptance is single flight and survives unavailable listing',
    () async {
      final repository = _Repository()
        ..stateResponse = Failure(
          StateError('listing unavailable'),
          StackTrace.current,
        )
        ..pendingAccept = Completer();
      final container = ProviderContainer(
        overrides: [
          collaborationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final provider = collaborationJoinViewModelProvider('b' * 64);
      final keepAlive = container.listen(provider, (_, _) {});
      addTearDown(keepAlive.close);
      await _settle();
      expect(container.read(provider).phase, JoinPhase.ready);
      final viewModel = container.read(provider.notifier);
      final accepting = viewModel.accept();
      await viewModel.accept();
      expect(repository.accepts, 1);
      repository.pendingAccept!.complete(
        Success(
          SharedScope.fromJson({
            'id': 'scope',
            'rootProjectId': 'project',
            'ownerId': 'owner',
            'role': 'member',
          }),
        ),
      );
      await accepting;
      expect(container.read(provider).phase, JoinPhase.accepted);
      expect(container.read(provider).projectId, 'project');
    },
  );

  test('public projection retains cycles and orphaned tasks exactly once', () {
    final project = PublicProject.fromResponse({
      'tasks': [
        {'id': 'a', 'content': 'A', 'parentId': 'b'},
        {'id': 'b', 'content': 'B', 'parentId': 'a'},
        {'id': 'c', 'content': 'C', 'parentId': 'missing'},
      ],
    });
    final tasks = project.sections.single.tasks;
    expect(tasks.map((node) => node.task.id).toSet(), {'a', 'b', 'c'});
    expect(tasks.length, 3);
    expect(() => project.sections.clear(), throwsUnsupportedError);
    expect(() => tasks.clear(), throwsUnsupportedError);
  });

  test(
    'pending invitations exclude expired and completed and deduplicate email',
    () {
      final current = _invitation('current', 'a@example.test');
      expect(
        pendingInvitations([
          _invitation(
            'stale',
            'a@example.test',
            expiresAt: '2030-01-01T12:00:00Z',
          ),
          current,
          _invitation(
            'accepted',
            'b@example.test',
            acceptedAt: '2029-01-01T00:00:00Z',
          ),
          _invitation(
            'expired',
            'c@example.test',
            expiresAt: '2030-01-01T00:00:00Z',
          ),
        ], DateTime.utc(2030)),
        [current],
      );
    },
  );

  test('a scope change drops members loaded for the previous scope', () async {
    final repository = _Repository();
    final pending = Completer<Result<CollaborationMembers>>();
    repository.membersByScope['scope-a'] = pending.future;
    repository.membersByScope['scope-b'] = Future.value(
      Success(
        CollaborationMembers(
          members: const [],
          invitations: [_invitation('new', 'new@example.test')],
        ),
      ),
    );
    final scopes = StreamController<List<SharedScope>>.broadcast();
    addTearDown(scopes.close);
    final container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWithValue(repository),
        collaborationActorIdProvider.overrideWith((ref) async => 'owner-1'),
        _scopesProvider.overrideWith((ref) => scopes.stream),
        sharedScopeForProjectProvider.overrideWith(
          (ref, projectId) => ref.watch(_scopesProvider).value?.first,
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = shareProjectViewModelProvider('project');
    final keepAlive = container.listen(provider, (_, _) {});
    addTearDown(keepAlive.close);

    scopes.add([_scope('scope-a')]);
    await _settle();
    await _settle();
    expect(repository.memberCalls, ['scope-a']);

    scopes.add([_scope('scope-b')]);
    await _settle();
    await _settle();
    expect(repository.memberCalls, ['scope-a', 'scope-b']);
    expect(container.read(provider).invitations.map((row) => row.id), ['new']);

    pending.complete(
      Success(
        CollaborationMembers(
          members: const [],
          invitations: [_invitation('old', 'old@example.test')],
        ),
      ),
    );
    await _settle();
    expect(container.read(provider).invitations.map((row) => row.id), ['new']);
  });

  test(
    'sign-out during acceptance never publishes the accepted scope',
    () async {
      final repository = _Repository()..pendingAccept = Completer();
      final session = StreamController<bool>.broadcast();
      addTearDown(session.close);
      final signedInProvider = StreamProvider<bool>((ref) => session.stream);
      final container = ProviderContainer(
        overrides: [
          signedInProvider.overrideWith((ref) => session.stream),
          collaborationRepositoryProvider.overrideWith(
            (ref) =>
                ref.watch(signedInProvider).value == true ? repository : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = collaborationJoinViewModelProvider('c' * 64);
      final keepAlive = container.listen(provider, (_, _) {});
      addTearDown(keepAlive.close);
      session.add(true);
      await _settle();
      await _settle();
      expect(container.read(provider).signedIn, isTrue);

      final accepting = container.read(provider.notifier).accept();
      await _settle();
      expect(repository.accepts, 1);

      session.add(false);
      await _settle();
      await _settle();
      expect(container.read(provider).signedIn, isFalse);

      repository.pendingAccept!.complete(Success(_scope('scope')));
      await accepting;
      expect(container.read(provider).phase, isNot(JoinPhase.accepted));
      expect(container.read(provider).projectId, isNull);
    },
  );
}
