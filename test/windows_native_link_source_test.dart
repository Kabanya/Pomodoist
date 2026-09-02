import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/windows_native_link_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts only valid native link method calls', () async {
    final source = WindowsNativeLinkSource();
    final links = <Uri>[];
    final subscription = source.links.listen(links.add);

    await source.handleMethodCall(
      const MethodCall(
        'link',
        'pomodoist://login-callback/?error_code=otp_expired',
      ),
    );
    await source.handleMethodCall(
      const MethodCall('other', 'pomodoist://focus'),
    );
    await source.handleMethodCall(const MethodCall('link', 'not a URI'));
    await source.handleMethodCall(const MethodCall('link', 42));

    expect(links, [
      Uri.parse('pomodoist://login-callback/?error_code=otp_expired'),
    ]);

    await subscription.cancel();
    await source.dispose();
  });

  test('finishes account callback work before emitting the link', () async {
    final releaseExchange = Completer<void>();
    final exchanged = <Uri>[];
    final source = WindowsNativeLinkSource(
      beforeEmit: (uri) async {
        exchanged.add(uri);
        await releaseExchange.future;
      },
    );
    final links = <Uri>[];
    final subscription = source.links.listen(links.add);
    final callback = Uri.parse('pomodoist://login-callback/?code=AUTH_CODE');

    final pending = source.handleMethodCall(
      MethodCall('link', callback.toString()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(exchanged, [callback]);
    expect(links, isEmpty);

    releaseExchange.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(links, [callback]);

    await subscription.cancel();
    await source.dispose();
  });

  test('identifies only exact Supabase auth callbacks', () {
    expect(
      isWindowsAccountAuthCallback(
        Uri.parse('pomodoist://login-callback/?code=AUTH_CODE'),
      ),
      isTrue,
    );
    expect(
      isWindowsAccountAuthCallback(
        Uri.parse('pomodoist://login-callback#error=access_denied'),
      ),
      isTrue,
    );
    expect(
      isWindowsAccountAuthCallback(Uri.parse('pomodoist://login-callback')),
      isFalse,
    );
    expect(
      isWindowsAccountAuthCallback(
        Uri.parse('pomodoist://login-callback/path?code=AUTH_CODE'),
      ),
      isFalse,
    );
    expect(
      isWindowsAccountAuthCallback(
        Uri.parse('https://evil.test/login-callback?code=AUTH_CODE'),
      ),
      isFalse,
    );
  });
}
