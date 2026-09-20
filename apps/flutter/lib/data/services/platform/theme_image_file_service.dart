import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pomodoist/domain/models/settings/theme_image.dart';

/// Reads and validates a user-selected file before delegating image decoding.
final class ThemeImageFileService {
  const ThemeImageFileService(this._prepare);

  final Future<Uint8List> Function(Uint8List bytes) _prepare;

  Future<PreparedThemeImage> prepare(XFile file) async {
    if (await file.length() > themeImageMaxBytes) {
      throw const ThemeImageTooLargeException();
    }
    final bytes = await file.readAsBytes();
    final prepared = await _prepare(bytes);
    return (id: sha256.convert(prepared).toString(), bytes: prepared);
  }
}
