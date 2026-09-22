import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pomodoist/data/services/local/flavor_application_support_directory_io.dart';
import 'package:pomodoist/data/services/local/theme_image_store_io.dart';
import 'package:pomodoist/data/services/voice/voice_recording_store_io.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

const supportPath = '/support';
const _themeImageId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<Directory> support() async => Directory(supportPath);

/// The path a build of [flavor] must resolve to on [platform].
String expectedPath(
  AppFlavor flavor, {
  required bool isWindows,
  required bool isLinux,
}) {
  final derivedFromBinaryName = isWindows || isLinux;
  if (!derivedFromBinaryName || flavor.isProduction) return supportPath;
  return p.join(supportPath, flavor.applicationId);
}

void main() {
  tearDown(() => setAppFlavor(buildTimeAppFlavor ?? AppFlavor.production));

  test('production keeps exactly the path path_provider returns', () async {
    setAppFlavor(AppFlavor.production);
    for (final platform in const [
      (name: 'windows', isWindows: true, isLinux: false),
      (name: 'linux', isWindows: false, isLinux: true),
      (name: 'macos', isWindows: false, isLinux: false),
    ]) {
      final directory = await flavorApplicationSupportDirectory(
        isWindows: platform.isWindows,
        isLinux: platform.isLinux,
        loader: support,
      );
      expect(directory.path, (await support()).path, reason: platform.name);
      expect(
        directory.path,
        expectedPath(
          AppFlavor.production,
          isWindows: platform.isWindows,
          isLinux: platform.isLinux,
        ),
        reason: platform.name,
      );
    }
  });

  test(
    'development and staging get their own id on Windows and Linux',
    () async {
      for (final platform in const [
        (name: 'windows', isWindows: true, isLinux: false),
        (name: 'linux', isWindows: false, isLinux: true),
      ]) {
        final paths = <AppFlavor, String>{};
        for (final flavor in AppFlavor.values) {
          setAppFlavor(flavor);
          final directory = await flavorApplicationSupportDirectory(
            isWindows: platform.isWindows,
            isLinux: platform.isLinux,
            loader: support,
          );
          expect(
            directory.path,
            expectedPath(
              flavor,
              isWindows: platform.isWindows,
              isLinux: platform.isLinux,
            ),
            reason: '${flavor.name} on ${platform.name}',
          );
          paths[flavor] = directory.path;
        }
        expect(paths.values.toSet(), hasLength(AppFlavor.values.length));
        expect(
          paths[AppFlavor.development],
          isNot(paths[AppFlavor.production]),
        );
        expect(paths[AppFlavor.staging], isNot(paths[AppFlavor.production]));
        expect(paths[AppFlavor.development], isNot(paths[AppFlavor.staging]));
      }
    },
  );

  test('macOS, iOS and Android are untouched for every flavor', () async {
    final paths = <String>{};
    for (final flavor in AppFlavor.values) {
      setAppFlavor(flavor);
      final directory = await flavorApplicationSupportDirectory(
        isWindows: false,
        isLinux: false,
        loader: support,
      );
      expect(directory.path, (await support()).path, reason: flavor.name);
      paths.add(directory.path);
    }
    expect(paths, hasLength(1));
  });

  test('the platform decision comes from dart:io', () async {
    final derivedFromBinaryName = Platform.isWindows || Platform.isLinux;
    for (final flavor in AppFlavor.values) {
      setAppFlavor(flavor);
      final directory = await flavorApplicationSupportDirectory(
        loader: support,
      );
      expect(
        directory.path,
        derivedFromBinaryName && !flavor.isProduction
            ? p.join(supportPath, flavor.applicationId)
            : supportPath,
        reason: flavor.name,
      );
    }
  });

  test(
    'both stores resolve their default directory through the helper',
    () async {
      for (final path in const [
        'lib/data/services/local/theme_image_store_io.dart',
        'lib/data/services/voice/voice_recording_store_io.dart',
      ]) {
        final source = await File(path).readAsString();
        expect(
          source,
          contains('directory ?? flavorApplicationSupportDirectory'),
          reason: path,
        );
        expect(
          source,
          contains('flavor_application_support_directory_io.dart'),
          reason: path,
        );
        expect(
          source,
          isNot(contains('getApplicationSupportDirectory')),
          reason: path,
        );
      }
    },
  );

  test(
    'Windows installs of different flavors never share a store directory',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pomodoist-flavor-support-',
      );
      addTearDown(() => root.delete(recursive: true));

      final voiceDirectories = <String>{};
      for (final flavor in AppFlavor.values) {
        Future<Directory> flavorSupport() async {
          setAppFlavor(flavor);
          return flavorApplicationSupportDirectory(
            isWindows: true,
            loader: () async => root,
          );
        }

        final parent = flavor.isProduction
            ? root.path
            : p.join(root.path, flavor.applicationId);

        await FileThemeImageStore(
          directory: flavorSupport,
        ).write(_themeImageId, Uint8List.fromList([1, 2, 3]));
        expect(
          await File(
            p.join(parent, 'pomodoist_theme_images', '$_themeImageId.png'),
          ).exists(),
          isTrue,
          reason: flavor.name,
        );

        final voiceDirectory = Directory(
          p.dirname(
            await FileVoiceRecordingStore(
              directory: flavorSupport,
            ).createPath(),
          ),
        );
        expect(
          voiceDirectory.path,
          p.join(parent, 'pomodoist_voice_pending'),
          reason: flavor.name,
        );
        expect(await voiceDirectory.exists(), isTrue, reason: flavor.name);
        voiceDirectories.add(voiceDirectory.path);
      }
      expect(voiceDirectories, hasLength(AppFlavor.values.length));
    },
  );
}
