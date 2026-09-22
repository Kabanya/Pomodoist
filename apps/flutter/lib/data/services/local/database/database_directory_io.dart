import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:pomodoist/domain/models/app_flavor.dart';

Future<Object> pomodoistDatabaseDirectory() async {
  if (defaultTargetPlatform != TargetPlatform.linux) {
    return getApplicationDocumentsDirectory();
  }
  return linuxApplicationDataDirectory();
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
  final directory = Directory(path.join(dataHome, appFlavor.applicationId));
  await directory.create(recursive: true);
  return directory;
}
