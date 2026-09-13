import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS voice input privacy descriptions are present', () async {
    final infoPlist = File('macos/Runner/Info.plist');
    final contents = await infoPlist.readAsString();

    expect(_plistString(contents, 'NSMicrophoneUsageDescription'), isNotEmpty);
    expect(
      _plistString(contents, 'NSSpeechRecognitionUsageDescription'),
      isNotEmpty,
    );
  });
}

String _plistString(String contents, String key) {
  final pattern = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
  );
  return pattern.firstMatch(contents)?.group(1)?.trim() ?? '';
}
