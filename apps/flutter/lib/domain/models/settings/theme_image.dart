import 'dart:typed_data';

const themeImageMaxBytes = 50 * 1024 * 1024;

typedef PreparedThemeImage = ({String id, Uint8List bytes});

class ThemeImageTooLargeException implements Exception {
  const ThemeImageTooLargeException();

  @override
  String toString() => 'Theme image exceeds the 50 MB limit';
}
