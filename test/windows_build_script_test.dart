import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clean build stops when flutter clean leaves the build directory', () {
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
      'tool/windows/build.ps1',
    ).copySync('${scriptDirectory.path}${Platform.pathSeparator}build.ps1');

    Directory('${testRoot.path}${Platform.pathSeparator}build').createSync();
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

    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}\n${result.stderr}',
      contains('flutter clean did not remove'),
    );
    expect(flutterLog.readAsLinesSync(), ['clean']);
  });
}
