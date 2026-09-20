import 'dart:async';
import 'package:app_account/app_account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/data/repositories/account/sdk_account_session_repository.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';

class FakeAccount extends Fake implements AccountClient {
  @override
  String? get currentUserId => 'signed-in-user';
  @override
  Stream<AccountAuthState> accountAuthStateChanges() => Stream.value(
    const AccountAuthState(
      signedIn: true,
      session: AccountSession(userId: 'signed-in-user'),
    ),
  );
}

void main() {
  test('session adopts account after asynchronous bootstrap', () async {
    final ready = Completer<AccountClient?>();
    final container = ProviderContainer(
      overrides: [
        accountBootstrapInitializerProvider.overrideWithValue(
          () => ready.future,
        ),
        accountOverviewProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      accountSessionProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(container.read(accountSessionProvider).value?.userId, isNull);
    ready.complete(FakeAccount());
    await pumpEventQueue();
    expect(
      container.read(accountClientProvider)?.currentUserId,
      'signed-in-user',
    );
    expect(
      container.read(accountSessionProvider).value?.userId,
      'signed-in-user',
    );
    expect(container.read(accountSignedInProvider), isTrue);
  });
  test(
    'pending profile load cannot publish after repository disposal',
    () async {
      final pending = Completer<PomodoistAccountOverview?>();
      final repository = SdkAccountSessionRepository(
        currentUserId: () => 'signed-in-user',
        authChanges: () => const Stream.empty(),
        overviewLoader: () => pending.future,
      );
      await repository.watchSession().first;
      await repository.dispose();
      pending.complete(
        PomodoistAccountOverview(
          profile: const PomodoistAccountProfile(id: 'signed-in-user'),
          apps: const [],
          generatedAt: DateTime.utc(2026),
        ),
      );
      await pumpEventQueue();
    },
  );
}
