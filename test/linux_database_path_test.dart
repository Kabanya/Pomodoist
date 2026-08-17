import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/database_directory_io.dart';

void main() {
  test('database configuration uses the platform-aware resolver', () async {
    final source = await File('lib/core/db/app_database.dart').readAsString();

    expect(source, contains("import 'database_directory.dart';"));
    expect(source, contains('databaseDirectory: pomodoistDatabaseDirectory'));
  });

  test('new Linux profile uses the XDG application data directory', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-db-path-');
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory('${root.path}/Documents');
    final support = Directory('${root.path}/xdg-data/pomodoist');

    expect(
      await selectLinuxDatabaseDirectory(
        documents: documents,
        support: support,
      ),
      support,
    );
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

  test('existing Linux database remains visible at its legacy path', () async {
    final root = await Directory.systemTemp.createTemp('pomodoist-db-path-');
    addTearDown(() => root.delete(recursive: true));
    final documents = await Directory('${root.path}/Documents').create();
    final support = Directory('${root.path}/xdg-data/pomodoist');
    await File('${documents.path}/pomodoist.sqlite').writeAsBytes([1]);

    expect(
      await selectLinuxDatabaseDirectory(
        documents: documents,
        support: support,
      ),
      documents,
    );
  });
}
