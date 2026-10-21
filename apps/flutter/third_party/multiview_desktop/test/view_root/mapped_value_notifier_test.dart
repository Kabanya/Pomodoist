import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/utils/mapped_value_notifier.dart';

void main() {
  group('MappedValueNotifier', () {
    test('transforms source updates', () {
      final source = ValueNotifier(2);
      final mapped = MappedValueNotifier<int, String>(
        source: source,
        transform: (v) => 'value-$v',
      );

      expect(mapped.value, 'value-2');

      source.value = 5;
      expect(mapped.value, 'value-5');

      mapped.dispose();
      source.dispose();
    });

    test('stops listening after dispose', () {
      final source = ValueNotifier(1);
      final mapped = MappedValueNotifier<int, int>(
        source: source,
        transform: (v) => v * 10,
      );

      mapped.dispose();
      source.value = 9;
      expect(mapped.value, 10);
      source.dispose();
    });
  });
}
