import 'dart:typed_data';

abstract class ThemeImageStore {
  Future<T> protect<T>(Future<T> Function() action) => action();

  Future<Uint8List?> read(String id);
  Future<void> write(String id, Uint8List bytes);
  Future<void> retain(Set<String> ids);
}

final _imageIdPattern = RegExp(r'^[a-f0-9]{64}$');

bool isThemeImageId(String id) =>
    id.length == 64 && _imageIdPattern.hasMatch(id);

void validateThemeImageId(String id) {
  if (!isThemeImageId(id))
    throw const FormatException('Invalid theme image ID');
}
