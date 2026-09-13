import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/updates/github_update_source.dart';
import 'package:pomodoist/features/updates/update_contracts.dart';
import 'package:pomodoist/features/updates/update_downloader_io.dart';
import 'package:pomodoist/features/updates/update_release.dart';

import 'desktop_update_release_test.dart' as fixtures;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async => respond(options);
  @override
  void close({bool force = false}) {}
}

Dio client(FutureOr<ResponseBody> Function(RequestOptions) respond) =>
    Dio()..httpClientAdapter = _Adapter(respond);
ResponseBody jsonResponse(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
UpdateOffer binaryOffer(List<int> bytes, {String? digest, int? size, UpdateAsset? checksum}) => UpdateOffer(
  tag: 'v2.0.0', version: UpdateVersion.parse('2.0.0'), notes: '', checksum: checksum,
  asset: UpdateAsset(name: 'Pomodoist-x86_64.AppImage', size: size ?? bytes.length,
    sha256: digest ?? sha256.convert(bytes).toString(),
    url: Uri.parse('https://github.com/Kabanya/Pomodoist/releases/download/v2.0.0/Pomodoist-x86_64.AppImage')),
);

void main() {
  test('release discovery reads subsequent pages and uses semantic precedence', () async {
    final pages = <int>[];
    final source = GitHubUpdateSource(dio: client((request) {
      final page = request.queryParameters['page'] as int;
      pages.add(page);
      expect(request.headers['Authorization'], isNull);
      return jsonResponse(page == 1
        ? List.generate(100, (_) => fixtures.releaseFixture('v1.2.0'))
        : [fixtures.releaseFixture('v9.0.0')]);
    }));
    addTearDown(source.dispose);
    final found = await source.findUpdate(current: UpdateVersion.parse('1.0.0'),
      target: fixtures.linuxTarget, channel: UpdateChannel.stable);
    expect(pages, [1, 2]);
    expect(found!.tag, 'v9.0.0');
  });

  test('GitHub rate limits produce a retryable error', () async {
    final source = GitHubUpdateSource(dio: client((_) => jsonResponse({}, 429)));
    addTearDown(source.dispose);
    await expectLater(source.findUpdate(current: UpdateVersion.parse('1.0.0'),
      target: fixtures.linuxTarget, channel: UpdateChannel.stable),
      throwsA(isA<UpdateFailure>().having((e) => e.message, 'message', contains('rate limit'))));
  });

  group('verified downloads', () {
    late Directory stage;
    setUp(() async { stage = await Directory.systemTemp.createTemp('pomodoist-download-test-'); });
    tearDown(() async { await stage.delete(recursive: true); });

    test('streams correct bytes and verifies before promoting the artifact', () async {
      final bytes = utf8.encode('verified release payload');
      final downloader = UpdateDownloader(dio: client((_) => ResponseBody.fromBytes(bytes, 200)));
      addTearDown(downloader.dispose);
      final destination = File('${stage.path}/release');
      final phases = <UpdatePhase>[];
      final hash = await downloader.download(binaryOffer(bytes), destination, (phase, _) => phases.add(phase));
      expect(await destination.readAsBytes(), bytes);
      expect(hash, sha256.convert(bytes).toString());
      expect(phases, containsAllInOrder([UpdatePhase.downloading, UpdatePhase.verifying]));
      expect(await File('${destination.path}.part').exists(), isFalse);
    });

    test('corrupt digest is rejected and no executable or partial file remains', () async {
      final bytes = utf8.encode('corrupted');
      final downloader = UpdateDownloader(dio: client((_) => ResponseBody.fromBytes(bytes, 200)));
      addTearDown(downloader.dispose);
      final destination = File('${stage.path}/release');
      await expectLater(downloader.download(binaryOffer(bytes, digest: 'a' * 64), destination, (_, _) {}),
        throwsA(isA<UpdateFailure>()));
      expect(await destination.exists(), isFalse);
      expect(await File('${destination.path}.part').exists(), isFalse);
    });

    for (final delta in [-1, 1]) {
      test('incorrect byte count ($delta) leaves no installable artifact', () async {
        final bytes = utf8.encode('payload');
        final downloader = UpdateDownloader(dio: client((_) => ResponseBody.fromBytes(bytes, 200)));
        addTearDown(downloader.dispose);
        final destination = File('${stage.path}/release');
        await expectLater(downloader.download(binaryOffer(bytes, size: bytes.length + delta), destination, (_, _) {}),
          throwsA(isA<UpdateFailure>()));
        expect(await destination.exists(), isFalse);
        expect(await File('${destination.path}.part').exists(), isFalse);
      });
    }

    test('interrupted stream cleans up its partial file', () async {
      final bytes = utf8.encode('payload');
      Stream<Uint8List> interrupted() async* {
        yield Uint8List.fromList(bytes.take(2).toList());
        throw const SocketException('interrupted');
      }
      final downloader = UpdateDownloader(dio: client((_) => ResponseBody(interrupted(), 200)));
      addTearDown(downloader.dispose);
      final destination = File('${stage.path}/release');
      await expectLater(downloader.download(binaryOffer(bytes), destination, (_, _) {}), throwsA(isA<Exception>()));
      expect(await destination.exists(), isFalse);
      expect(await File('${destination.path}.part').exists(), isFalse);
    });

    for (final redirect in ['http://github.com/file', 'https://evil.example/release.exe']) {
      test('rejects untrusted redirect $redirect', () async {
        final downloader = UpdateDownloader(dio: client((_) => ResponseBody.fromBytes([], 302,
          headers: {'location': [redirect]})));
        addTearDown(downloader.dispose);
        await expectLater(downloader.download(binaryOffer([1]), File('${stage.path}/release'), (_, _) {}),
          throwsA(isA<UpdateFailure>()));
      });
    }

    test('mismatched sidecar and API digest fail before fetching executable', () async {
      final checksum = utf8.encode('${'b' * 64} *Pomodoist-x86_64.AppImage\n');
      var requests = 0;
      final downloader = UpdateDownloader(dio: client((_) { requests++; return ResponseBody.fromBytes(checksum, 200); }));
      addTearDown(downloader.dispose);
      final offer = binaryOffer([1], digest: 'a' * 64, checksum: UpdateAsset(
        name: 'Pomodoist-x86_64.AppImage.sha256', size: checksum.length,
        url: Uri.parse('https://github.com/Kabanya/Pomodoist/releases/download/v2.0.0/Pomodoist-x86_64.AppImage.sha256')));
      await expectLater(downloader.download(offer, File('${stage.path}/release'), (_, _) {}), throwsA(isA<UpdateFailure>()));
      expect(requests, 1);
    });
  });
}
