import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platform mode targets invoke their matching build modes', () {
    const expectedCommands = <String, String>{
      'android': 'flutter-under-test" build apk --debug',
      'web-debug': 'flutter-under-test" build web --debug',
      'web-profile': 'flutter-under-test" build web --profile',
      'web-release': 'flutter-under-test" build web --release',
      'linux-debug': 'flutter-under-test" build linux --debug',
      'linux-profile': 'flutter-under-test" build linux --profile',
      'linux-release': 'flutter-under-test" build linux --release',
      'windows-debug':
          'powershell.exe -NoProfile -ExecutionPolicy Bypass '
          '-File ./tool/windows/build.ps1 -Configuration Debug',
      'windows-profile':
          'powershell.exe -NoProfile -ExecutionPolicy Bypass '
          '-File ./tool/windows/build.ps1 -Configuration Profile',
      'windows-release':
          'powershell.exe -NoProfile -ExecutionPolicy Bypass '
          '-File ./tool/windows/build.ps1 -Configuration Release',
      'macos-debug': 'flutter-under-test" build macos --debug',
      'macos-profile': 'flutter-under-test" build macos --profile',
      'macos-release': 'flutter-under-test" build macos --release',
    };

    for (final entry in expectedCommands.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'DART=dart-under-test',
        'FLUTTER=flutter-under-test',
        'LOCAL_CONFIG=local.env',
        'ANDROID_CONFIG=android.env',
        'LINUX_CONFIG=pubspec.yaml',
        'WINDOWS_CONFIG=pubspec.yaml',
        'TESTFLIGHT_CONFIG=pubspec.yaml',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout.toString(),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test('platform targets consume their generated environment files', () {
    final expectedConfigs = <String, String>{
      'android': '--dart-define-from-file="$_repoRoot/android.env"',
      'run': '--dart-define-from-file="$_repoRoot/local.env"',
      'run-linux': '--dart-define-from-file="$_repoRoot/local.env"',
      'web': '--dart-define-from-file="$_repoRoot/local.env"',
      'web-release': '--dart-define-from-file="$_repoRoot/local.env"',
      'linux-debug': '--dart-define-from-file="$_repoRoot/staging.env"',
      'linux-release': '--dart-define-from-file="$_repoRoot/linux.env"',
      'windows-debug': '-ConfigFile "staging.env"',
      'windows-release': '-ConfigFile "C:/windows.env"',
      'macos-debug': '--dart-define-from-file="$_repoRoot/staging.env"',
      'macos-release': '--dart-define-from-file="$_repoRoot/testflight.env"',
    };

    for (final entry in expectedConfigs.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'DART=dart-under-test',
        'FLUTTER=flutter-under-test',
        'LOCAL_CONFIG=local.env',
        'ANDROID_CONFIG=android.env',
        'LINUX_CONFIG=linux.env',
        'WINDOWS_CONFIG=C:/windows.env',
        'STAGING_CONFIG=staging.env',
        'TESTFLIGHT_CONFIG=testflight.env',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout.toString(),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test('desktop build modes accept a per-target configuration override', () {
    final expectedOutputs = <String, String>{
      'macos-debug': '--dart-define-from-file="$_repoRoot/prod.env"',
      'macos-profile': '--dart-define-from-file="$_repoRoot/prod.env"',
      'macos-release': '--dart-define-from-file="$_repoRoot/prod.env"',
      'linux-debug': '--dart-define-from-file="$_repoRoot/prod.env"',
      'linux-profile': '--dart-define-from-file="$_repoRoot/prod.env"',
      'linux-release': '--config "prod.env"',
      'windows-debug': '-ConfigFile "C:/prod.env"',
      'windows-profile': '-ConfigFile "C:/prod.env"',
      'windows-release': '-ConfigFile "C:/prod.env"',
    };

    for (final entry in expectedOutputs.entries) {
      final name = entry.key.toUpperCase().replaceAll('-', '_');
      final value = entry.key.startsWith('windows')
          ? 'C:/prod.env'
          : 'prod.env';
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'FLUTTER=flutter-under-test',
        'DART=dart-under-test',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
        '${name}_CONFIG=$value',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout.toString(),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test(
    'Android build isolates Gradle state and uses the guarded billing channel',
    () {
      final result = Process.runSync(_makeExecutable(), const [
        '--no-print-directory',
        '--dry-run',
        'android',
        'FLUTTER=flutter-under-test',
        'ANDROID_CONFIG=android.env',
        'ANDROID_GRADLE_HOME=build/android/gradle-test-home',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final output = result.stdout.toString();
      expect(
        output,
        contains(
          'GRADLE_USER_HOME="$_repoRoot/build/android/gradle-test-home"',
        ),
      );
      expect(
        output,
        contains('--dart-define=POMODOIST_BILLING_CHANNEL=storekit'),
      );
    },
  );

  test(
    'Android entry point follows the environment in its dart-define file',
    () {
      final profiles = Directory.systemTemp.createTempSync(
        'pomodoist-android-target-',
      );
      addTearDown(() => profiles.deleteSync(recursive: true));

      final expectedTargets = <String, String>{
        'local.env': 'lib/main_development.dart',
        'staging.env': 'lib/main_staging.dart',
        'production.env': 'lib/main.dart',
        'selfhosted.env': 'lib/main.dart',
        // A JSON dart-define file is not readable as dotenv, so the resolver
        // yields nothing and the pair falls back to the production entry point.
        'production.json': 'lib/main.dart',
        'missing.env': 'lib/main.dart',
      };
      for (final entry in expectedTargets.entries) {
        final profile = File('${profiles.path}/${entry.key}');
        final environment = entry.key.split('.').first;
        profile.writeAsStringSync(
          entry.key.endsWith('.json')
              ? '{"POMODOIST_ENVIRONMENT": "$environment"}\n'
              : 'POMODOIST_ENVIRONMENT=$environment\n',
        );

        expect(
          _androidTarget(profile.path),
          '--target "${entry.value}"',
          reason: entry.key,
        );
      }

      expect(
        _androidTarget(
          File('${profiles.path}/production.env').path,
          extraArguments: const ['ANDROID_TARGET=lib/main_staging.dart'],
        ),
        '--target "lib/main_staging.dart"',
        reason: 'an explicit ANDROID_TARGET still wins',
      );
    },
  );

  test('setup prepares environments before resolving packages', () {
    final result = Process.runSync(_makeExecutable(), const [
      '--no-print-directory',
      '--dry-run',
      'setup-flutter',
      'DART=dart-under-test',
      'FLUTTER=flutter-under-test',
    ], workingDirectory: _repoRoot);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final output = result.stdout.toString();
    expect(output, contains('dart-under-test" tool/env_setup.dart bootstrap'));
    expect(output, contains('dart-under-test" tool/env_setup.dart sync'));
    final syncIndex = output.indexOf(
      'dart-under-test" tool/env_setup.dart sync',
    );
    expect(syncIndex, lessThan(output.indexOf('flutter-under-test" pub get')));
    expect(
      output.indexOf('dart-under-test" tool/env_setup.dart bootstrap'),
      lessThan(syncIndex),
    );
  });

  test('iPhone and iPad mode targets run their selected simulators', () {
    const simulators = <String, String>{
      'ios-debug': 'iPhone Test',
      'ios-profile': 'iPhone Test',
      'ipad-debug': 'iPad Test',
      'ipad-profile': 'iPad Test',
    };

    for (final entry in simulators.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'IOS_SIMULATOR=iPhone Test',
        'IPAD_SIMULATOR=iPad Test',
        'FLUTTER=flutter-under-test',
        'LOCAL_CONFIG=pubspec.yaml',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      final commands = result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .where((line) => line.isNotEmpty)
          .toList();
      expect(commands, hasLength(4), reason: entry.key);
      expect(
        commands.first,
        anyOf(
          contains('ln -s ../../build/flutter'),
          contains('link-build.ps1'),
        ),
        reason: '${entry.key}: the flutter build directory must resolve to the '
            'root build',
      );
      expect(
        commands.sublist(1),
        [
          'xcrun simctl bootstatus "${entry.value}" -b',
          'open -a Simulator',
          'cd "$_repoRoot/apps/flutter" && "flutter-under-test" run -d "${entry.value}" --debug '
              '--flavor "development" '
              '--target "lib/main_development.dart" '
              '--dart-define-from-file="$_repoRoot/pubspec.yaml" '
              '--dart-define=POMODOIST_RELEASE='
              '"0123456789abcdef0123456789abcdef01234567" '
              '--dart-define=POMODOIST_BILLING_CHANNEL=storekit',
        ],
        reason: entry.key,
      );
    }
  });

  test('Watch mode targets build and launch their selected configuration', () {
    const configurations = <String, String>{
      'watch-debug': 'Debug',
      'watch-profile': 'Profile',
    };
    final makeWorkingDirectory = _repoRoot.replaceAll(r'\', '/');
    final watchBuildDir = '$makeWorkingDirectory/build/watch-test';

    for (final entry in configurations.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'WATCH_SIMULATOR=Watch Test',
        'WATCH_BUILD_DIR=build/watch-test',
      ], workingDirectory: _repoRoot);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .where((line) => line.isNotEmpty),
        [
          'xcrun simctl bootstatus "Watch Test" -b',
          'open -a Simulator',
          'xcodebuild -quiet -project "$_repoRoot/apps/flutter/ios/Runner.xcodeproj" '
              '-target PomodoistWatch -configuration "${entry.value}" '
              '-sdk watchsimulator SYMROOT="$watchBuildDir" '
              'OBJROOT="$watchBuildDir/obj" build',
          'xcrun simctl install "Watch Test" '
              '"$watchBuildDir/${entry.value}-watchsimulator/'
              'PomodoistWatch.app"',
          'xcrun simctl launch "Watch Test" '
              'com.finchforge.pomodoist.watchkitapp',
        ],
        reason: entry.key,
      );
    }
  });

  test('windows-installer builds a configured release before packaging', () {
    final result = Process.runSync(_makeExecutable(), const [
      '--no-print-directory',
      '--dry-run',
      'windows-installer',
      'WINDOWS_CONFIG=C:/secure config/pomodoist-windows-production.json',
      'WINDOWS_RELEASE_DIR=C:/release output/Pomodoist',
      'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      'DART=dart-under-test',
    ], workingDirectory: _repoRoot);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final commands = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    expect(commands, hasLength(2));
    expect(
      commands[0],
      'powershell.exe -NoProfile -ExecutionPolicy Bypass '
      '-File ./tool/windows/build.ps1 -Configuration Release -Clean '
      '-Flavor "production" '
      '-ConfigFile "C:/secure config/pomodoist-windows-production.json" '
      '-Target "lib/main.dart" '
      '-ReleaseSha "0123456789abcdef0123456789abcdef01234567"',
    );
    expect(
      commands[1],
      'powershell.exe -NoProfile -ExecutionPolicy Bypass '
      '-File ./tool/windows/installer/build.ps1 '
      '-Flavor "production" '
      '-BuildDirectory "C:/release output/Pomodoist"',
    );
    expect(commands.join('\n'), isNot(contains('-Configuration Debug')));
  });

  test('make help runs from a Windows PowerShell environment', () {
    if (!Platform.isWindows) return;

    final result = Process.runSync(_makeExecutable(), const [
      '--no-print-directory',
      'help',
    ], workingDirectory: _repoRoot);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('make windows-installer'));
  });
}

String _makeExecutable() {
  final command = Platform.isWindows ? 'where.exe' : 'which';
  final lookup = Process.runSync(command, const ['make']);
  if (lookup.exitCode == 0) {
    return lookup.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
  }

  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final packages = Directory('$localAppData/Microsoft/WinGet/Packages');
      if (packages.existsSync()) {
        for (final entity in packages.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith(r'\bin\make.exe')) {
            return entity.path;
          }
        }
      }
    }
  }

  throw StateError('GNU Make is required for this test.');
}

/// Resolves `make --dry-run android` for [config] and returns its `--target`
/// argument, so the test exercises the real dotenv reader in the Makefile.
String _androidTarget(String config, {List<String> extraArguments = const []}) {
  final result = Process.runSync(_makeExecutable(), [
    '--no-print-directory',
    '--dry-run',
    'android',
    'FLUTTER=flutter-under-test',
    'DART=${_dartExecutable()}',
    'ANDROID_CONFIG=$config',
    'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
    ...extraArguments,
  ], workingDirectory: _repoRoot);

  expect(result.exitCode, 0, reason: '$config: ${result.stderr}');
  final match = RegExp(
    r'--target "([^"]*)"',
  ).firstMatch(result.stdout.toString());
  expect(match, isNotNull, reason: '$config produced no --target');
  return match!.group(0)!;
}

String _dartExecutable() {
  final pinned = File('../../.fvm/flutter_sdk/bin/dart');
  return pinned.existsSync() ? pinned.absolute.path : 'dart';
}

String get _repoRoot =>
    Directory('../..').resolveSymbolicLinksSync().replaceAll(r'\', '/');
