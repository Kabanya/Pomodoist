import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS focus widget uses an adaptive nontransparent background', () async {
    final source = await File(
      'apple/FocusWidget/PomodoistFocusWidget.swift',
    ).readAsString();

    expect(source, contains('Color(UIColor.systemBackground)'));
    expect(
      source,
      isNot(
        contains(
          'content.containerBackground(for: .widget) {\n'
          '        Color.clear',
        ),
      ),
    );
    expect(source, isNot(contains('content.background(Color.clear)')));
  });

  test('iOS project exposes the focus widget extension', () async {
    final tracked = (await Process.run('git', ['ls-files'])).stdout as String;
    final contentsFiles = tracked
        .split('\n')
        .where(
          (path) =>
              path.endsWith('Contents.json') && path.contains('.xcassets/'),
        )
        .where(
          (path) =>
              path.startsWith('ios/') ||
              path.startsWith('macos/') ||
              path.startsWith('apple/'),
        );
    for (final contentsPath in contentsFiles) {
      final decoded = jsonDecode(await File(contentsPath).readAsString());
      final images = (decoded as Map<String, dynamic>)['images'];
      if (images is! List) continue;
      for (final image in images.whereType<Map<String, dynamic>>()) {
        final filename = image['filename'];
        if (filename is! String || filename.isEmpty) continue;
        final asset = File('${File(contentsPath).parent.path}/$filename');
        expect(asset.existsSync(), isTrue, reason: asset.path);
      }
    }

    if (!Platform.isMacOS) return;

    final result = await Process.run('xcodebuild', [
      '-project',
      'ios/Runner.xcodeproj',
      '-list',
      '-json',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final project =
        (jsonDecode(result.stdout as String) as Map<String, dynamic>)['project']
            as Map<String, dynamic>;
    expect(
      (project['targets'] as List<dynamic>).cast<String>(),
      contains('PomodoistFocusWidgetExtension'),
    );
  });
}
