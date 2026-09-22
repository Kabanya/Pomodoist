import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

/// The iOS project resolves every flavor identity from real Xcode build
/// configurations. The `Development` scheme selects `Debug-Development`,
/// `Release-Development` and `Profile-Development`; the two non-production
/// flavors therefore need those nine blocks in the project file, and production
/// needs none because the `Production` scheme already selects the plain
/// `Debug`/`Release`/`Profile`. `make ios-flavor-settings` prints what Xcode
/// resolves for each target, which is how these expectations were confirmed.
///
/// A flavor whose configuration is missing does not fail loudly: Xcode falls
/// back to the base configuration of the same mode, and the build ships
/// production's bundle identifier, App Group and display name. These tests
/// exist so that fallback cannot happen unnoticed.
void main() {
  final project = _IosProject.parse(
    File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
  );

  // The configurations a flavor builds through, in the order the schemes use
  // them. Production is the base configuration itself.
  const flavored = <String, List<String>>{
    'Development': [
      'Debug-Development',
      'Release-Development',
      'Profile-Development',
    ],
    'Staging': ['Debug-Staging', 'Release-Staging', 'Profile-Staging'],
  };

  group('ios/Runner.xcodeproj flavor configurations', () {
    test('every target declares both non-production flavors', () {
      for (final entry in flavored.entries) {
        for (final name in entry.value) {
          for (final target in _targets) {
            expect(
              project.buildSettings(name, target),
              isNotNull,
              reason: '$target must have a $name configuration',
            );
          }
        }
      }
    });

    test('the app carries the flavor identity', () {
      for (final entry in flavored.entries) {
        final flavor = _flavor(entry.key);
        for (final name in entry.value) {
          final settings = project.buildSettings(name, 'Runner')!;
          expect(
            settings['PRODUCT_BUNDLE_IDENTIFIER'],
            _nativeFlavor(name, flavor).applicationId,
            reason: '$name/Runner',
          );
          // The built `.app` is named after `PRODUCT_NAME` — which is what the
          // `TEST_HOST` of the runner tests points at — while the name the user
          // sees comes from `CFBundleDisplayName`, which both Info.plists
          // expand from `POMODOIST_DISPLAY_NAME`.
          expect(
            settings['PRODUCT_NAME'],
            contains(flavor.displayName),
            reason: '$name/Runner',
          );
        }
      }
    });

    test('the app group, url scheme and display name follow the flavor', () {
      for (final entry in flavored.entries) {
        final flavor = _flavor(entry.key);
        for (final name in entry.value) {
          final nativeFlavor = _nativeFlavor(name, flavor);
          // The project-level configuration and the app target both carry the
          // identity, because the watch and widget targets inherit the group
          // from the configuration they are built with.
          for (final target in ['Project', 'Runner']) {
            final settings = project.buildSettings(name, target)!;
            expect(
              settings['POMODOIST_APP_GROUP'],
              nativeFlavor.appGroup,
              reason: '$name/$target',
            );
            expect(
              settings['POMODOIST_URL_SCHEME'],
              contains(flavor.urlScheme),
              reason: '$name/$target',
            );
            expect(
              settings['POMODOIST_DISPLAY_NAME'],
              contains(flavor.displayName),
              reason: '$name/$target',
            );
          }
        }
      }
    });

    test('the embedded targets carry their own bundle identifiers', () {
      for (final entry in flavored.entries) {
        final flavor = _flavor(entry.key);
        for (final name in entry.value) {
          final nativeFlavor = _nativeFlavor(name, flavor);
          final expected = {
            'Runner': nativeFlavor.applicationId,
            'RunnerTests': nativeFlavor.runnerTestsBundleId,
            'Watch': nativeFlavor.watchBundleId,
            'WatchTests': nativeFlavor.watchTestsBundleId,
            'Widget': nativeFlavor.focusWidgetBundleId,
          };
          for (final target in _targets) {
            expect(
              project.buildSettings(name, target)!['PRODUCT_BUNDLE_IDENTIFIER'],
              expected[target],
              reason: '$name/$target',
            );
          }
        }
      }
    });

    test('the flavor icon is selected', () {
      // Without this the app icon falls back to the asset catalog's default,
      // so the three builds would be indistinguishable on the home screen.
      // Both the app and the watch app carry a per-flavor appiconset; the
      // widget and the test bundles are not icons.
      for (final entry in flavored.entries) {
        final icon = 'AppIcon-${entry.key}';
        for (final name in entry.value) {
          for (final target in ['Runner', 'Watch']) {
            expect(
              project.buildSettings(
                name,
                target,
              )!['ASSETCATALOG_COMPILER_APPICON_NAME'],
              icon,
              reason: '$name/$target',
            );
          }
        }
      }
    });

    test('signs with the entitlements of the flavor', () {
      // Every iOS configuration resolves `$(POMODOIST_APP_GROUP)` from its own
      // build settings, so the app, the watch app and the widget all claim
      // their flavor's group. There is no group-free configuration on iOS.
      const entitlements = {
        'Runner': 'Runner/Runner.entitlements',
        'Watch': 'PomodoistWatch/PomodoistWatch.entitlements',
        'Widget': 'PomodoistFocusWidget/PomodoistFocusWidget.entitlements',
      };
      for (final entry in flavored.entries) {
        for (final name in entry.value) {
          for (final target in entitlements.keys) {
            expect(
              project.buildSettings(name, target)!['CODE_SIGN_ENTITLEMENTS'],
              entitlements[target],
              reason: '$name/$target',
            );
          }
        }
      }
    });

    test('keeps the test hosts pointing at the flavor app', () {
      // `TEST_HOST` names the built `.app` directory, which is `PRODUCT_NAME`.
      for (final entry in flavored.entries) {
        final flavor = _flavor(entry.key);
        for (final name in entry.value) {
          expect(
            project.buildSettings(name, 'RunnerTests')!['TEST_HOST'],
            contains('${flavor.displayName}.app/'),
            reason: '$name/RunnerTests',
          );
        }
      }
    });

    test('only staging TestFlight reuses the production App Store identity', () {
      // Debug/Profile flavors install side by side. Release-Staging is the one
      // exception: it is uploaded as another build of the existing production
      // App Store Connect app, while retaining staging runtime configuration,
      // display name and icon.
      for (final entry in flavored.entries) {
        final flavor = _flavor(entry.key);
        for (final name in entry.value) {
          final applicationId = _nativeFlavor(name, flavor).applicationId;
          for (final target in _targets) {
            final bundleId = project.buildSettings(
              name,
              target,
            )!['PRODUCT_BUNDLE_IDENTIFIER'];
            if (bundleId == null) {
              continue;
            }
            expect(
              bundleId == applicationId ||
                  bundleId.startsWith('$applicationId.'),
              isTrue,
              reason: '$name/$target claims another flavor\'s bundle id',
            );
          }
        }
      }
    });

    test('the production configurations keep production identity', () {
      // Production deliberately uses the base configurations. They still need
      // the shared identity values because every production Info.plist and
      // entitlement expands them at build time.
      for (final name in ['Debug', 'Release', 'Profile']) {
        expect(
          project.buildSettings(name, 'Runner')!['PRODUCT_BUNDLE_IDENTIFIER'],
          AppFlavor.production.applicationId,
          reason: '$name/Runner',
        );
        expect(
          project.buildSettings(name, 'Project')!['POMODOIST_APP_GROUP'],
          AppFlavor.production.appGroup,
          reason: '$name/Project',
        );
        expect(
          project.buildSettings(name, 'Project')!['POMODOIST_DISPLAY_NAME'],
          AppFlavor.production.displayName,
          reason: '$name/Project',
        );
        expect(
          project.buildSettings(name, 'Project')!['POMODOIST_URL_SCHEME'],
          AppFlavor.production.urlScheme,
          reason: '$name/Project',
        );
      }
    });
  });

  group('ios/Runner.xcodeproj schemes', () {
    test('each flavor has exactly one shared scheme', () {
      // Flutter resolves `--flavor X` to a scheme by capitalizing X, so a
      // second scheme whose name capitalizes the same way would make the choice
      // ambiguous, and a missing one would leave the CLI with no flavor at all.
      final schemes = Directory('ios/Runner.xcodeproj/xcshareddata/xcschemes')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.xcscheme'))
          .map((name) => name.substring(0, name.length - '.xcscheme'.length))
          .toList();
      for (final flavor in AppFlavor.values) {
        final capitalized =
            '${flavor.name[0].toUpperCase()}'
            '${flavor.name.substring(1)}';
        expect(schemes.where((name) => name.toLowerCase() == flavor.name), [
          capitalized,
        ], reason: 'the scheme Flutter selects for --flavor ${flavor.name}');
      }
    });

    test('each scheme selects its own flavor configurations', () {
      // Flutter passes `--flavor X` to `-scheme X`, so the scheme is the
      // contract the CLI relies on: it must not resolve to a base
      // configuration, which would ship production identity for a flavor.
      final expected = <String, Set<String>>{
        'Development': flavored['Development']!.toSet(),
        'Staging': flavored['Staging']!.toSet(),
        'Production': {'Debug', 'Release', 'Profile'},
      };
      for (final entry in expected.entries) {
        final path =
            'ios/Runner.xcodeproj/xcshareddata/xcschemes/'
            '${entry.key}.xcscheme';
        final scheme = File(path);
        expect(scheme.existsSync(), isTrue, reason: path);
        final resolved = RegExp(r'buildConfiguration = "([^"]+)"')
            .allMatches(scheme.readAsStringSync())
            .map((match) => match.group(1)!)
            .toSet();
        expect(resolved, entry.value, reason: path);
      }
    });
  });
}

/// Every target that carries flavor-valued settings.
const List<String> _targets = [
  'Project',
  'Runner',
  'RunnerTests',
  'Watch',
  'WatchTests',
  'Widget',
];

AppFlavor _flavor(String name) =>
    AppFlavor.values.firstWhere((flavor) => flavor.name == name.toLowerCase());

AppFlavor _nativeFlavor(String configuration, AppFlavor runtimeFlavor) =>
    configuration == 'Release-Staging' ? AppFlavor.production : runtimeFlavor;

/// The build settings of `ios/Runner.xcodeproj`, read straight out of the
/// project file.
///
/// The link between a settings block and its target is the configuration list:
/// each block is declared anonymously — its bundle identifier identifies the
/// target only in production, because the flavor blocks change it — so the
/// owning list is what resolves the target here.
class _IosProject {
  _IosProject._(this._settings);

  factory _IosProject.parse(String project) {
    // Each configuration list names the configuration blocks it owns.
    final targetOfId = <String, String>{};
    for (final list in RegExp(
      r'\t\t\w+ /\* Build configuration list for ([^*]+) \*/ = \{\n'
      r'(.*?)\n\t\t};\n',
      dotAll: true,
    ).allMatches(project)) {
      final owner = _listTarget(list.group(1)!);
      for (final entry in RegExp(
        r'(\w+) /\* [^*]+ \*/',
      ).allMatches(list.group(2)!)) {
        targetOfId[entry.group(1)!] = owner;
      }
    }

    final settings = <String, Map<String, String>>{};
    // A block is delimited by brace depth rather than by a closing-line
    // pattern: `\n\t\t};\n` also occurs inside a block, and a lazy capture that
    // reaches for it can swallow the next block's header.
    final headers = RegExp(
      r'^(\t+)(\w{24}) /\* ([^*]*) \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n',
      multiLine: true,
    );
    for (final header in headers.allMatches(project)) {
      final target = targetOfId[header.group(2)];
      // The header match runs past the opening brace — it captures the `isa`
      // line too — so the brace is located rather than measured.
      final end = _blockEnd(project, project.indexOf('{', header.start));
      final body = project.substring(header.start, end);
      // The blank configurations spell the name unquoted (`name = Debug;`) and
      // the flavored ones quote it.
      final name = RegExp(
        r'name = (?:"([^"]+)"|([A-Za-z_][\w-]*));',
      ).firstMatch(body);
      if (target == null || name == null) {
        continue;
      }
      final values = <String, String>{};
      for (final match in RegExp(
        r'^\t{4}([A-Za-z_][A-Za-z0-9_]*) = (.*);$',
        multiLine: true,
      ).allMatches(body)) {
        values[match.group(1)!] = match.group(2)!;
      }
      settings[_key(name.group(1) ?? name.group(2)!, target)] = values;
    }

    return _IosProject._(settings);
  }

  /// The offset of the `}` that closes the object whose `{` is at [brace].
  static int _blockEnd(String project, int brace) {
    var depth = 0;
    for (var i = brace; i < project.length; i++) {
      final char = project[i];
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    throw StateError('unbalanced braces in the project file');
  }

  final Map<String, Map<String, String>> _settings;

  Map<String, String>? buildSettings(String configuration, String target) =>
      _settings[_key(configuration, target)];

  static String _key(String configuration, String target) =>
      '$configuration\u0000$target';
}

/// The target a configuration list belongs to.
String _listTarget(String header) {
  final name = header.replaceAll(RegExp(r'^PBX\w+ '), '').replaceAll('"', '');
  return switch (name) {
    'Runner' => header.startsWith('PBXProject') ? 'Project' : 'Runner',
    'RunnerTests' => 'RunnerTests',
    'PomodoistWatch' => 'Watch',
    'PomodoistWatchTests' => 'WatchTests',
    'PomodoistFocusWidgetExtension' => 'Widget',
    _ => throw StateError('unknown configuration list owner: $header'),
  };
}
