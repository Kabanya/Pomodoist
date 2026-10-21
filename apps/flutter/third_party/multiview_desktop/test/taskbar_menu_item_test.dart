import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TaskbarMenuItem', () {
    test('toJson encodes id and title without iconAsset', () async {
      const item = TaskbarMenuItem(title: 'Open new window');

      final json = await item.toJson(0);

      expect(json['id'], 0);
      expect(json['title'], 'Open new window');
      expect(json.containsKey('icon'), isFalse);
    });

    test('toJson uses list index as native id', () async {
      const item = TaskbarMenuItem(title: 'Second item');

      final json = await item.toJson(2);

      expect(json['id'], 2);
      expect(json['title'], 'Second item');
    });

    test('toJson embeds icon as base64 when iconAsset is set', () async {
      const assetPath = 'test/fixtures/plus.png';
      const item = TaskbarMenuItem(
        title: 'Open new window',
        iconAsset: assetPath,
      );

      final expectedBytes = (await rootBundle.load(assetPath))
          .buffer
          .asUint8List();

      final json = await item.toJson(0);

      expect(json['id'], 0);
      expect(json['title'], 'Open new window');
      expect(json['icon'], isA<String>());
      expect(base64Decode(json['icon'] as String), expectedBytes);
    });

    test('onPressed is not included in native payload', () async {
      var pressed = false;
      final item = TaskbarMenuItem(
        title: 'Action',
        onPressed: () => pressed = true,
      );

      final json = await item.toJson(0);

      expect(json.keys, containsAll(['id', 'title']));
      expect(json.containsKey('onPressed'), isFalse);
      expect(pressed, isFalse);
    });
  });
}
