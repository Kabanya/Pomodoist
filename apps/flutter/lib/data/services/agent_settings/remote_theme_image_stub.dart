import 'dart:typed_data';

Future<Uint8List> downloadRemoteThemeImage(Uri uri) =>
    Future.error(UnsupportedError('Remote image imports are unavailable.'));
