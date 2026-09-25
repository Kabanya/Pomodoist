import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

/// The Focus widget and the focus status item share their snapshot through an
/// App Group. The group is never written into a plist or a Swift literal: each
/// target reads `PomodoistAppGroup` out of its own Info.plist, which Xcode
/// expands from `$(POMODOIST_APP_GROUP)` per flavor. Losing that key on one
/// target would silently send that flavor's snapshot to the production group.
void main() {
  test('every focus target publishes its own PomodoistAppGroup', () {
    for (final path in [
      'macos/Runner/Info.plist',
      'macos/PomodoistFocusWidget/Info.plist',
      'ios/Runner/Info.plist',
    ]) {
      final plist = File(path).readAsStringSync();
      expect(
        plist,
        contains('<key>PomodoistAppGroup</key>'),
        reason: '$path must declare PomodoistAppGroup',
      );
      expect(
        plist,
        contains(r'<string>$(POMODOIST_APP_GROUP)</string>'),
        reason: '$path must expand the group from the build configuration',
      );
    }
  });

  test('the app group fallback is empty rather than production', () {
    final shared = File(
      'apple/FocusWidget/PomodoistFocusShared.swift',
    ).readAsStringSync();
    final identifier = shared
        .split('\n')
        .skipWhile(
          (line) => !line.startsWith('let pomodoistFocusAppGroupIdentifier'),
        )
        .take(2)
        .join('\n');

    expect(identifier, contains('"PomodoistAppGroup"'));
    expect(
      identifier,
      isNot(contains('group.com.pomodoist')),
      reason:
          'a build that cannot resolve the key must fall back to .standard, '
          'not to another flavor\'s container',
    );
  });

  test('the app group is only claimed where the flavor declares it', () {
    // Local debug configurations sign without an App Group so they build on a
    // machine whose account has not registered the flavor's group yet. The
    // widget is sandboxed and stays group-free there.
    final local = File(
      'macos/Runner/LocalDebug.entitlements',
    ).readAsStringSync();
    expect(local, isNot(contains('application-groups')));
    expect(local, contains('com.apple.security.app-sandbox'));

    for (final path in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
      'macos/PomodoistFocusWidget/PomodoistFocusWidget.entitlements',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains(r'<string>$(POMODOIST_APP_GROUP)</string>'),
        reason: '$path must take the group from the configuration',
      );
    }
  });

  test('each macOS configuration selects the entitlements it can be signed '
      'with', () {
    // `flutter build macos --flavor X --debug` resolves "Debug-X"; every other
    // mode resolves "Release-X" or "Profile-X", which ship the way the flavor
    // ships. A configuration that asks for the App Group needs a profile for an
    // explicit App ID, and Xcode cannot mint one for a flavor whose App ID is
    // not on the account yet. Only the local debug configurations therefore
    // point at a group-free file, which keeps local flavors buildable without
    // weakening the released ones.
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final entitlements = _entitlementsByConfiguration(project);

    expect(entitlements, isNotEmpty, reason: 'no build settings were parsed');

    const groupFree = {
      'Runner': 'Runner/LocalDebug.entitlements',
      'PomodoistFocusWidgetExtension':
          'PomodoistFocusWidget/LocalDebug.entitlements',
    };

    for (final flavor in ['Development', 'Staging', 'Production']) {
      for (final target in groupFree.keys) {
        expect(
          entitlements['Debug-$flavor']?[target],
          groupFree[target],
          reason: 'Debug-$flavor/$target must build without an App Group',
        );
      }
    }

    // Release and Profile ship the way the flavor ships, so they claim the
    // group: each flavor's container stays its own and a released build cannot
    // read another flavor's snapshot.
    const withGroup = {
      ('Release', 'Runner'): 'Runner/Release.entitlements',
      ('Profile', 'Runner'): 'Runner/DebugProfile.entitlements',
      ('Release', 'PomodoistFocusWidgetExtension'):
          'PomodoistFocusWidget/PomodoistFocusWidget.entitlements',
      ('Profile', 'PomodoistFocusWidgetExtension'):
          'PomodoistFocusWidget/PomodoistFocusWidget.entitlements',
    };
    for (final entry in withGroup.entries) {
      final (mode, target) = entry.key;
      for (final flavor in ['Development', 'Staging', 'Production']) {
        expect(
          entitlements['$mode-$flavor']?[target],
          entry.value,
          reason: '$mode-$flavor/$target must claim the flavor App Group',
        );
      }
    }
  });

  test('macOS build modes preserve each flavor identity', () {
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final configurations = _identityByConfiguration(project);
    for (final flavor in AppFlavor.values) {
      final name = '${flavor.name[0].toUpperCase()}${flavor.name.substring(1)}';
      for (final mode in ['Debug', 'Profile', 'Release', 'Release-Direct']) {
        final configuration = '$mode-$name';
        final identity = configurations[configuration]!;
        final expected = {
          'Runner': flavor.applicationId,
          'RunnerTests': flavor.runnerTestsBundleId,
          'PomodoistFocusWidgetExtension': flavor.focusWidgetBundleId,
        };
        for (final entry in expected.entries) {
          expect(
            identity[entry.key]?['PRODUCT_BUNDLE_IDENTIFIER'],
            entry.value,
            reason: '$configuration/${entry.key}',
          );
        }
        expect(
          identity['Runner']?['POMODOIST_BUILD_BUNDLE_ID'],
          flavor.applicationId,
          reason: '$configuration signing must use the flavor identity',
        );
        if (mode != 'Release-Direct') {
          for (final target in ['Runner', 'PomodoistFocusWidgetExtension']) {
            expect(
              identity[target]?['POMODOIST_APP_GROUP'],
              flavor.appGroup,
              reason: '$configuration/$target',
            );
          }
        }
        expect(
          identity['Runner']?['POMODOIST_DISPLAY_NAME'],
          flavor.displayName,
        );
        expect(
          identity['Runner']?['ASSETCATALOG_COMPILER_APPICON_NAME'],
          flavor.isProduction ? 'AppIcon' : 'AppIcon-$name',
        );
      }
    }
  });
}

Map<String, Map<String, Map<String, String>>> _identityByConfiguration(
  String project,
) {
  final configurations = <String, Map<String, Map<String, String>>>{};
  var settings = <String, String>{};

  for (final rawLine in project.split('\n')) {
    final line = rawLine.trim();
    final setting = RegExp(r'^([A-Z][A-Z0-9_]*) = (.*);$').firstMatch(line);
    if (setting != null) {
      settings[setting.group(1)!] = setting.group(2)!.replaceAll('"', '');
      continue;
    }
    if (!line.startsWith('name = ')) continue;

    final bundleId = settings['PRODUCT_BUNDLE_IDENTIFIER'];
    if (bundleId != null) {
      final target = bundleId.contains('focuswidget')
          ? 'PomodoistFocusWidgetExtension'
          : bundleId.contains('RunnerTests')
          ? 'RunnerTests'
          : 'Runner';
      final name = _setting(line, 'name = ');
      configurations.putIfAbsent(name, () => {})[target] = settings;
    }
    settings = <String, String>{};
  }
  return configurations;
}

/// Maps each macOS build configuration name to its per-target
/// `CODE_SIGN_ENTITLEMENTS`, read straight out of the project file.
///
/// A configuration block is a run of `key = value;` settings closed by
/// `name = "<configuration>";`. The setting that identifies the target is the
/// bundle identifier: the widget appends `.focuswidget`, and the app is the
/// only target left.
Map<String, Map<String, String>> _entitlementsByConfiguration(String project) {
  final configurations = <String, Map<String, String>>{};
  String? entitlements;
  String? target;

  for (final rawLine in project.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('CODE_SIGN_ENTITLEMENTS = ')) {
      entitlements = _setting(line, 'CODE_SIGN_ENTITLEMENTS = ');
    } else if (line.startsWith('PRODUCT_BUNDLE_IDENTIFIER = ')) {
      final bundleId = _setting(line, 'PRODUCT_BUNDLE_IDENTIFIER = ');
      target = bundleId.contains('focuswidget')
          ? 'PomodoistFocusWidgetExtension'
          : 'Runner';
    } else if (line.startsWith('name = ')) {
      final name = _setting(line, 'name = ');
      // Project-level configurations carry no bundle identifier; they are not
      // what Xcode signs with, so they are skipped.
      if (entitlements != null && target != null) {
        configurations.putIfAbsent(name, () => {})[target] = entitlements;
      }
      entitlements = null;
      target = null;
    }
  }
  return configurations;
}

String _setting(String line, String prefix) => line
    .substring(prefix.length)
    .replaceAll(';', '')
    .replaceAll('"', '')
    .trim();
