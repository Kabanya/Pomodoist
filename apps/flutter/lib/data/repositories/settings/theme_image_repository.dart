import 'dart:typed_data';

export 'package:pomodoist/utils/theme_image_id.dart';

abstract class ThemeImageRepository {
  Future<T> protect<T>(Future<T> Function() action) => action();

  Future<Uint8List?> read(String id);
  Future<void> write(String id, Uint8List bytes);
  Future<void> retain(Set<String> ids);
}
