import 'dart:typed_data';

import 'package:pomodoist/domain/models/settings/theme_image.dart';

const remoteThemeImageTimeout = Duration(seconds: 30);

/// Remote imports never attach account credentials or accept local destinations.
void validateRemoteThemeImageUrl(Uri uri) {
  final host = uri.host.toLowerCase();
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      host.isEmpty ||
      uri.port != 443 ||
      uri.fragment.isNotEmpty ||
      host.contains(':') ||
      !host.contains('.') ||
      RegExp(r'^[0-9.]+$').hasMatch(host) ||
      host.startsWith('0x') ||
      host.endsWith('.') ||
      const [
        'localhost',
        'local',
        'internal',
        'lan',
        'home',
        'test',
        'invalid',
        'example',
        'onion',
      ].any((suffix) => host == suffix || host.endsWith('.$suffix'))) {
    throw const FormatException(
      'A public HTTPS image URL without credentials is required.',
    );
  }
}

Future<Uint8List> readRemoteThemeImage(
  Stream<List<int>> stream, {
  int maxBytes = themeImageMaxBytes,
}) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (chunk.length > maxBytes - result.length) {
      throw const ThemeImageTooLargeException();
    }
    result.add(chunk);
  }
  if (result.isEmpty) {
    throw const FormatException('The image response is empty.');
  }
  return result.takeBytes();
}
