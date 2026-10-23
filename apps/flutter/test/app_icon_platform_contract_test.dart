import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'every Runner configuration includes its classic icon, Watch does not',
    () {
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final settings = RegExp(
        r'buildSettings = \{(.*?)\n\s*\};',
        dotAll: true,
      ).allMatches(project);
      var runners = 0;
      for (final block in settings) {
        final text = block.group(1)!;
        final primary = RegExp(
          r'ASSETCATALOG_COMPILER_APPICON_NAME = ([^;]+);',
        ).firstMatch(text)?.group(1)?.replaceAll('"', '');
        if (primary == null) continue;
        if (text.contains('PomodoistWatch/Info.plist')) {
          expect(text, isNot(contains('ALTERNATE_APPICON_NAMES')));
        } else {
          runners++;
          expect(
            text,
            contains(
              'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "$primary-Classic";',
            ),
          );
          final directory = Directory(
            'ios/Runner/Assets.xcassets/$primary-Classic.appiconset',
          );
          final manifest =
              jsonDecode(
                    File('${directory.path}/Contents.json').readAsStringSync(),
                  )
                  as Map;
          for (final slot in manifest['images'] as List) {
            expect(
              File('${directory.path}/${slot['filename']}').existsSync(),
              isTrue,
            );
          }
        }
      }
      expect(runners, greaterThan(0));
      for (final name in ['Info.plist', 'Info-Local.plist']) {
        expect(
          File('ios/Runner/$name').readAsStringSync(),
          contains(
            '<string>\$(ASSETCATALOG_COMPILER_APPICON_NAME)-Classic</string>',
          ),
        );
      }
    },
  );

  test(
    'Android aliases retain one initial launcher and independent deep links',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = RegExp(
        r'<activity\s.*?</activity>',
        dotAll: true,
      ).firstMatch(manifest)!.group(0)!;
      expect(activity, contains('android:exported="true"'));
      expect(activity, isNot(contains('android.intent.category.LAUNCHER')));
      final aliases = RegExp(
        r'<activity-alias\s.*?</activity-alias>',
        dotAll: true,
      ).allMatches(manifest).map((m) => m.group(0)!).toList();
      expect(aliases, hasLength(2));
      expect(
        aliases.where((alias) => alias.contains('android:enabled="true"')),
        hasLength(1),
      );
      for (final alias in aliases) {
        expect(alias, contains('android:targetActivity=".MainActivity"'));
        expect(alias, contains('android.intent.category.LAUNCHER'));
        expect(alias, contains('android:exported="true"'));
      }
      for (final flavor in ['production', 'development', 'staging']) {
        final linkManifest = File(
          'android/app/src/$flavor/AndroidManifest.xml',
        ).readAsStringSync();
        expect(
          linkManifest,
          contains('<activity android:name=".MainActivity">'),
        );
        expect(linkManifest, contains('android:host="login-callback"'));
        expect(linkManifest, contains('android:host="focus"'));
        for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
          expect(
            File(
              'android/app/src/$flavor/res/mipmap-$density/ic_launcher_classic.png',
            ).existsSync(),
            isTrue,
          );
        }
      }
    },
  );

  test('both runtime choices are bundled separately for every flavor', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = loadYaml(pubspec)['flutter']['assets'] as YamlList;
    for (final flavor in ['production', 'development', 'staging']) {
      final directory = 'assets/branding/app_icons/generated/$flavor';
      for (final icon in ['icon-light-pomo', 'classic']) {
        expect(pubspec, contains('- $directory/$icon.png'));
        final macos = assets.whereType<YamlMap>().singleWhere(
          (asset) => asset['path'] == '$directory/$icon-macos.png',
        );
        expect(macos['platforms'], ['macos']);
        expect(
          macos['flavors'],
          containsAll([
            flavor,
            '${flavor[0].toUpperCase()}${flavor.substring(1)}',
          ]),
        );
        expect(pubspec, contains('path: $directory/$icon.ico'));
        for (final suffix in ['.png', '-macos.png', '.ico']) {
          expect(File('$directory/$icon$suffix').lengthSync(), greaterThan(0));
        }
      }
    }
  });
}
