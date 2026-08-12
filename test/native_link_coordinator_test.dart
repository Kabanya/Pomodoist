import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/native_link_coordinator.dart';

void main() {
  test('fingerprints canonical URI bytes without retaining raw secrets', () {
    final first = Uri.parse(
      'pomodoist://captcha-callback?state=${'A' * 43}&token=TOKEN_ONE',
    );
    final second = Uri.parse(
      'pomodoist://captcha-callback?state=${'A' * 43}&token=TOKEN_TWO',
    );

    final fingerprint = nativeLinkFingerprint(first);

    expect(
      fingerprint,
      sha256.convert(utf8.encode(first.toString())).toString(),
    );
    expect(nativeLinkFingerprint(first), fingerprint);
    expect(nativeLinkFingerprint(second), isNot(fingerprint));
    expect(fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(fingerprint, isNot(contains('TOKEN_ONE')));
    expect(fingerprint, isNot(contains('state')));
  });

  test('buffers an initial focus route until the router attaches', () async {
    final links = StreamController<Uri>.broadcast();
    final coordinator = NativeLinkCoordinator(
      loadInitialLink: () async => Uri.parse('pomodoist://focus'),
      linkStream: links.stream,
    );

    await coordinator.prepare();
    await coordinator.start();
    final routes = <String>[];
    final detach = coordinator.attachRouteSink(routes.add);

    expect(routes, ['/focus']);

    detach();
    await coordinator.dispose();
    await links.close();
  });

  test('routes only the exact Stripe purchase fallback link', () {
    expect(
      nativeRouteForLink(Uri.parse('pomodoist://purchase-success')),
      '/purchase-success?source=stripe',
    );
    expect(
      nativeRouteForLink(Uri.parse('pomodoist://purchase-success?next=evil')),
      isNull,
    );
    expect(
      nativeRouteForLink(Uri.parse('pomodoist://purchase-success/path')),
      isNull,
    );
  });

  test(
    'dispatches exact CAPTCHA callbacks to the shared stream once',
    () async {
      final links = StreamController<Uri>.broadcast();
      final callback = Uri.parse(
        'pomodoist://captcha-callback?state=${'A' * 43}&token=opaque-token',
      );
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () async => callback,
        linkStream: links.stream,
      );
      final callbacks = <Uri>[];
      final subscription = coordinator.captchaCallbacks.listen(callbacks.add);
      await coordinator.prepare();
      await coordinator.start();

      links.add(callback);
      links.add(callback);
      links.add(
        Uri.parse(
          'pomodoist://captcha-callback?state=${'A' * 43}'
          '&token=opaque-token&extra=unsafe',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(callbacks, [callback]);

      await subscription.cancel();
      await coordinator.dispose();
      await links.close();
    },
  );

  test(
    'preserves only a safe login return route and keeps auth data out of routing',
    () async {
      final links = StreamController<Uri>.broadcast();
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () async => null,
        linkStream: links.stream,
      );
      final rawLinks = <Uri>[];
      final rawSubscription = links.stream.listen(rawLinks.add);
      final routes = <String>[];
      coordinator.attachRouteSink(routes.add);
      await coordinator.prepare();
      await coordinator.start();

      final authLink = Uri.parse(
        'pomodoist://login-callback?code=AUTH_SECRET'
        '&returnTo=%2Fsettings%3Ftab%3Daccount',
      );
      links.add(authLink);
      await Future<void>.delayed(Duration.zero);

      expect(rawLinks, [authLink]);
      expect(routes, ['/login-callback?returnTo=%2Fsettings%3Ftab%3Daccount']);
      expect(routes.single, isNot(contains('AUTH_SECRET')));

      await rawSubscription.cancel();
      await coordinator.dispose();
      await links.close();
    },
  );

  test(
    'handles streamed focus links, duplicates, and disposal safely',
    () async {
      var clock = DateTime.utc(2026, 7, 12, 12);
      final links = StreamController<Uri>.broadcast();
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () async => Uri.parse('pomodoist://focus'),
        linkStream: links.stream,
        now: () => clock,
        duplicateWindow: const Duration(seconds: 2),
      );
      final routes = <String>[];
      coordinator.attachRouteSink(routes.add);
      await coordinator.prepare();
      await coordinator.start();

      links.add(Uri.parse('pomodoist://focus'));
      await Future<void>.delayed(Duration.zero);
      expect(routes, ['/focus']);

      clock = clock.add(const Duration(seconds: 3));
      links.add(Uri.parse('pomodoist://focus'));
      await Future<void>.delayed(Duration.zero);
      expect(routes, ['/focus', '/focus']);

      await coordinator.dispose();
      links.add(Uri.parse('pomodoist://focus'));
      await Future<void>.delayed(Duration.zero);
      expect(routes, ['/focus', '/focus']);
      await links.close();
    },
  );

  test(
    'actively expires the digest and cancels replaced and disposed timers',
    () async {
      final links = StreamController<Uri>.broadcast();
      final expiries = <void Function()>[];
      final cancelled = <int>[];
      final coordinator = NativeLinkCoordinator(
        loadInitialLink: () async => null,
        linkStream: links.stream,
        duplicateWindow: const Duration(seconds: 2),
        scheduleFingerprintExpiry: (duration, callback) {
          expect(duration, const Duration(seconds: 2));
          final index = expiries.length;
          expiries.add(callback);
          return () => cancelled.add(index);
        },
      );
      final routes = <String>[];
      coordinator.attachRouteSink(routes.add);
      await coordinator.prepare();
      await coordinator.start();

      links.add(Uri.parse('pomodoist://focus'));
      await Future<void>.delayed(Duration.zero);
      expect(routes, ['/focus']);
      expect(expiries, hasLength(1));

      links.add(Uri.parse('pomodoist://login-callback'));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, [0]);
      expect(expiries, hasLength(2));

      expiries[0]();
      links.add(Uri.parse('pomodoist://login-callback'));
      await Future<void>.delayed(Duration.zero);
      expect(routes, ['/focus', '/login-callback?returnTo=%2Fsettings']);

      expiries[1]();
      links.add(Uri.parse('pomodoist://login-callback'));
      await Future<void>.delayed(Duration.zero);
      expect(routes, [
        '/focus',
        '/login-callback?returnTo=%2Fsettings',
        '/login-callback?returnTo=%2Fsettings',
      ]);
      expect(expiries, hasLength(3));

      await coordinator.dispose();
      expect(cancelled, containsAll(<int>[0, 2]));
      expect(cancelled, isNot(contains(1)));
      await links.close();
    },
  );

  test('sanitizes malformed and unsupported native links', () async {
    final links = StreamController<Uri>.broadcast();
    final coordinator = NativeLinkCoordinator(
      loadInitialLink: () async => null,
      linkStream: links.stream,
    );
    final routes = <String>[];
    final callbacks = <Uri>[];
    coordinator.attachRouteSink(routes.add);
    final subscription = coordinator.captchaCallbacks.listen(callbacks.add);
    await coordinator.prepare();
    await coordinator.start();

    for (final link in [
      'https://evil.test/focus',
      'pomodoist://focus?extra=x',
      'pomodoist://focus/path',
      'pomodoist://login-callback/path?returnTo=%2Ftoday',
      'pomodoist://captcha-callback?state=short&token=opaque-token',
    ]) {
      links.add(Uri.parse(link));
    }
    await Future<void>.delayed(Duration.zero);

    expect(routes, isEmpty);
    expect(callbacks, isEmpty);

    await subscription.cancel();
    await coordinator.dispose();
    await links.close();
  });
}
