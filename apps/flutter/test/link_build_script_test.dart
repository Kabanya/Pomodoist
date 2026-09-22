import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Flutter project keeps build/ and .dart_tool as symlinks into the ignored
// repository-root build directory. Those links are deliberately untracked, so
// a fresh checkout has a missing or dangling path and Flutter cannot create or
// remove it. tool/link-build.sh has to repair every form of the path, which is
// what regressed in the release that shipped the committed links.
void main() {
  late Directory root;
  late Directory flutterRoot;

  setUp(() {
    if (Platform.isWindows) return;
    root = Directory.systemTemp.createTempSync('pomodoist-link-build-');
    flutterRoot = Directory('${root.path}/apps/flutter')
      ..createSync(recursive: true);
    File(
      '${root.path}/tool/link-build.sh',
    ).createSync(recursive: true);
    File('../../tool/link-build.sh').copySync(
      '${root.path}/tool/link-build.sh',
    );
  });

  tearDown(() {
    if (Platform.isWindows) return;
    root.deleteSync(recursive: true);
  });

  // Runs the real script against the temp checkout and returns its stderr.
  String runLinker() {
    final result = Process.runSync('bash', ['tool/link-build.sh'], workingDirectory: root.path);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    return result.stderr.toString();
  }

  void expectLinks() {
    for (final entry in const {
      'build': '../../build/flutter',
      '.dart_tool': '../../build/dart_tool',
    }.entries) {
      final link = Link('${flutterRoot.path}/${entry.key}');
      expect(link.existsSync(), isTrue, reason: '${entry.key} is not a link');
      expect(link.targetSync(), entry.value, reason: '${entry.key} target');
      expect(
        Directory(link.resolveSymbolicLinksSync()).existsSync(),
        isTrue,
        reason: '${entry.key} must resolve to a real directory',
      );
    }
    expect(Directory('${root.path}/build/flutter').existsSync(), isTrue);
    expect(Directory('${root.path}/build/dart_tool').existsSync(), isTrue);
  }

  test('creates the links from a fresh checkout', () {
    if (Platform.isWindows) return;
    runLinker();
    expectLinks();
  });

  test('replaces dangling links restored from a bad commit', () {
    if (Platform.isWindows) return;
    for (final name in ['build', '.dart_tool']) {
      Link('${flutterRoot.path}/$name').createSync('../../build/$name');
    }
    // Nothing exists at the targets yet, so both links hang.
    expect(Directory('${root.path}/build').existsSync(), isFalse);

    runLinker();
    expectLinks();
  });

  test('replaces real directories left behind by an earlier Flutter run', () {
    if (Platform.isWindows) return;
    for (final name in ['build', '.dart_tool']) {
      Directory('${flutterRoot.path}/$name').createSync();
      File(
        '${flutterRoot.path}/$name/stale-artifact',
      ).writeAsStringSync('stale');
    }

    runLinker();
    expectLinks();
    expect(
      File('${flutterRoot.path}/build/stale-artifact').existsSync(),
      isFalse,
      reason: 'stale directory contents must be removed, not merged',
    );
  });

  test('is idempotent across repeated runs', () {
    if (Platform.isWindows) return;
    runLinker();
    final first = File(
      '${root.path}/build/flutter/kept',
    )..writeAsStringSync('kept');
    expect(runLinker(), isEmpty, reason: 'second run must not report repairs');
    expectLinks();
    expect(
      first.existsSync(),
      isTrue,
      reason: 'a correct link must be left alone',
    );
  });

  test('leaves unrelated files alone', () {
    if (Platform.isWindows) return;
    final pubspec = File('${flutterRoot.path}/pubspec.yaml')
      ..writeAsStringSync('name: pomodoist\n');
    runLinker();
    expect(pubspec.readAsStringSync(), 'name: pomodoist\n');
  });
}
