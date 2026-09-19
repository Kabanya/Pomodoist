import 'dart:typed_data';

import 'package:pomodoist/data/repositories/settings/theme_image_repository.dart';
import 'package:pomodoist/data/services/local/theme_image_store_contract.dart';

final class StoredThemeImageRepository extends ThemeImageRepository {
  StoredThemeImageRepository(this._store);

  final ThemeImageStore _store;

  @override
  Future<T> protect<T>(Future<T> Function() action) => _store.protect(action);

  @override
  Future<Uint8List?> read(String id) => _store.read(id);

  @override
  Future<void> write(String id, Uint8List bytes) => _store.write(id, bytes);

  @override
  Future<void> retain(Set<String> ids) => _store.retain(ids);
}
