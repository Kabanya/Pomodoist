import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<Object> pomodoistDatabaseDirectory() async {
  if (defaultTargetPlatform != TargetPlatform.linux) {
    return getApplicationDocumentsDirectory();
  }

  final support = await linuxApplicationDataDirectory();
  try {
    final documents = await getApplicationDocumentsDirectory();
    return await selectLinuxDatabaseDirectory(
      documents: documents,
      support: support,
    );
  } on MissingPlatformDirectoryException {
    return support;
  }
}

@visibleForTesting
Future<Directory> linuxApplicationDataDirectory({
  Map<String, String>? environment,
}) async {
  final resolvedEnvironment = environment ?? Platform.environment;
  final configuredDataHome = resolvedEnvironment['XDG_DATA_HOME'];
  final home = resolvedEnvironment['HOME'];
  final dataHome = configuredDataHome != null && configuredDataHome.isNotEmpty
      ? configuredDataHome
      : home != null && home.isNotEmpty
      ? path.join(home, '.local', 'share')
      : throw StateError('HOME is required to locate Pomodoist data.');
  final directory = Directory(path.join(dataHome, 'com.finchforge.pomodoist'));
  await directory.create(recursive: true);
  return directory;
}

@visibleForTesting
Future<Directory> selectLinuxDatabaseDirectory({
  required Directory documents,
  required Directory support,
}) async {
  final legacyDatabase = File(path.join(documents.path, 'pomodoist.sqlite'));
  return await legacyDatabase.exists() ? documents : support;
}
