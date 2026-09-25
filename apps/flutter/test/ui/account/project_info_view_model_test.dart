import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/collaboration/view_models/project_info_view_model.dart';
import 'package:pomodoist/ui/collaboration/widgets/collaboration_copy.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_en.dart';

ProjectItem _project({String? scopeId, bool archived = false}) => ProjectItem(
  id: 'child',
  parentId: 'root',
  scopeId: scopeId,
  userId: 'local',
  name: 'Research',
  orderKey: 'a',
  isArchived: archived,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

SharedScope _scope({
  String role = 'member',
  String owner = 'owner',
  String? ownerName = 'Alex',
}) => SharedScope.fromJson({
  'id': 'scope',
  'rootProjectId': 'root',
  'ownerId': owner,
  'role': role,
  'members': [
    {'userId': 'owner', 'role': 'administrator', 'displayName': ownerName},
    {
      'userId': 'me',
      'role': owner == 'me' ? 'administrator' : role,
      'displayName': 'Sam',
    },
  ],
});

void main() {
  late StreamController<List<ProjectItem>> projects;
  late StreamController<List<SharedScope>> scopes;
  late Completer<String> actor;
  late ProviderContainer container;
  final provider = projectInfoViewModelProvider('child');

  setUp(() {
    projects = StreamController<List<ProjectItem>>();
    scopes = StreamController<List<SharedScope>>.broadcast();
    actor = Completer<String>();
    container = ProviderContainer(
      overrides: [
        projectsProvider.overrideWith((_) => projects.stream),
        sharedScopesProvider.overrideWith((_) => scopes.stream),
        collaborationActorIdProvider.overrideWith((_) => actor.future),
      ],
    );
    container.listen(sharedScopesProvider, (_, _) {});
    container.listen(collaborationActorIdProvider, (_, _) {});
    container.listen(provider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await projects.close();
    await scopes.close();
  });

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  test('personal archived project needs no collaboration data', () async {
    projects.add([_project(archived: true)]);
    await settle();
    final info = container.read(provider).requireValue;
    expect(info.project.name, 'Research');
    expect(info.project.isArchived, isTrue);
    expect(info.scope, isNull);
    expect(info.memberCount, 1);
  });

  for (final role in CollaborationRole.values) {
    test(
      'subproject exposes shared owner and members for ${role.name}',
      () async {
        projects.add([_project(scopeId: 'scope')]);
        scopes.add([_scope(role: role.name)]);
        actor.complete('me');
        await settle();
        final info = container.read(provider).requireValue;
        expect(info.project.id, 'child');
        expect(info.scope!.rootProjectId, 'root');
        expect(info.scope!.ownerId, 'owner');
        expect(info.scope!.role, role);
        expect(info.scope!.members.map((member) => member.userId), [
          'owner',
          'me',
        ]);
        expect(info.actorId, 'me');
        expect(info.memberCount, 2);
      },
    );
  }

  test('ownership and role update while information is open', () async {
    projects.add([_project(scopeId: 'scope')]);
    scopes.add([_scope()]);
    actor.complete('me');
    await settle();
    expect(container.read(provider).requireValue.scope!.ownerId, 'owner');
    scopes.add([_scope(owner: 'me', role: 'administrator')]);
    await settle();
    final info = container.read(provider).requireValue;
    expect(info.scope!.ownerId, info.actorId);
    expect(info.scope!.role, CollaborationRole.administrator);
  });

  test(
    'missing owner name uses the existing localized member fallback',
    () async {
      projects.add([_project(scopeId: 'scope')]);
      scopes.add([_scope(ownerName: null)]);
      actor.complete('me');
      await settle();
      final scope = container.read(provider).requireValue.scope!;
      expect(
        collaborationMemberLabel(AppLocalizationsEn(), scope, scope.ownerId),
        'Member',
      );
    },
  );

  test('project, scope and actor loading never become personal data', () async {
    expect(container.read(provider).isLoading, isTrue);
    projects.add([_project(scopeId: 'scope')]);
    await settle();
    expect(container.read(provider).isLoading, isTrue);
    scopes.add([_scope()]);
    await settle();
    expect(container.read(provider).isLoading, isTrue);
    actor.complete('me');
    await settle();
    expect(container.read(provider).requireValue.scope, isNotNull);
  });

  test('missing or revoked scope is unavailable, never personal', () async {
    projects.add([_project(scopeId: 'scope')]);
    scopes.add([]);
    actor.complete('me');
    await settle();
    expect(container.read(provider).hasError, isTrue);
    scopes.add([_scope()]);
    await settle();
    expect(container.read(provider).requireValue.scope, isNotNull);
    scopes.add([]);
    await settle();
    expect(container.read(provider).hasError, isTrue);
  });

  test(
    'scope stream errors replace previously available information',
    () async {
      projects.add([_project(scopeId: 'scope')]);
      scopes.add([_scope()]);
      actor.complete('me');
      await settle();
      scopes.addError(StateError('scope read failed'));
      await settle();
      expect(container.read(provider).hasError, isTrue);
    },
  );

  test('scope without a synchronized member list is unavailable', () async {
    projects.add([_project(scopeId: 'scope')]);
    scopes.add([
      SharedScope.fromJson({
        'id': 'scope',
        'rootProjectId': 'root',
        'ownerId': 'owner',
        'role': 'member',
      }),
    ]);
    actor.complete('me');
    await settle();
    expect(container.read(provider).hasError, isTrue);
    scopes.add([_scope()]);
    await settle();
    expect(container.read(provider).requireValue.memberCount, 2);
  });

  test('project and actor failures remain errors', () async {
    projects.addError(StateError('project read failed'));
    await settle();
    expect(container.read(provider).hasError, isTrue);
    projects.add([_project(scopeId: 'scope')]);
    scopes.add([_scope()]);
    await settle();
    actor.completeError(StateError('actor read failed'));
    await settle();
    expect(container.read(provider).hasError, isTrue);
  });

  test('deleted project does not leave stale information open', () async {
    projects.add([_project()]);
    await settle();
    expect(container.read(provider).hasValue, isTrue);
    projects.add([]);
    await settle();
    expect(container.read(provider).hasError, isTrue);
  });
}
