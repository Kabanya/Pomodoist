import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/native_account_startup.dart';
import 'package:pomodoist/app/native_link_coordinator_core.dart';

void main() {
  test(
    'pending initial link does not block startup and routes when ready',
    () async {
      final initialLink = Completer<Uri?>();
      final routes = <String>[];
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () => initialLink.future,
        loadLinkStream: () => const Stream<Uri>.empty(),
      );
      addTearDown(() async {
        if (!initialLink.isCompleted) initialLink.complete(null);
        await coordinator.dispose();
      });

      final startup = await prepareNativeAccountStartup(
        links: coordinator,
        initializeAccount: () async => 'configured-account',
      ).timeout(Duration.zero);

      expect(await startup.initializeAccount(), 'configured-account');
      coordinator.attachRouteSink(routes.add);
      initialLink.complete(Uri.parse('pomodoist://focus'));
      await pumpEventQueue();

      expect(routes, ['/focus']);
    },
  );

  test('account auth owns the initial native callback stream', () async {
    final events = <String>[];
    final authCallbacks = <Uri>[];
    final callback = Uri.parse(
      'pomodoist://login-callback?code=test-oauth-code',
    );
    late final StreamController<Uri> platformLinks;
    platformLinks = StreamController<Uri>.broadcast(
      onListen: () {
        scheduleMicrotask(() => platformLinks.add(callback));
      },
    );
    StreamController<Uri>? sharedController;
    Stream<Uri> loadSharedAppLinksStream() {
      events.add('app-links-stream');
      final existing = sharedController;
      if (existing != null) return existing.stream;
      final controller = StreamController<Uri>.broadcast();
      sharedController = controller;
      platformLinks.stream.listen(controller.add);
      return controller.stream;
    }

    final coordinator = NativeLinkCoordinator(
      loadInitialLink: () async {
        events.add('prepare');
        return callback;
      },
      loadLinkStream: loadSharedAppLinksStream,
    );
    StreamSubscription<Uri>? authSubscription;
    final startup = await prepareNativeAccountStartup(
      links: coordinator,
      initializeAccount: () async {
        events.add('account');
        authSubscription = loadSharedAppLinksStream().listen(authCallbacks.add);
        await Future<void>.delayed(Duration.zero);
        return 'configured-account';
      },
    );

    expect(events, ['prepare', 'account', 'app-links-stream']);
    expect(await startup.initializeAccount(), 'configured-account');
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      'prepare',
      'account',
      'app-links-stream',
      'app-links-stream',
    ]);
    expect(authCallbacks, [callback]);

    await authSubscription?.cancel();
    await coordinator.dispose();
    await sharedController?.close();
    await platformLinks.close();
  });

  test(
    'failed account startup preserves links until a retry succeeds',
    () async {
      final events = <String>[];
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () async {
          events.add('prepare');
          return null;
        },
        loadLinkStream: () {
          events.add('links');
          return const Stream<Uri>.empty();
        },
      );
      var attempts = 0;
      final startup = await prepareNativeAccountStartup(
        links: coordinator,
        initializeAccount: () async {
          attempts += 1;
          events.add('account-$attempts');
          if (attempts == 1) throw StateError('offline');
          return 'retry-account';
        },
      );

      expect(events, ['prepare', 'account-1']);
      await expectLater(startup.initializeAccount(), throwsStateError);
      expect(events, ['prepare', 'account-1']);
      expect(await startup.initializeAccount(), 'retry-account');
      await Future<void>.delayed(Duration.zero);
      expect(events, ['prepare', 'account-1', 'account-2', 'links']);

      await coordinator.dispose();
    },
  );

  test(
    'late account startup preserves the callback until it succeeds',
    () async {
      final pending = Completer<String>();
      var linksStarted = false;
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () async => null,
        loadLinkStream: () {
          linksStarted = true;
          return const Stream<Uri>.empty();
        },
      );
      final startup = await prepareNativeAccountStartup(
        links: coordinator,
        initializeAccount: () => pending.future,
      );

      await expectLater(
        startup.initialAttempt.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );

      expect(linksStarted, isFalse);
      final providerAttempt = startup.initializeAccount();
      expect(identical(providerAttempt, pending.future), isTrue);

      pending.complete('late-account');
      expect(await providerAttempt, 'late-account');
      await Future<void>.delayed(Duration.zero);
      expect(linksStarted, isTrue);
      await coordinator.dispose();
    },
  );
}
