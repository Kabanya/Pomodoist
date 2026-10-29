import 'dart:typed_data';

import 'remote_theme_image_stub.dart'
    if (dart.library.io) 'remote_theme_image_io.dart'
    if (dart.library.js_interop) 'remote_theme_image_web.dart'
    as platform;

import 'remote_theme_image_policy.dart';
export 'remote_theme_image_policy.dart';

Future<Uint8List> downloadRemoteThemeImage(Uri uri) {
  validateRemoteThemeImageUrl(uri);
  return platform.downloadRemoteThemeImage(uri);
}
