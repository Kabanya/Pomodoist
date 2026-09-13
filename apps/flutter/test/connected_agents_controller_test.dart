import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';

void main() {
  for (final initial in <List<AccountOAuthGrant>?>[
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
        final account = _Account();
        final container = _container(account);
        final subscription = container.listen(
          connectedAgentsProvider,
          (_, _) {},
        );
        final controller = container.read(connectedAgentsProvider.notifier);
        expect(container.read(connectedAgentsProvider).isLoading, isTrue);
        await _settle();
        final first = controller.refresh();
        if (initial == null) {
          account.requests.single.completeError(StateError('offline'));
        } else {
          account.requests.single.complete(initial);
        }
        await first;
        final previous = container.read(connectedAgentsProvider);
        expect(previous.isLoading, isFalse);
        expect(previous.hasError, initial == null);
        expect(controller.grants, initial);

        subscription.close();
        await container.pump();
        expect(container.read(connectedAgentsProvider), same(previous));
        expect(account.requests, hasLength(1));

        final refresh = controller.refresh();
        final duplicate = controller.refresh();
        expect(duplicate, same(refresh));
        expect(account.requests, hasLength(2));
        expect(container.read(connectedAgentsProvider), same(previous));
        expect(controller.grants, initial);
        account.requests.last.complete([_grantB]);
        await refresh;
        expect(container.read(connectedAgentsProvider).hasError, isFalse);
        expect(controller.grants, [_grantB]);
      },
    );
  }

  test('background error retains the last list until retry succeeds', () async {
    final account = _Account();
    final container = _container(account);
    final controller = container.read(connectedAgentsProvider.notifier);
    await _settle();
    account.requests.single.complete([_grant]);
    await controller.refresh();

    final refresh = controller.refresh();
    account.requests.last.completeError(StateError('offline'));
    await refresh;
    final failed = container.read(connectedAgentsProvider);
    expect(failed.hasError, isTrue);
    expect(failed.isLoading, isFalse);
    expect(controller.grants, [_grant]);

    final retry = controller.refresh();
    expect(container.read(connectedAgentsProvider), same(failed));
    account.requests.last.complete([]);
    await retry;
    expect(controller.grants, isEmpty);
    expect(container.read(connectedAgentsProvider).hasError, isFalse);
  });

  for (final listening in [true, false]) {
    test(
      'token renewal retains data; account changes discard stale requests (listening: $listening)',
      () async {
        final account = _Account();
        final container = _container(account);
        final subscription = container.listen(
          connectedAgentsProvider,
          (_, _) {},
        );
        final controller = container.read(connectedAgentsProvider.notifier);
        await _settle();
        account.requests.single.complete([_grant]);
        await controller.refresh();
        final previous = container.read(connectedAgentsProvider);
        if (!listening) {
          subscription.close();
          await container.pump();
        }

        container.updateOverrides(_overrides(account, token: 'renewed'));
        await container.pump();
        expect(container.read(connectedAgentsProvider), same(previous));
        expect(account.requests, hasLength(1));

        final stale = controller.refresh();
        account.userId = 'user-b';
        container.updateOverrides(_overrides(account));
        await container.pump();
        expect(container.read(connectedAgentsProvider).isLoading, isTrue);
        await _settle();
        expect(controller.grants, isNull);
        expect(account.requests, hasLength(3));
        account.requests[1].complete([_grant]);
        await stale;
        expect(controller.grants, isNull);
        account.requests.last.complete([_grantB]);
        await controller.refresh();
        expect(controller.grants, [_grantB]);

        container.updateOverrides(_overrides(account, signedIn: false));
        await container.pump();
        expect(container.read(connectedAgentsProvider).isLoading, isFalse);
        expect(controller.grants, isNull);
        container.updateOverrides(_overrides(account));
        await container.pump();
        expect(container.read(connectedAgentsProvider).isLoading, isTrue);
        await _settle();
        expect(controller.grants, isNull);
        expect(account.requests, hasLength(4));
        account.requests.last.complete([]);
        await controller.refresh();
      },
    );
  }

  test(
    'signing out and back in while settings are closed clears the cached session',
    () async {
      final account = _Account();
      final container = _container(account);
      final subscription = container.listen(connectedAgentsProvider, (_, _) {});
      final controller = container.read(connectedAgentsProvider.notifier);
      await _settle();
      account.requests.single.complete([_grant]);
      await controller.refresh();
      final stale = controller.refresh();
      subscription.close();
      await container.pump();

      container.updateOverrides(_overrides(account, signedIn: false));
      await container.pump();
      container.updateOverrides(_overrides(account));
      await container.pump();
      account.requests.last.complete([_grant]);
      await stale;

      expect(controller.grants, isNull);
      expect(container.read(connectedAgentsProvider).isLoading, isTrue);
      expect(controller.grants, isNull);
      await _settle();
      account.requests.last.complete([]);
      await controller.refresh();
    },
  );

  test(
    'replacement client ignores an old revoke even for the same user',
    () async {
      final account = _Account();
      final container = _container(account);
      container.listen(connectedAgentsProvider, (_, _) {});
      final controller = container.read(connectedAgentsProvider.notifier);
      await _settle();
      account.requests.single.complete([_grant]);
      await controller.refresh();
      final revoke = controller.revoke(_grant.clientId);

      final replacement = _Account();
      container.updateOverrides(_overrides(replacement));
      await container.pump();
      await _settle();
      expect(container.read(connectedAgentsProvider).isLoading, isTrue);
      expect(controller.grants, isNull);
      replacement.requests.single.complete([_grant]);
      await controller.refresh();
      account.revocation.complete();
      await revoke;
      expect(controller.grants, [_grant]);
      expect(replacement.requests, hasLength(1));
      expect(replacement.revokedIds, isEmpty);
    },
  );

  test(
    'successful revoke removes immediately and rejects older list responses',
    () async {
      final account = _Account();
      final container = _container(account);
      final controller = container.read(connectedAgentsProvider.notifier);
      await _settle();
      account.requests.single.complete([_grant, _grantB]);
      await controller.refresh();
      final staleRefresh = controller.refresh();
      final revoke = controller.revoke(_grant.clientId);
      expect(controller.grants, [_grant, _grantB]);
      expect(account.revokedIds, [_grant.clientId]);
      account.revocation.complete();
      await _settle();
      expect(controller.grants, [_grantB]);
      expect(container.read(connectedAgentsProvider).isLoading, isFalse);
      expect(account.requests, hasLength(3));

      account.requests[1].complete([_grant, _grantB]);
      await staleRefresh;
      expect(controller.grants, [_grantB]);
      account.requests.last.completeError(StateError('refresh failed'));
      await revoke;
      expect(controller.grants, [_grantB]);
      expect(container.read(connectedAgentsProvider).hasError, isTrue);
    },
  );

  test(
    'failed revoke keeps the grant and reports failure to the caller',
    () async {
      final account = _Account();
      final container = _container(account);
      final controller = container.read(connectedAgentsProvider.notifier);
      await _settle();
      account.requests.single.complete([_grant]);
      await controller.refresh();
      final revoke = controller.revoke(_grant.clientId);
      final assertion = expectLater(revoke, throwsStateError);
      account.revocation.completeError(StateError('offline'));
      await assertion;
      expect(controller.grants, [_grant]);
      expect(account.requests, hasLength(1));
    },
  );
}

ProviderContainer _container(_Account account) {
  final container = ProviderContainer(overrides: _overrides(account));
  addTearDown(container.dispose);
  return container;
}

List<Override> _overrides(
  _Account account, {
  String token = 'token',
  bool signedIn = true,
}) => [
  accountClientProvider.overrideWithValue(account),
  accountConfiguredProvider.overrideWithValue(true),
  accountAuthStateProvider.overrideWithValue(
    AsyncData(
      AccountAuthState(
        signedIn: signedIn,
        session: signedIn
            ? AccountSession(userId: account.userId, accessToken: token)
            : null,
      ),
    ),
  ),
];

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final _grant = AccountOAuthGrant(
  clientId: 'client-a',
  clientName: 'Agent A',
  scopes: const [],
  connectedAt: DateTime.utc(2026, 9, 1),
);
final _grantB = AccountOAuthGrant(
  clientId: 'client-b',
  clientName: 'Agent B',
  scopes: const [],
  connectedAt: DateTime.utc(2026, 9, 2),
);

class _Account implements AccountClient {
  String userId = 'user-a';
  final requests = <Completer<List<AccountOAuthGrant>>>[];
  final revocation = Completer<void>();
  final revokedIds = <String>[];

  @override
  String get currentUserId => userId;

  @override
  Future<List<AccountOAuthGrant>> listOAuthGrants() {
    final request = Completer<List<AccountOAuthGrant>>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> revokeOAuthGrant(String clientId) {
    revokedIds.add(clientId);
    return revocation.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
