import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/database/database_directory_io.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

void main() {
  tearDown(() => setAppFlavor(buildTimeAppFlavor ?? AppFlavor.production));

  test('database configuration uses the platform-aware resolver', () async {
    final source = await File(
      'lib/data/services/local/database/app_database.dart',
    ).readAsString();

    expect(source, contains('database/database_directory.dart'));
    expect(source, contains('databaseDirectory: pomodoistDatabaseDirectory'));
    expect(source, contains('name: pomodoistDatabaseFileName'));
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

  test('Linux data directories are distinct per flavor', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-db-flavor-');
    addTearDown(() => root.delete(recursive: true));

    final directories = <String>{};
    for (final flavor in AppFlavor.values) {
      setAppFlavor(flavor);
      final directory = await linuxApplicationDataDirectory(
        environment: {'XDG_DATA_HOME': root.path},
      );
      expect(directory.path, '${root.path}/${flavor.applicationId}');
      directories.add(directory.path);
    }
    expect(directories, hasLength(AppFlavor.values.length));
  });

  test('the database file name keeps production and scopes the rest', () {
    setAppFlavor(AppFlavor.production);
    expect(pomodoistDatabaseFileName, 'pomodoist');

    for (final flavor in AppFlavor.values.where((f) => !f.isProduction)) {
      setAppFlavor(flavor);
      expect(pomodoistDatabaseFileName, 'pomodoist-${flavor.name}');
    }
  });
}
