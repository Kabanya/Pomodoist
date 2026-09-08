import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'update_contracts.dart';
import 'update_release.dart';

class UpdateDownloader {
  UpdateDownloader({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'User-Agent': 'Pomodoist-Desktop-Updater'},
  ));
  final Dio _dio;
  final _cancel = CancelToken();

  Future<ResponseBody> _open(UpdateAsset asset, String tag) async {
    if (!isTrustedUpdateUrl(asset.url, tag, asset.name)) {
      throw const UpdateFailure('The update URL is not a trusted GitHub release asset.');
    }
    var url = asset.url;
    for (var redirects = 0; redirects < 6; redirects++) {
      final response = await _dio.get<ResponseBody>(url.toString(),
        cancelToken: _cancel,
        options: Options(responseType: ResponseType.stream, followRedirects: false,
          validateStatus: (status) => status == 200 ||
              const [301, 302, 303, 307, 308].contains(status)),
      );
      final body = response.data;
      if (body == null) throw const UpdateFailure('Empty update download response.');
      if (response.statusCode == 200) return body;
      await body.stream.listen(null).cancel();
      final location = response.headers.value('location');
      if (location == null) throw const UpdateFailure('Missing update redirect location.');
      url = url.resolve(location);
      const cdnHosts = {'release-assets.githubusercontent.com',
        'objects.githubusercontent.com', 'github-releases.githubusercontent.com'};
      if (url.scheme != 'https' || url.port != 443 || url.userInfo.isNotEmpty ||
          url.hasFragment || !(cdnHosts.contains(url.host) ||
            isTrustedUpdateUrl(url, tag, asset.name))) {
        throw const UpdateFailure('Unsafe update download redirect.');
      }
    }
    throw const UpdateFailure('Too many update download redirects.');
  }

  Future<String> _checksum(UpdateOffer offer) async {
    var expected = offer.asset.sha256;
    final sidecar = offer.checksum;
    if (sidecar != null) {
      final response = await _open(sidecar, offer.tag);
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (bytes.length > 4096) throw const UpdateFailure('Checksum file is too large.');
      }
      if (bytes.length != sidecar.size) throw const UpdateFailure('Incomplete checksum download.');
      final checksum = parseUpdateChecksum(utf8.decode(bytes), offer.asset.name);
      if (expected != null && expected != checksum) {
        throw const UpdateFailure('The release checksum and GitHub digest disagree.');
      }
      expected = checksum;
    }
    if (expected == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw const UpdateFailure('The release does not provide a valid SHA-256 checksum.');
    }
    return expected;
  }

  /// Streams to disk, checks the exact byte count, then hashes from disk. Only a
  /// verified file is promoted from .part to the executable installer filename.
  Future<String> download(UpdateOffer offer, File destination, UpdateProgress progress) async {
    final partial = File('${destination.path}.part');
    final deadline = Timer(const Duration(minutes: 20), () => _cancel.cancel('timeout'));
    try {
      if (offer.asset.size <= 0 || offer.asset.size > 512 * 1024 * 1024) {
        throw const UpdateFailure('Unsupported update artifact size.');
      }
      final expected = await _checksum(offer);
      final response = await _open(offer.asset, offer.tag);
      final sink = partial.openWrite();
      var received = 0;
      final throttle = Stopwatch()..start();
      try {
        await sink.addStream(response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
          received += chunk.length;
          if (received > offer.asset.size) {
            throw const UpdateFailure('The update is larger than its declared size.');
          }
          if (throttle.elapsedMilliseconds >= 100 || received == offer.asset.size) {
            progress(UpdatePhase.downloading, received / offer.asset.size);
            throttle.reset();
          }
          return chunk;
        }));
        await sink.flush();
      } catch (_) {
        // addStream can close its file sink on a source error. A second close
        // must not replace the original integrity/network failure.
        try { await sink.close(); } catch (_) { /* Preserve the source error. */ }
        rethrow;
      }
      await sink.close();
      if (received != offer.asset.size) throw const UpdateFailure('The update download was interrupted.');
      progress(UpdatePhase.verifying, null);
      final actual = (await sha256.bind(partial.openRead()).first).toString();
      if (actual != expected) throw const UpdateFailure('Update integrity check failed. Nothing was installed.');
      await partial.rename(destination.path);
      return expected;
    } on DioException {
      throw const UpdateFailure('Update download failed. Check your connection and retry.');
    } finally {
      deadline.cancel();
      if (await partial.exists()) await partial.delete();
    }
  }

  void dispose() {
    _cancel.cancel('disposed');
    _dio.close(force: true);
  }
}
