import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared Apple widgets compile for iOS 15', () async {
    if (!Platform.isMacOS) return;
    final sdk = await Process.run('xcrun', [
      '--sdk',
      'iphoneos',
      '--show-sdk-path',
    ]);
    expect(sdk.exitCode, 0, reason: '${sdk.stderr}');
    final compile = await Process.run('xcrun', [
      'swiftc',
      '-typecheck',
      '-parse-as-library',
      '-target',
      'arm64-apple-ios15.0',
      '-sdk',
      (sdk.stdout as String).trim(),
      'apple/FocusWidget/PomodoistFocusShared.swift',
      'apple/FocusWidget/PomodoistFocusWidget.swift',
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
  });

  test(
    'native widget snapshots retain legacy decoding and safe links',
    () async {
      if (!Platform.isMacOS) return;
      final directory = await Directory.systemTemp.createTemp(
        'apple-widget-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final binary = '${directory.path}/snapshot-check';
      final compile = await Process.run('xcrun', [
        'swiftc',
        'apple/FocusWidget/PomodoistFocusShared.swift',
        'tool/tests/apple_widget_snapshot_test.swift',
        '-o',
        binary,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
      final run = await Process.run(binary, []);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, contains('Apple widget snapshot checks passed'));
    },
  );

  test(
    'iOS and macOS widget extensions bundle the existing Pomo poses',
    () async {
      if (!Platform.isMacOS) return;
      for (final platform in ['ios', 'macos']) {
        final result = await Process.run('plutil', [
          '-convert',
          'json',
          '-o',
          '-',
          '$platform/Runner.xcodeproj/project.pbxproj',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final objects =
            (jsonDecode(result.stdout as String)
                    as Map<String, dynamic>)['objects']
                as Map<String, dynamic>;
        final widget = objects.values
            .whereType<Map<String, dynamic>>()
            .singleWhere(
              (object) =>
                  object['isa'] == 'PBXNativeTarget' &&
                  object['name'] == 'PomodoistFocusWidgetExtension',
            );
        final resources = (widget['buildPhases'] as List)
            .map((id) => objects[id] as Map<String, dynamic>)
            .singleWhere((phase) => phase['isa'] == 'PBXResourcesBuildPhase');
        final pomo = (resources['files'] as List)
            .map(
              (id) => objects[objects[id]['fileRef']] as Map<String, dynamic>,
            )
            .singleWhere((ref) => ref['name'] == 'Pomo');
        expect(pomo['lastKnownFileType'], 'folder');
        expect(pomo['sourceTree'], 'SOURCE_ROOT');
        for (final pose in ['calm', 'focus', 'happy', 'rest']) {
          final bundled = File('$platform/${pomo['path']}/$pose-still.webp');
          final original = File('assets/pomo/$pose-still.webp');
          expect(await bundled.readAsBytes(), await original.readAsBytes());
        }
      }
    },
  );

  test(
    'Watch app embeds widgets with matching app groups in every flavor',
    () async {
      if (!Platform.isMacOS) return;
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
      Map<String, dynamic> target(String name) =>
          objects.values.whereType<Map<String, dynamic>>().singleWhere(
            (object) =>
                object['isa'] == 'PBXNativeTarget' && object['name'] == name,
          );
      final app = target('PomodoistWatch');
      final widgets = target('PomodoistWatchWidgets');
      final resources = (widgets['buildPhases'] as List)
          .map((id) => objects[id] as Map<String, dynamic>)
          .singleWhere((phase) => phase['isa'] == 'PBXResourcesBuildPhase');
      expect(
        (resources['files'] as List).map(
          (id) => objects[objects[id]['fileRef']]['path'],
        ),
        contains('PomodoistFocusWidget/PrivacyInfo.xcprivacy'),
      );
      final embed = (app['buildPhases'] as List)
          .map((id) => objects[id] as Map<String, dynamic>)
          .singleWhere(
            (phase) =>
                phase['isa'] == 'PBXCopyFilesBuildPhase' &&
                phase['dstSubfolderSpec'] == '13',
          );
      expect(
        (embed['files'] as List).map((id) => objects[id]['fileRef']),
        contains(widgets['productReference']),
      );
      for (final nativeTarget in [app, widgets]) {
        final list = objects[nativeTarget['buildConfigurationList']];
        for (final id in list['buildConfigurations'] as List) {
          final settings = objects[id]['buildSettings'] as Map<String, dynamic>;
          expect(
            settings['CODE_SIGN_ENTITLEMENTS'],
            'PomodoistWatch/PomodoistWatch.entitlements',
          );
          expect(settings['WATCHOS_DEPLOYMENT_TARGET'], '10.0');
        }
      }
      final entitlement = await File(
        'ios/PomodoistWatch/PomodoistWatch.entitlements',
      ).readAsString();
      expect(entitlement, contains(r'$(POMODOIST_APP_GROUP)'));
      for (final path in [
        'ios/PomodoistWatch/Info.plist',
        'ios/PomodoistWatchWidgets/Info.plist',
      ]) {
        final info = await File(path).readAsString();
        expect(info, contains(r'$(POMODOIST_APP_GROUP)'));
        expect(info, contains(r'$(POMODOIST_URL_SCHEME)'));
      }
    },
  );

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
