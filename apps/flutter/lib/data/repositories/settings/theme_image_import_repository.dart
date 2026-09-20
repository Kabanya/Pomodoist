import 'package:file_selector/file_selector.dart';

import 'package:pomodoist/domain/models/settings/theme_image.dart';

abstract interface class ThemeImageImportRepository {
  Future<PreparedThemeImage> prepare(XFile file);
}
