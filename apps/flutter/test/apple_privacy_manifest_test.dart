import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each Apple executable declares the UserDefaults reasons it uses', () {
    const expected = {
      'ios/Runner/PrivacyInfo.xcprivacy': {'1C8F.1'},
      'ios/PomodoistFocusWidget/PrivacyInfo.xcprivacy': {'1C8F.1'},
      'ios/PomodoistWatch/PrivacyInfo.xcprivacy': {'CA92.1'},
      'macos/Runner/PrivacyInfo.xcprivacy': {'1C8F.1', 'CA92.1'},
    };

    for (final entry in expected.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: '${entry.key} is missing');
      if (!file.existsSync()) continue;

      final userDefaults = RegExp(
        r'<key>NSPrivacyAccessedAPIType</key>\s*'
        r'<string>NSPrivacyAccessedAPICategoryUserDefaults</string>\s*'
        r'<key>NSPrivacyAccessedAPITypeReasons</key>\s*'
        r'<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(file.readAsStringSync());
      expect(
        userDefaults,
        isNotNull,
        reason: '${entry.key} must declare its UserDefaults reason',
      );
      final reasons = RegExp(r'<string>([^<]+)</string>')
          .allMatches(userDefaults!.group(1)!)
          .map((match) => match.group(1)!)
          .toSet();
      expect(reasons, entry.value);
    }
  });

  test('privacy manifests belong to their executable resource phases', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    const expected = {
      '97C146EC1CF9000F007C117D': 'C30000000000000000000001',
      'A10000000000000000000023': 'C30000000000000000000002',
      'B20000000000000000000011': 'C30000000000000000000003',
    };

    for (final entry in expected.entries) {
      final phase = RegExp(
        '${entry.key} /\\* Resources \\*/ = \\{.*?\\n\\t\\t\\};',
        dotAll: true,
      ).firstMatch(project);
      expect(phase, isNotNull, reason: '${entry.key} resources are missing');
      expect(phase!.group(0), contains(entry.value));
    }

    final macosProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final runnerResources = RegExp(
      r'33CC10EB2044A3C60003C045 /\* Resources \*/ = \{.*?\n\t\t\};',
      dotAll: true,
    ).firstMatch(macosProject);
    expect(
      runnerResources,
      isNotNull,
      reason: 'macOS Runner resources are missing',
    );
    expect(
      runnerResources!.group(0),
      contains('PrivacyInfo.xcprivacy in Resources'),
    );
  });
}
