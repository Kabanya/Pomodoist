import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pomodoist/app/theme/theme_image_store_io.dart';

void main() {
  late Directory support;
  late FileThemeImageStore store;
  final first = 'a' * 64;
  final second = 'b' * 64;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('theme_image_store_test_');
    store = FileThemeImageStore(directory: () async => support);
  });
  tearDown(() => support.delete(recursive: true));

  test(
    'writes survive reopening and retain removes only unreferenced images',
    () async {
      expect(await store.read(first), isNull);
      await store.write(first, Uint8List.fromList([1, 2, 3]));
      await store.write(second, Uint8List.fromList([4, 5, 6]));
      final reopened = FileThemeImageStore(directory: () async => support);
      expect(await reopened.read(first), [1, 2, 3]);
      final storage = Directory(p.join(support.path, 'pomodoist_theme_images'));
      final unrelated = File(p.join(storage.path, 'notes.txt'));
      await unrelated.writeAsString('keep');
      final outside = File(p.join(support.path, '$second.png'));
      await outside.writeAsString('keep outside');
      final nested = Directory(p.join(storage.path, '$second.png'));
      await File(p.join(storage.path, '$second.png')).delete();
      await nested.create();
      await File(p.join(nested.path, 'keep.txt')).writeAsString('keep nested');
      await reopened.retain({first});
      expect(await reopened.read(first), [1, 2, 3]);
      expect(await unrelated.readAsString(), 'keep');
      expect(await outside.readAsString(), 'keep outside');
      expect(await nested.exists(), isTrue);
      await nested.delete(recursive: true);
      await reopened.write(second, Uint8List.fromList([7]));
      await reopened.retain({first});
      expect(await reopened.read(second), isNull);
      await reopened.retain({});
      expect(await reopened.read(first), isNull);
    },
  );

  test(
    'concurrent writes publish complete files and remove temporary data',
    () async {
      await Future.wait([
        store.write(first, Uint8List.fromList([1, 2, 3])),
        store.write(second, Uint8List.fromList([4, 5, 6])),
      ]);
      await store.write(first, Uint8List.fromList([7, 8]));
      expect(await store.read(first), [7, 8]);
      expect(await store.read(second), [4, 5, 6]);
      expect(
        (await support.list(recursive: true).toList()).whereType<File>().map(
          (file) => p.basename(file.path),
        ),
        unorderedEquals(['$first.png', '$second.png']),
      );
    },
  );

  test(
    'malformed IDs fail before reading, writing or deleting any storage',
    () async {
      await store.write(first, Uint8List.fromList([1]));
      for (final id in [
        '',
        '../outside',
        '/absolute',
        'A' * 64,
        'a' * 63,
        '$first\n',
      ]) {
        await expectLater(store.read(id), throwsFormatException);
        await expectLater(store.write(id, Uint8List(1)), throwsFormatException);
        await expectLater(store.retain({id}), throwsFormatException);
        expect(await store.read(first), [1]);
      }
    },
  );
}
