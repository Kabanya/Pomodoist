import 'package:file_selector/file_selector.dart';

import 'package:pomodoist/data/repositories/settings/theme_image_import_repository.dart';
import 'package:pomodoist/data/services/platform/theme_image_file_service.dart';
import 'package:pomodoist/domain/models/settings/theme_image.dart';

final class FileThemeImageImportRepository
    implements ThemeImageImportRepository {
  const FileThemeImageImportRepository(this._files);

  final ThemeImageFileService _files;

  @override
  Future<PreparedThemeImage> prepare(XFile file) => _files.prepare(file);
}
