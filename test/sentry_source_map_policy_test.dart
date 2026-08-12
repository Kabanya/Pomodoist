import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('artifact verifier rejects absolute source paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'pomodoist-absolute-source-verifier.',
    );
    addTearDown(() => root.delete(recursive: true));
    final main = File('${root.path}/lib/main.dart');
    await main.parent.create(recursive: true);
    await main.writeAsString('Future<void> main() {}');
    const debugId = '01234567-89ab-cdef-0123-456789abcdef';
    final runtime = File('${root.path}/runtime.js');
    final exported = File('${root.path}/exported.js');
    await runtime.writeAsString('//# debugId=$debugId\n');
    await exported.writeAsString('//# debugId=$debugId\n');
    final sourceMap = File('${root.path}/main.dart.js.map');
    await sourceMap.writeAsString(
      jsonEncode({
        'version': 3,
        'debug_id': debugId,
        'sources': [
          '../../../lib/main.dart',
          '/opt/homebrew/share/flutter/packages/flutter/lib/widgets.dart',
        ],
        'sourcesContent': [await main.readAsString(), null],
        'names': <String>[],
        'mappings': 'AAAA',
      }),
    );

    final result = await Process.run('python3', [
      File('tool/verify_sentry_artifacts.py').absolute.path,
      runtime.path,
      exported.path,
      sourceMap.path,
      root.path,
    ]);

    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}${result.stderr}',
      contains('absolute source path'),
    );
  });

  test(
    'web artifacts embed only Pomodoist lib sources and hide maps',
    () async {
      final dockerfile = await File('deploy/web/Dockerfile').readAsString();
      final nginx = await File('deploy/web/nginx.conf').readAsString();
      final preparer = await File(
        'tool/prepare_sentry_sourcemaps.dart',
      ).readAsString();
      final verifier = await File(
        'tool/verify_sentry_artifacts.py',
      ).readAsString();

      expect(dockerfile, contains('flutter build web --release --source-maps'));
      expect(
        dockerfile,
        contains("find build/web -type f -name '*.map' -delete"),
      );
      expect(dockerfile, isNot(contains('account-sync-platform')));
      expect(nginx, contains(r'location ~* \.map$'));
      expect(preparer, contains("'../../../lib/'"));
      expect(preparer, isNot(contains('account-sync-platform')));
      expect(verifier, contains('debug_id'));
      expect(verifier, isNot(contains('account-sync-platform')));

      final root = await Directory.systemTemp.createTemp('pomodoist-verifier.');
      addTearDown(() => root.delete(recursive: true));
      final main = File('${root.path}/lib/main.dart');
      await main.parent.create(recursive: true);
      await main.writeAsString('Future<void> main() {}');
      const debugId = '01234567-89ab-cdef-0123-456789abcdef';
      final runtime = File('${root.path}/runtime.js');
      final exported = File('${root.path}/exported.js');
      await runtime.writeAsString('//# debugId=$debugId\n');
      await exported.writeAsString('//# debugId=$debugId\n');
      final sourceMap = File('${root.path}/main.dart.js.map');
      await sourceMap.writeAsString(
        jsonEncode({
          'version': 3,
          'debug_id': debugId,
          'sources': ['../../../lib/main.dart', 'webpack://third-party.js'],
          'sourcesContent': [await main.readAsString(), 'must-not-be-embedded'],
          'names': <String>[],
          'mappings': 'AAAA',
        }),
      );
      final result = await Process.run('python3', [
        File('tool/verify_sentry_artifacts.py').absolute.path,
        runtime.path,
        exported.path,
        sourceMap.path,
        root.path,
      ]);

      expect(
        result.exitCode,
        isNot(0),
        reason: '${result.stdout}${result.stderr}',
      );
      expect('${result.stdout}${result.stderr}', contains('non-lib'));
    },
  );
}
