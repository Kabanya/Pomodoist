final _themeImageIdPattern = RegExp(r'^[a-f0-9]{64}$');

bool isThemeImageId(String id) =>
    id.length == 64 && _themeImageIdPattern.hasMatch(id);

void validateThemeImageId(String id) {
  if (!isThemeImageId(id)) {
    throw const FormatException('Invalid theme image ID');
  }
}
