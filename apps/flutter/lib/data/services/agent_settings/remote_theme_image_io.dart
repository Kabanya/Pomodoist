import 'dart:io';
import 'dart:typed_data';
import 'package:pomodoist/domain/models/settings/theme_image.dart';
import 'remote_theme_image_policy.dart'
    show
        validateRemoteThemeImageUrl,
        readRemoteThemeImage,
        remoteThemeImageTimeout;

bool isPublicImageAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 16) {
    // Only global unicast; exclude documentation and transition mechanisms.
    return b[0] & 0xe0 == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x01 && (b[2] == 0 || b[2] == 0x0d)) &&
        !(b[0] == 0x20 && b[1] == 0x02);
  }
  return b[0] != 0 &&
      b[0] != 10 &&
      b[0] != 127 &&
      b[0] < 224 &&
      !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
      !(b[0] == 169 && b[1] == 254) &&
      !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
      !(b[0] == 192 &&
          (b[1] == 168 || b[1] == 0 || (b[1] == 88 && b[2] == 99))) &&
      !(b[0] == 198 &&
          (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) &&
      !(b[0] == 203 && b[1] == 0 && b[2] == 113);
}

Future<Uint8List> downloadRemoteThemeImage(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (target, proxyHost, proxyPort) async {
    final addresses = await InternetAddress.lookup(target.host);
    if (addresses.isEmpty || !addresses.every(isPublicImageAddress)) {
      throw const FormatException(
        'The image host must resolve to public addresses.',
      );
    }
    // Connect to the validated address, avoiding a second DNS lookup/rebinding.
    return Socket.startConnect(addresses.first, target.port);
  };
  Future<Uint8List> download() async {
    var current = uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      validateRemoteThemeImageUrl(current);
      final request = await client.getUrl(current);
      request.followRedirects = false;
      final response = await request.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const FormatException('Invalid image redirect.');
        }
        current = current.resolve(location);
        // Do not consume an unbounded redirect body.
        await response.listen((_) {}).cancel();
        continue;
      }
      if (response.statusCode != 200 ||
          response.headers.contentType?.primaryType != 'image') {
        throw const FormatException('The URL must return an image.');
      }
      if (response.contentLength > themeImageMaxBytes) {
        throw const ThemeImageTooLargeException();
      }
      return readRemoteThemeImage(response);
    }
    throw const FormatException('Too many image redirects.');
  }

  try {
    return await download().timeout(remoteThemeImageTimeout);
  } finally {
    client.close(force: true);
  }
}
