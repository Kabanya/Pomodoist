import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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

    expect(commands, hasLength(3));
    expect(
      commands[0],
      'dart-under-test run tool/desktop_release_config.dart '
      '--config "C:/secure config/pomodoist-windows-production.json"',
    );
    expect(
      commands[1],
      'powershell.exe -NoProfile -ExecutionPolicy Bypass '
      '-File ./tool/windows/build.ps1 -Configuration Release -Clean '
      '-ConfigFile "C:/secure config/pomodoist-windows-production.json" '
      '-ReleaseSha "0123456789abcdef0123456789abcdef01234567"',
    );
    expect(
      commands[2],
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
