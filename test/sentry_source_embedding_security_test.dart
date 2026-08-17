import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/prepare_sentry_sourcemaps.dart' as preparer;

void main() {
  test(
    'rewrites absolute third-party source paths without embedding them',
    () async {
      final testRoot = await Directory.systemTemp.createTemp(
        'pomodoist-sentry-absolute-paths.',
      );
      addTearDown(() => testRoot.delete(recursive: true));
      final repository = await _repositoryFixture(testRoot);
      final main = File('${repository.path}/lib/main.dart');
      await main.writeAsString('Future<void> main() async {}');
      final sourceMap = File('${repository.path}/main.dart.js.map');
      await sourceMap.writeAsString(
        jsonEncode({
          'version': 3,
          'sources': [
            '../../../lib/main.dart',
            '/opt/homebrew/share/flutter/packages/flutter/lib/widgets.dart',
            r'C:\flutter\packages\flutter\lib\material.dart',
          ],
          'names': <String>[],
          'mappings': '',
        }),
      );

      await preparer.prepareSentrySourceMap(sourceMap.path, repository.path);

      final decoded = jsonDecode(await sourceMap.readAsString()) as Map;
      expect(decoded['sources'], [
        '../../../lib/main.dart',
        'third-party:///1/widgets.dart',
        'third-party:///2/material.dart',
      ]);
      expect(decoded['sourcesContent'], [
        await main.readAsString(),
        null,
        null,
      ]);
    },
  );

  group('Sentry source embedding symlink policy', () {
    late Directory testRoot;

    setUp(() async {
      testRoot = await Directory.systemTemp.createTemp(
        'pomodoist-sentry-source-security.',
      );
    });

    tearDown(() async {
      await testRoot.delete(recursive: true);
    });

    test('rejects a first-party symlink to an outside sentinel', () async {
      final repository = await _repositoryFixture(testRoot);
      final sentinel = File('${testRoot.path}/outside-secret.txt');
      await sentinel.writeAsString('OUTSIDE-SENTINEL-MUST-NOT-BE-EMBEDDED');
      await Link('${repository.path}/lib/main.dart').create(sentinel.path);
      final sourceMap = await _sourceMapFixture(repository);

      await expectLater(
        preparer.prepareSentrySourceMap(sourceMap.path, repository.path),
        throwsA(isA<FormatException>()),
      );

      expect(
        await sourceMap.readAsString(),
        isNot(contains('OUTSIDE-SENTINEL-MUST-NOT-BE-EMBEDDED')),
      );
    });

    test('rejects an in-repository first-party symlink', () async {
      if (Platform.isWindows) return;

      final repository = await _repositoryFixture(testRoot);
      final realMain = File('${repository.path}/lib/real_main.dart');
      await realMain.writeAsString('Future<void> main() async {}');
      await Link('${repository.path}/lib/main.dart').create(realMain.path);
      final sourceMap = await _sourceMapFixture(repository);

      await expectLater(
        preparer.prepareSentrySourceMap(sourceMap.path, repository.path),
        throwsA(isA<FormatException>()),
      );

      final debugId = '01234567-89ab-cdef-0123-456789abcdef';
      final runtimeJs = File('${testRoot.path}/runtime.js');
      final exportedJs = File('${testRoot.path}/exported.js');
      final javascript = '//# debugId=$debugId\n';
      await runtimeJs.writeAsString(javascript);
      await exportedJs.writeAsString(javascript);
      await sourceMap.writeAsString(
        jsonEncode({
          'version': 3,
          'debug_id': debugId,
          'sources': ['../../../lib/main.dart'],
          'sourcesContent': [await realMain.readAsString()],
          'names': <String>[],
          'mappings': '',
        }),
      );
      final verifier = await Process.run('python3', [
        File('tool/verify_sentry_artifacts.py').absolute.path,
        runtimeJs.path,
        exportedJs.path,
        sourceMap.path,
        repository.path,
      ]);

      expect(verifier.exitCode, isNot(0));
      expect(
        '${verifier.stdout}\n${verifier.stderr}'.toLowerCase(),
        contains('symlink'),
      );
    });

    test(
      'rejects a broken first-party symlink without partial embedding',
      () async {
        final repository = await _repositoryFixture(testRoot);
        await Link(
          '${repository.path}/lib/main.dart',
        ).create('${repository.path}/lib/missing.dart');
        final sourceMap = await _sourceMapFixture(repository);

        await expectLater(
          preparer.prepareSentrySourceMap(sourceMap.path, repository.path),
          throwsA(isA<FormatException>()),
        );

        final decoded = jsonDecode(await sourceMap.readAsString());
        expect(decoded, isNot(contains('sourcesContent')));
      },
    );
  });
}

Future<Directory> _repositoryFixture(Directory testRoot) async {
  final repository = Directory('${testRoot.path}/repo');
  await Directory('${repository.path}/lib').create(recursive: true);
  return repository;
}

Future<File> _sourceMapFixture(Directory repository) async {
  final sourceMap = File('${repository.path}/main.dart.js.map');
  await sourceMap.writeAsString(
    jsonEncode({
      'version': 3,
      'sources': ['../../../lib/main.dart'],
      'names': <String>[],
      'mappings': '',
    }),
  );
  return sourceMap;
}
