import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platform mode targets invoke their matching build modes', () {
    const expectedCommands = <String, String>{
      'web-debug': 'flutter-under-test build web --debug',
      'web-profile': 'flutter-under-test build web --profile',
      'web-release': 'flutter-under-test build web --release',
      'linux-debug': 'flutter-under-test build linux --debug',
      'linux-profile': 'flutter-under-test build linux --profile',
      'linux-release': 'flutter-under-test build linux --release',
      'windows-debug':
          'powershell.exe -NoProfile -ExecutionPolicy Bypass '
          '-File ./tool/windows/build.ps1 -Configuration Debug',
      'windows-profile':
          'powershell.exe -NoProfile -ExecutionPolicy Bypass '
          '-File ./tool/windows/build.ps1 -Configuration Profile',
      'windows-release':
          'powershell.exe -NoProfile -ExecutionPolicy Bypass '
          '-File ./tool/windows/build.ps1 -Configuration Release',
      'macos-debug': 'flutter-under-test build macos --debug',
      'macos-profile': 'flutter-under-test build macos --profile',
      'macos-release': 'flutter-under-test build macos --release',
    };

    for (final entry in expectedCommands.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'DART=dart-under-test',
        'FLUTTER=flutter-under-test',
        'LOCAL_CONFIG=local.env',
        'LINUX_CONFIG=pubspec.yaml',
        'WINDOWS_CONFIG=pubspec.yaml',
        'TESTFLIGHT_CONFIG=pubspec.yaml',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout.toString(),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test('platform targets consume their generated environment files', () {
    const expectedConfigs = <String, String>{
      'run': '--dart-define-from-file="local.env"',
      'run-linux': '--dart-define-from-file="local.env"',
      'web': '--dart-define-from-file="local.env"',
      'web-release': '--dart-define-from-file="local.env"',
      'linux-debug': '--dart-define-from-file="linux.env"',
      'linux-release': '--dart-define-from-file="linux.env"',
      'windows-debug': '-ConfigFile "C:/windows.env"',
      'windows-release': '-ConfigFile "C:/windows.env"',
      'macos-debug': '--dart-define-from-file="local.env"',
      'macos-release': '--dart-define-from-file="testflight.env"',
    };

    for (final entry in expectedConfigs.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'DART=dart-under-test',
        'FLUTTER=flutter-under-test',
        'LOCAL_CONFIG=local.env',
        'LINUX_CONFIG=linux.env',
        'WINDOWS_CONFIG=C:/windows.env',
        'TESTFLIGHT_CONFIG=testflight.env',
        'POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout.toString(),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test('setup prepares environments before resolving packages', () {
    final result = Process.runSync(_makeExecutable(), const [
      '--no-print-directory',
      '--dry-run',
      'setup-flutter',
      'DART=dart-under-test',
      'FLUTTER=flutter-under-test',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final output = result.stdout.toString();
    expect(output, contains('dart-under-test tool/env_setup.dart setup'));
    expect(
      output.indexOf('dart-under-test tool/env_setup.dart setup'),
      lessThan(output.indexOf('flutter-under-test pub get')),
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
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .where((line) => line.isNotEmpty),
        [
          'xcrun simctl bootstatus "${entry.value}" -b',
          'open -a Simulator',
          'flutter-under-test run -d "${entry.value}" --debug '
              '--dart-define-from-file="pubspec.yaml" '
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
    final watchBuildDir = '${Directory.current.path}/build/watch-test';

    for (final entry in configurations.entries) {
      final result = Process.runSync(_makeExecutable(), [
        '--no-print-directory',
        '--dry-run',
        entry.key,
        'WATCH_SIMULATOR=Watch Test',
        'WATCH_BUILD_DIR=build/watch-test',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      expect(
        result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .where((line) => line.isNotEmpty),
        [
          'xcrun simctl bootstatus "Watch Test" -b',
          'open -a Simulator',
          'xcodebuild -quiet -project ios/Runner.xcodeproj '
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
    ], workingDirectory: Directory.current.path);

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
      '-ConfigFile "C:/secure config/pomodoist-windows-production.json" '
      '-ReleaseSha "0123456789abcdef0123456789abcdef01234567"',
    );
    expect(
      commands[1],
      'powershell.exe -NoProfile -ExecutionPolicy Bypass '
      '-File ./tool/windows/installer/build.ps1 '
      '-BuildDirectory "C:/release output/Pomodoist"',
    );
    expect(commands.join('\n'), isNot(contains('-Configuration Debug')));
  });

  test('make help runs from a Windows PowerShell environment', () {
    if (!Platform.isWindows) return;

    final result = Process.runSync(_makeExecutable(), const [
      '--no-print-directory',
      'help',
    ], workingDirectory: Directory.current.path);

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
