import 'dart:async';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/agent_settings/remote_theme_image_io.dart';
import 'package:pomodoist/domain/models/settings/theme_image.dart';

class _Headers implements HttpHeaders {
  _Headers(this.location);
  final String? location;
  @override
  ContentType get contentType => ContentType('image', 'png');
  @override
  String? value(String name) => location;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response({this.statusCode = 200, this.location, this.contentLength = 3});
  @override
  final int statusCode, contentLength;
  final String? location;
  @override
  HttpHeaders get headers => _Headers(location);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(<int>[1, 2, 3]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  Future<HttpClientResponse> close() => response;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _Client implements HttpClient {
  _Client(this.responses);
  final List<Future<HttpClientResponse>> responses;
  final urls = <Uri>[];
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    urls.add(uri);
    return _Request(responses[urls.length - 1]);
  }

  @override
  void close({bool force = false}) => closed = force;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

void main() {
  final source = Uri.parse('https://images.unsplash.com/photo');
  test('imports a response after a public HTTPS redirect', () async {
    final client = _Client([
      Future.value(_Response(statusCode: 302, location: '/next')),
      Future.value(_Response()),
    ]);
    final bytes = await HttpOverrides.runZoned(
      () => downloadRemoteThemeImage(source),
      createHttpClient: (_) => client,
    );
    expect(bytes, [1, 2, 3]);
    expect(client.urls, [source, source.resolve('/next')]);
    expect(client.closed, true);
  });
  test('rejects private redirect before requesting its destination', () async {
    final client = _Client([
      Future.value(_Response(statusCode: 302, location: 'https://127.0.0.1/a')),
    ]);
    await expectLater(
      HttpOverrides.runZoned(
        () => downloadRemoteThemeImage(source),
        createHttpClient: (_) => client,
      ),
      throwsFormatException,
    );
    expect(client.urls, [source]);
    expect(client.closed, true);
  });
  test('rejects excessive declared content size', () async {
    final client = _Client([
      Future.value(_Response(contentLength: themeImageMaxBytes + 1)),
    ]);
    await expectLater(
      HttpOverrides.runZoned(
        () => downloadRemoteThemeImage(source),
        createHttpClient: (_) => client,
      ),
      throwsA(isA<ThemeImageTooLargeException>()),
    );
    expect(client.closed, true);
  });
  test('total timeout closes an unresponsive HTTP client', () {
    fakeAsync((clock) {
      final client = _Client([Completer<HttpClientResponse>().future]);
      Object? failure;
      HttpOverrides.runZoned(
        () => downloadRemoteThemeImage(source),
        createHttpClient: (_) => client,
      ).then<void>(
        (_) {},
        onError: (Object error) {
          failure = error;
        },
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 31));
      expect(failure, isA<TimeoutException>());
      expect(client.closed, true);
    });
  });
  test(
    'rejects private, mapped, reserved and transition IPs after DNS resolution',
    () {
      for (final value in [
        '0.0.0.0',
        '10.0.0.1',
        '127.0.0.1',
        '100.64.0.1',
        '169.254.169.254',
        '172.16.0.1',
        '192.168.1.1',
        '192.0.2.1',
        '198.18.0.1',
        '198.51.100.1',
        '203.0.113.1',
        '224.0.0.1',
        '255.255.255.255',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        'fe80::1',
        '2001:db8::1',
        '2002:7f00:1::',
      ]) {
        expect(
          isPublicImageAddress(InternetAddress(value)),
          false,
          reason: value,
        );
      }
      for (final value in ['8.8.8.8', '1.1.1.1', '2606:4700:4700::1111']) {
        expect(
          isPublicImageAddress(InternetAddress(value)),
          true,
          reason: value,
        );
      }
    },
  );
}
