import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/screen_retriever/display.dart';

void main() {
  group('Display', () {
    test('fromJson parses full display payload', () {
      final display = Display.fromJson({
        'id': 'screen-1',
        'name': 'Built-in',
        'size': {'width': 1920.0, 'height': 1080.0},
        'visiblePosition': {'dx': 0.0, 'dy': 100.0},
        'visibleSize': {'width': 1920.0, 'height': 980.0},
        'scaleFactor': 2.0,
      });

      expect(display.id, 'screen-1');
      expect(display.name, 'Built-in');
      expect(display.size, const Size(1920, 1080));
      expect(display.visiblePosition, const Offset(0, 100));
      expect(display.visibleSize, const Size(1920, 980));
      expect(display.scaleFactor, 2.0);
    });

    test('fromJson handles missing optional fields', () {
      final display = Display.fromJson({
        'id': 'screen-2',
        'size': {'width': 800.0, 'height': 600.0},
      });

      expect(display.name, isNull);
      expect(display.visiblePosition, isNull);
      expect(display.visibleSize, isNull);
      expect(display.scaleFactor, isNull);
    });
  });
}
