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

    // Inspect the project without resolving its unrelated Swift packages.
    final result = await Process.run('plutil', [
      '-convert',
      'json',
      '-o',
      '-',
      'ios/Runner.xcodeproj/project.pbxproj',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final document =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final objects = document['objects'] as Map<String, dynamic>;
    final project = objects[document['rootObject']] as Map<String, dynamic>;
    final targets = (project['targets'] as List<dynamic>)
        .map((id) => objects[id] as Map<String, dynamic>)
        .where((target) => target['name'] == 'PomodoistFocusWidgetExtension');
    expect(targets, hasLength(1));
    expect(targets.single['isa'], 'PBXNativeTarget');
    expect(
      targets.single['productType'],
      'com.apple.product-type.app-extension',
    );
  });
}
