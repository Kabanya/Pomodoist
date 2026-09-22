import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pomodoist/domain/models/app_flavor.dart';

/// The application-support directory the running build flavor owns.
///
/// Windows builds that directory from the executable name and Linux builds it
/// from the desktop application id, and both stay `pomodoist` for every flavor,
/// so the development, staging and production builds would otherwise read and
/// write one shared directory. Non-production flavors therefore get a
/// subdirectory named after their application id. macOS, iOS and Android are
/// returned untouched: their application-support directory already contains the
/// bundle identifier, which differs per flavor.
///
/// Production is returned unchanged in every case, so its on-disk location
/// never moves.
///
/// Callers create the directory they append to the result; nothing is written
/// here. The optional parameters exist for tests: they let a Windows or Linux
/// host be simulated from macOS and keep `path_provider` out of the test.
Future<Directory> flavorApplicationSupportDirectory({
  bool? isWindows,
  bool? isLinux,
  Future<Directory> Function()? loader,
}) async {
  final directory = await (loader ?? getApplicationSupportDirectory)();
  final derivedFromBinaryName =
      (isWindows ?? Platform.isWindows) || (isLinux ?? Platform.isLinux);
  if (!derivedFromBinaryName || appFlavor.isProduction) return directory;
  return Directory(p.join(directory.path, appFlavor.applicationId));
}
