import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release build retries a transient native hook failure', () {
    if (!Platform.isWindows) return;

    final testRoot = Directory.systemTemp.createTempSync(
      'pomodoist-windows-build-retry-',
    );
    addTearDown(() => testRoot.deleteSync(recursive: true));

    final scriptDirectory = Directory(
      '${testRoot.path}${Platform.pathSeparator}tool'
      '${Platform.pathSeparator}windows',
    )..createSync(recursive: true);
    File(
      '../../tool/windows/build.ps1',
    ).copySync('${scriptDirectory.path}${Platform.pathSeparator}build.ps1');
    File(
      '../../tool/windows/link-build.ps1',
    ).copySync('${scriptDirectory.path}${Platform.pathSeparator}link-build.ps1');
    // build.ps1 dot-sources the flavor table from its own directory, so the
    // copy has to carry it too or the script aborts before it reaches Flutter.
    File('../../tool/windows/flavors.ps1').copySync(
      '${scriptDirectory.path}${Platform.pathSeparator}flavors.ps1',
    );

    Directory('${testRoot.path}/apps/flutter').createSync(recursive: true);
    final configFile = File(
      '${testRoot.path}${Platform.pathSeparator}production.json',
    )..writeAsStringSync('{}');
    final dartLog = File('${testRoot.path}${Platform.pathSeparator}dart.log');
    final dartMarker = File(
      '${testRoot.path}${Platform.pathSeparator}dart-succeeded.marker',
    );
    final flutterLog = File(
      '${testRoot.path}${Platform.pathSeparator}flutter.log',
    );

    final fakeBin = Directory(
      '${testRoot.path}${Platform.pathSeparator}fake-bin',
    )..createSync();
    File('${fakeBin.path}${Platform.pathSeparator}dart.cmd').writeAsStringSync(
      '@echo off\r\n'
      'echo %*>>"%FAKE_DART_LOG%"\r\n'
      'if not exist "%FAKE_DART_MARKER%" (\r\n'
      '  type nul >"%FAKE_DART_MARKER%"\r\n'
      '  exit /b 255\r\n'
      ')\r\n'
      'exit /b 0\r\n',
    );
    File(
      '${fakeBin.path}${Platform.pathSeparator}flutter.cmd',
    ).writeAsStringSync(
      '@echo off\r\necho %*>>"%FAKE_FLUTTER_LOG%"\r\nexit /b 0\r\n',
    );

    final environment = Map<String, String>.from(Platform.environment)
      ..['PATH'] = '${fakeBin.path};${Platform.environment['PATH'] ?? ''}'
      ..['FAKE_DART_LOG'] = dartLog.path
      ..['FAKE_DART_MARKER'] = dartMarker.path
      ..['FAKE_FLUTTER_LOG'] = flutterLog.path;
    final result = Process.runSync('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      '${scriptDirectory.path}${Platform.pathSeparator}build.ps1',
      '-Configuration',
      'Release',
      '-ConfigFile',
      configFile.path,
      '-ReleaseSha',
      '0123456789abcdef0123456789abcdef01234567',
    ], environment: environment);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(dartLog.readAsLinesSync(), hasLength(2));
    expect(flutterLog.readAsLinesSync(), [
      'build windows --release '
          '--flavor production '
          '--target lib/main.dart '
          '--dart-define-from-file=${configFile.path} '
          '--dart-define=POMODOIST_RELEASE='
          '0123456789abcdef0123456789abcdef01234567 '
          '--dart-define=POMODOIST_BILLING_CHANNEL=stripe',
    ]);
  });

  test('clean build recreates the root build link', () {
    if (!Platform.isWindows) return;

    final testRoot = Directory.systemTemp.createTempSync(
      'pomodoist-windows-build-script-',
    );
    addTearDown(() => testRoot.deleteSync(recursive: true));

    final scriptDirectory = Directory(
      '${testRoot.path}${Platform.pathSeparator}tool'
      '${Platform.pathSeparator}windows',
    )..createSync(recursive: true);
    File(
      '../../tool/windows/build.ps1',
    ).copySync('${scriptDirectory.path}${Platform.pathSeparator}build.ps1');
    File(
      '../../tool/windows/link-build.ps1',
    ).copySync('${scriptDirectory.path}${Platform.pathSeparator}link-build.ps1');
    // build.ps1 dot-sources the flavor table from its own directory, so the
    // copy has to carry it too or the script aborts before it reaches Flutter.
    File('../../tool/windows/flavors.ps1').copySync(
      '${scriptDirectory.path}${Platform.pathSeparator}flavors.ps1',
    );

    Directory(
      '${testRoot.path}/apps/flutter/build',
    ).createSync(recursive: true);
    Directory('${testRoot.path}/apps/flutter').createSync(recursive: true);
    final configFile = File(
      '${testRoot.path}${Platform.pathSeparator}production.json',
    )..writeAsStringSync('{}');
    final flutterLog = File(
      '${testRoot.path}${Platform.pathSeparator}flutter.log',
    );

    final fakeBin = Directory(
      '${testRoot.path}${Platform.pathSeparator}fake-bin',
    )..createSync();
    File(
      '${fakeBin.path}${Platform.pathSeparator}dart.cmd',
    ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    File(
      '${fakeBin.path}${Platform.pathSeparator}flutter.cmd',
    ).writeAsStringSync(
      '@echo off\r\necho %*>>"%FAKE_FLUTTER_LOG%"\r\nexit /b 0\r\n',
    );

    final environment = Map<String, String>.from(Platform.environment)
      ..['PATH'] = '${fakeBin.path};${Platform.environment['PATH'] ?? ''}'
      ..['FAKE_FLUTTER_LOG'] = flutterLog.path;
    final result = Process.runSync('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      '${scriptDirectory.path}${Platform.pathSeparator}build.ps1',
      '-Configuration',
      'Release',
      '-Clean',
      '-ConfigFile',
      configFile.path,
      '-ReleaseSha',
      '0123456789abcdef0123456789abcdef01234567',
    ], environment: environment);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(flutterLog.readAsLinesSync(), [
      'clean',
      'build windows --release '
          '--flavor production '
          '--target lib/main.dart '
          '--dart-define-from-file=${configFile.path} '
          '--dart-define=POMODOIST_RELEASE='
          '0123456789abcdef0123456789abcdef01234567 '
          '--dart-define=POMODOIST_BILLING_CHANNEL=stripe',
    ]);
    File(
      '${testRoot.path}/apps/flutter/build/probe.txt',
    ).writeAsStringSync('ok');
    expect(
      File('${testRoot.path}/build/flutter/probe.txt').existsSync(),
      isTrue,
      reason: 'apps/flutter/build must resolve to the root build directory.',
    );
  });
}
