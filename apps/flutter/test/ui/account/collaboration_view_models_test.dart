import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/public_project.dart';
import 'package:pomodoist/ui/collaboration/view_models/collaboration_join_view_model.dart';
import 'package:pomodoist/ui/collaboration/view_models/public_project_view_model.dart';
import 'package:pomodoist/ui/collaboration/view_models/share_project_view_model.dart';
import 'package:pomodoist/utils/result.dart';

class _Repository implements CollaborationRepository {
  var publicCalls = 0;
  var accepts = 0;
  Completer<Result<Map<String, dynamic>>>? pendingAccept;
  Result<Map<String, dynamic>> response = const Success({});
  @override
  Future<Result<Map<String, dynamic>>> publicRead(String token) async {
    publicCalls++;
    return response;
  }

  @override
  Future<Result<Map<String, dynamic>>> state() async => response;
  @override
  Future<Result<Map<String, dynamic>>> acceptInvitation(String token) async {
    accepts++;
    return pendingAccept?.future ?? response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
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
      repository.response = Failure(
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
        ..response = Failure(
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
        const Success({
          'scope': {'rootProjectId': 'project'},
        }),
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
      final current = {
        'email': 'a@example.test',
        'expiresAt': '2030-01-02T00:00:00Z',
      };
      expect(
        pendingInvitations([
          {'email': 'a@example.test', 'expiresAt': '2030-01-01T12:00:00Z'},
          current,
          {
            'email': 'b@example.test',
            'expiresAt': '2030-01-02T00:00:00Z',
            'acceptedAt': 'today',
          },
          {'email': 'c@example.test', 'expiresAt': '2030-01-01T00:00:00Z'},
        ], DateTime.utc(2030)),
        [current],
      );
    },
  );
}
