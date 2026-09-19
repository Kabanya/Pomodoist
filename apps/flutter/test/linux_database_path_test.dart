import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/database_directory_io.dart';

void main() {
  test('database configuration uses the platform-aware resolver', () async {
    final source = await File(
      'lib/data/services/local/database/app_database.dart',
    ).readAsString();

    expect(source, contains('database/database_directory.dart'));
    expect(source, contains('databaseDirectory: pomodoistDatabaseDirectory'));
  });

  test('Linux writable data never overlaps the installed bundle', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-db-path-');
    addTearDown(() => root.delete(recursive: true));

    final directory = await linuxApplicationDataDirectory(
      environment: {'XDG_DATA_HOME': root.path},
    );

    expect(directory.path, '${root.path}/com.finchforge.pomodoist');
    expect(directory.path, isNot('${root.path}/pomodoist'));
    expect(await directory.exists(), isTrue);
  });
}
