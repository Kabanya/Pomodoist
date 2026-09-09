import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'theme_image_store_contract.dart';

ThemeImageStore createThemeImageStore() => FileThemeImageStore();

class FileThemeImageStore extends ThemeImageStore {
  FileThemeImageStore({Future<Directory> Function()? directory})
    : _directoryLoader = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryLoader;
  Directory? _directory;

  Future<Directory> _storage() async {
    if (_directory != null) return _directory!;
    final parent = await _directoryLoader();
    return _directory = await Directory(
      p.join(parent.path, 'pomodoist_theme_images'),
    ).create(recursive: true);
  }

  @override
  Future<Uint8List?> read(String id) async {
    validateThemeImageId(id);
    final file = File(p.join((await _storage()).path, '$id.png'));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    validateThemeImageId(id);
    final directory = await _storage();
    final temporary = await directory.createTemp('.write_');
    try {
      final file = File(p.join(temporary.path, '$id.png'));
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(p.join(directory.path, '$id.png'));
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  @override
  Future<void> retain(Set<String> ids) async {
    ids.forEach(validateThemeImageId);
    await for (final entry in (await _storage()).list(followLinks: false)) {
      if (entry is! File || p.extension(entry.path) != '.png') continue;
      final id = p.basenameWithoutExtension(entry.path);
      if (isThemeImageId(id) && !ids.contains(id)) await entry.delete();
    }
  }
}
