import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/account/sdk_account_session_repository.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/utils/result.dart';

PomodoistAccountOverview _overview(String id) => PomodoistAccountOverview(
  profile: PomodoistAccountProfile(id: id, displayName: id),
  apps: const [],
  generatedAt: DateTime.utc(2026),
);

void main() {
  test(
    'an unresolved profile request cannot publish after an account change',
    () async {
      final auth = StreamController<AccountAuthState>.broadcast();
      addTearDown(auth.close);
      var userId = 'a';
      final first = Completer<PomodoistAccountOverview?>();
      final second = Completer<PomodoistAccountOverview?>();
      final repository = SdkAccountSessionRepository(
        currentUserId: () => userId,
        authChanges: () => auth.stream,
        overviewLoader: () => userId == 'a' ? first.future : second.future,
      );
      addTearDown(repository.dispose);

      final profiles = <PomodoistAccountProfile?>[];
      repository.watchProfile().listen(profiles.add);
      await pumpEventQueue();

      userId = 'b';
      auth.add(
        AccountAuthState(signedIn: true, session: AccountSession(userId: 'b')),
      );
      await pumpEventQueue();
      expect(profiles.last, isNull);

      first.complete(_overview('a'));
      await pumpEventQueue();
      expect(profiles.where((profile) => profile?.id == 'a'), isEmpty);

      second.complete(_overview('b'));
      await pumpEventQueue();
      expect(profiles.last?.id, 'b');
    },
  );

  test('sign-out during refresh drops the late profile', () async {
    final auth = StreamController<AccountAuthState>.broadcast();
    addTearDown(auth.close);
    var userId = 'a';
    final pending = Completer<PomodoistAccountOverview?>();
    final repository = SdkAccountSessionRepository(
      currentUserId: () => userId,
      authChanges: () => auth.stream,
      overviewLoader: () => pending.future,
    );
    addTearDown(repository.dispose);

    final profiles = <PomodoistAccountProfile?>[];
    repository.watchProfile().listen(profiles.add);
    await pumpEventQueue();

    final refresh = repository.refresh();
    userId = '';
    auth.add(const AccountAuthState(signedIn: false));
    await pumpEventQueue();
    pending.complete(_overview('a'));

    expect(await refresh, isA<Success<void>>());
    expect(profiles.where((profile) => profile?.id == 'a'), isEmpty);
    expect(profiles.last, isNull);
  });

  test('guest-to-account adoption increments the generation', () async {
    final auth = StreamController<AccountAuthState>.broadcast();
    addTearDown(auth.close);
    var userId = '';
    final repository = SdkAccountSessionRepository(
      currentUserId: () => userId.isEmpty ? null : userId,
      authChanges: () => auth.stream,
      overviewLoader: () async => _overview('a'),
    );
    addTearDown(repository.dispose);

    final sessions = <({String? userId, int generation})>[];
    repository.watchSession().listen(sessions.add);
    await pumpEventQueue();
    expect(sessions.last, (userId: null, generation: 0));

    userId = 'a';
    auth.add(
      AccountAuthState(signedIn: true, session: AccountSession(userId: 'a')),
    );
    await pumpEventQueue();
    expect(sessions.last, (userId: 'a', generation: 1));
  });

  test(
    'expired startup retries adopt the account without losing generation',
    () async {
      final auth = StreamController<AccountAuthState>.broadcast();
      addTearDown(auth.close);
      var userId = '';
      final repository = SdkAccountSessionRepository(
        currentUserId: () => userId.isEmpty ? null : userId,
        authChanges: () => auth.stream,
        overviewLoader: () async => _overview('a'),
      );
      addTearDown(repository.dispose);

      final sessions = <({String? userId, int generation})>[];
      repository.watchSession().listen(sessions.add);
      await pumpEventQueue();
      auth.add(const AccountAuthState(signedIn: false));
      auth.add(
        AccountAuthState(signedIn: true, session: AccountSession(userId: 'a')),
      );
      await pumpEventQueue();
      expect(sessions.map((session) => session.userId).toList(), [null, 'a']);
      expect(sessions.last.generation, 1);
    },
  );

  test('refresh failure returns Failure and keeps the last profile', () async {
    final repository = SdkAccountSessionRepository(
      currentUserId: () => 'a',
      authChanges: () => const Stream<AccountAuthState>.empty(),
      overviewLoader: () async => throw StateError('offline'),
    );
    addTearDown(repository.dispose);

    expect(await repository.refresh(), isA<Failure<void>>());
  });
}
