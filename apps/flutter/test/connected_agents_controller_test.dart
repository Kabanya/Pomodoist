import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_management_dependencies.dart';
import 'package:pomodoist/data/repositories/account/account_management_repository.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';
import 'package:pomodoist/ui/settings/view_models/connected_agents_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  for (final initial in <List<ConnectedAgent>?>[
    [_grant],
    [],
    null,
  ]) {
    test(
      'retains ${initial == null
          ? 'error'
          : initial.isEmpty
          ? 'empty list'
          : 'agents'} across visits and refreshes',
      () async {
        final repository = _FakeRepository();
        final container = _container(repository);
        final subscription = container.listen(
          connectedAgentsViewModelProvider,
          (_, _) {},
        );
        final controller = container.read(
          connectedAgentsViewModelProvider.notifier,
        );
        expect(
          container.read(connectedAgentsViewModelProvider).isLoading,
          isTrue,
        );
        await _settle();
        final first = controller.refresh();
        if (initial == null) {
          repository.requests.single.completeError(StateError('offline'));
        } else {
          repository.requests.single.complete(initial);
        }
        await first;
        final previous = container.read(connectedAgentsViewModelProvider);
        expect(previous.isLoading, isFalse);
        expect(previous.hasError, initial == null);
        expect(
          _clientIds(previous.grants),
          initial == null ? isNull : _clientIds(initial),
        );

        subscription.close();
        await container.pump();
        expect(
          container.read(connectedAgentsViewModelProvider),
          same(previous),
        );
        expect(repository.requests, hasLength(1));

        final refresh = controller.refresh();
        final duplicate = controller.refresh();
        expect(duplicate, same(refresh));
        expect(repository.requests, hasLength(2));
        expect(
          container.read(connectedAgentsViewModelProvider),
          same(previous),
        );
        expect(
          _clientIds(container.read(connectedAgentsViewModelProvider).grants),
          initial == null ? isNull : _clientIds(initial),
        );
        repository.requests.last.complete([_grantB]);
        await refresh;
        expect(
          container.read(connectedAgentsViewModelProvider).hasError,
          isFalse,
        );
        expect(
          _clientIds(container.read(connectedAgentsViewModelProvider).grants),
          ['client-b'],
        );
      },
    );
  }

  test('background error retains the last list until retry succeeds', () async {
    final repository = _FakeRepository();
    final container = _container(repository);
    final controller = container.read(connectedAgentsViewModelProvider.notifier);
    await _settle();
    repository.requests.single.complete([_grant]);
    await controller.refresh();

    final refresh = controller.refresh();
    repository.requests.last.completeError(StateError('offline'));
    await refresh;
    final failed = container.read(connectedAgentsViewModelProvider);
    expect(failed.hasError, isTrue);
    expect(failed.isLoading, isFalse);
    expect(_clientIds(failed.grants), ['client-a']);

    final retry = controller.refresh();
    expect(container.read(connectedAgentsViewModelProvider), same(failed));
    repository.requests.last.complete([]);
    await retry;
    expect(container.read(connectedAgentsViewModelProvider).grants, isEmpty);
    expect(
      container.read(connectedAgentsViewModelProvider).hasError,
      isFalse,
    );
  });

  test('account changes discard stale requests and load the new user', () async {
    final repository = _FakeRepository();
    final container = _container(repository);
    container.listen(connectedAgentsViewModelProvider, (_, _) {});
    final controller = container.read(connectedAgentsViewModelProvider.notifier);
    await _settle();
    repository.requests.single.complete([_grant]);
    await controller.refresh();
    expect(
      _clientIds(container.read(connectedAgentsViewModelProvider).grants),
      ['client-a'],
    );

    final stale = controller.refresh();
    final replacement = _FakeRepository(userId: 'user-b');
    container.updateOverrides(_overrides(replacement));
    await container.pump();
    expect(
      container.read(connectedAgentsViewModelProvider).isLoading,
      isTrue,
    );
    expect(container.read(connectedAgentsViewModelProvider).grants, isNull);
    await _settle();
    expect(replacement.requests, hasLength(1));

    repository.requests[1].complete([_grant]);
    await stale;
    expect(container.read(connectedAgentsViewModelProvider).grants, isNull);

    replacement.requests.last.complete([_grantB]);
    await container.read(connectedAgentsViewModelProvider.notifier).refresh();
    expect(
      _clientIds(container.read(connectedAgentsViewModelProvider).grants),
      ['client-b'],
    );

    container.updateOverrides([
      accountManagementRepositoryProvider.overrideWithValue(null),
    ]);
    await container.pump();
    expect(
      container.read(connectedAgentsViewModelProvider).isLoading,
      isFalse,
    );
    expect(container.read(connectedAgentsViewModelProvider).grants, isEmpty);
    container.updateOverrides(_overrides(replacement));
    await container.pump();
    expect(
      container.read(connectedAgentsViewModelProvider).isLoading,
      isTrue,
    );
    await _settle();
    expect(container.read(connectedAgentsViewModelProvider).grants, isNull);
    replacement.requests.last.complete([]);
    await container.read(connectedAgentsViewModelProvider.notifier).refresh();
  });

  test(
    'replacement client ignores an old revoke even for the same user',
    () async {
      final repository = _FakeRepository();
      final container = _container(repository);
      container.listen(connectedAgentsViewModelProvider, (_, _) {});
      final controller = container.read(
        connectedAgentsViewModelProvider.notifier,
      );
      await _settle();
      repository.requests.single.complete([_grant]);
      await controller.refresh();
      final revoke = controller.revoke(_grant.clientId, 'user-a');

      final replacement = _FakeRepository();
      container.updateOverrides(_overrides(replacement));
      await container.pump();
      await _settle();
      expect(
        container.read(connectedAgentsViewModelProvider).isLoading,
        isTrue,
      );
      expect(container.read(connectedAgentsViewModelProvider).grants, isNull);
      replacement.requests.single.complete([_grant]);
      await container
          .read(connectedAgentsViewModelProvider.notifier)
          .refresh();
      expect(
        _clientIds(container.read(connectedAgentsViewModelProvider).grants),
        ['client-a'],
      );
      repository.revocation.complete();
      await revoke;
      expect(
        _clientIds(container.read(connectedAgentsViewModelProvider).grants),
        ['client-a'],
      );
      expect(replacement.requests, hasLength(1));
      expect(replacement.revokedIds, isEmpty);
    },
  );

  test(
    'successful revoke removes immediately and rejects older list responses',
    () async {
      final repository = _FakeRepository();
      final container = _container(repository);
      final controller = container.read(
        connectedAgentsViewModelProvider.notifier,
      );
      await _settle();
      repository.requests.single.complete([_grant, _grantB]);
      await controller.refresh();
      final staleRefresh = controller.refresh();
      final revoke = controller.revoke(_grant.clientId, 'user-a');
      expect(
        _clientIds(container.read(connectedAgentsViewModelProvider).grants),
        ['client-a', 'client-b'],
      );
      expect(repository.revokedIds, ['client-a']);
      repository.revocation.complete();
      await _settle();
      expect(
        _clientIds(container.read(connectedAgentsViewModelProvider).grants),
        ['client-b'],
      );
      expect(
        container.read(connectedAgentsViewModelProvider).isLoading,
        isFalse,
      );
      expect(repository.requests, hasLength(3));

      repository.requests[1].complete([_grant, _grantB]);
      await staleRefresh;
      expect(
        _clientIds(container.read(connectedAgentsViewModelProvider).grants),
        ['client-b'],
      );
      repository.requests.last.completeError(StateError('refresh failed'));
      await revoke;
      expect(
        _clientIds(container.read(connectedAgentsViewModelProvider).grants),
        ['client-b'],
      );
      expect(
        container.read(connectedAgentsViewModelProvider).hasError,
        isTrue,
      );
    },
  );

  test(
    'failed revoke keeps the grant and exposes the failure to the state',
    () async {
      final repository = _FakeRepository();
      final container = _container(repository);
      final controller = container.read(
        connectedAgentsViewModelProvider.notifier,
      );
      await _settle();
      repository.requests.single.complete([_grant]);
      await controller.refresh();
      final revoke = controller.revoke(_grant.clientId, 'user-a');
      repository.revocation.completeError(StateError('offline'));
      await revoke;
      expect(
        _clientIds(container.read(connectedAgentsViewModelProvider).grants),
        ['client-a'],
      );
      expect(
        container.read(connectedAgentsViewModelProvider).revokeError,
        isNotNull,
      );
      expect(repository.requests, hasLength(1));
    },
  );
}

ProviderContainer _container(_FakeRepository repository) {
  final container = ProviderContainer(overrides: _overrides(repository));
  addTearDown(container.dispose);
  return container;
}

List<Override> _overrides(_FakeRepository repository) => [
  accountManagementRepositoryProvider.overrideWithValue(repository),
];

List<String>? _clientIds(List<ConnectedAgent>? agents) =>
    agents?.map((agent) => agent.clientId).toList();

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final _grant = ConnectedAgent(
  clientId: 'client-a',
  clientName: 'Agent A',
  connectedAt: DateTime.utc(2026, 9, 1),
);
final _grantB = ConnectedAgent(
  clientId: 'client-b',
  clientName: 'Agent B',
  connectedAt: DateTime.utc(2026, 9, 2),
);

class _FakeRepository implements AccountManagementRepository {
  _FakeRepository({this.userId = 'user-a'});

  @override
  final String? userId;
  final requests = <Completer<List<ConnectedAgent>>>[];
  final revocation = Completer<void>();
  final revokedIds = <String>[];

  @override
  String? get email => null;

  @override
  bool get isCurrent => true;

  @override
  Future<Result<List<ConnectedAgent>>> connectedAgents() async {
    final request = Completer<List<ConnectedAgent>>();
    requests.add(request);
    return Success(await request.future);
  }

  @override
  Future<Result<void>> revokeAgent(String clientId) async {
    revokedIds.add(clientId);
    await revocation.future;
    return const Success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
