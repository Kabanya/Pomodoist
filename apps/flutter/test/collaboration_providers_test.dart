import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/collaboration/presentation/collaboration_providers.dart';

void main() {
  test(
    'collaboration repository appears once the account signs in',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final account = _MutableAuthAccountClient();
      addTearDown(account.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          accountClientProvider.overrideWithValue(account),
        ],
      );
      addTearDown(container.dispose);

      final repositoryReady = Completer<void>();
      container.listen(
        collaborationRepositoryProvider,
        (previous, next) {
          if (next != null && !repositoryReady.isCompleted) {
            repositoryReady.complete();
          }
        },
        fireImmediately: true,
      );

      expect(container.read(collaborationRepositoryProvider), isNull);

      await container.read(accountAuthStateProvider.future);
      await Future<void>.delayed(Duration.zero);

      account.signIn('user-1');
      await repositoryReady.future;

      expect(container.read(collaborationRepositoryProvider), isNotNull);
    },
  );

  test(
    'collaboration repository survives a stale signed-out auth state',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final account = _MutableAuthAccountClient();
      addTearDown(account.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          accountClientProvider.overrideWithValue(account),
        ],
      );
      addTearDown(container.dispose);

      final repositoryReady = Completer<void>();
      container.listen(
        collaborationRepositoryProvider,
        (previous, next) {
          if (next != null && !repositoryReady.isCompleted) {
            repositoryReady.complete();
          }
        },
        fireImmediately: true,
      );

      await container.read(accountAuthStateProvider.future);
      await Future<void>.delayed(Duration.zero);

      account.signIn('user-1');
      await repositoryReady.future;

      // The auth stream can report a stale signed-out snapshot while the live
      // session is intact, so a later share tap must still find the repository.
      account.reportSignedOut();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(accountAuthStateProvider).value?.signedIn, isFalse);

      expect(container.read(collaborationRepositoryProvider), isNotNull);
      expect(container.read(accountSyncEngineProvider), isNotNull);
    },
  );
}

class _MutableAuthAccountClient implements AccountClient {
  String? userId;
  final _authStates = StreamController<AccountAuthState>.broadcast();

  @override
  String? get currentUserId => userId;

  @override
  AccountSession? get currentSession => userId == null
      ? null
      : AccountSession(userId: userId!, accessToken: 'test-token');

  @override
  Stream<AccountAuthState> accountAuthStateChanges() => _authStates.stream;

  void signIn(String id) {
    userId = id;
    _authStates.add(AccountAuthState(signedIn: true, session: currentSession));
  }

  void reportSignedOut() {
    _authStates.add(const AccountAuthState(signedIn: false));
  }

  Future<void> close() => _authStates.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
