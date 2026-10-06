import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/widgets/task_details_host.dart';

void main() {
  test(
    'side panels preserve the background responsive width during resizing',
    () {
      for (final (hostWidth, contentWidth, expectedWidth) in [
        (819.0, 819.0, 819.0),
        (820.0, 820.0, 820.0),
        (959.0, 959.0, 959.0),
        (960.0, 520.0, 960.0),
        (1059.0, 619.0, 1059.0),
        (1060.0, 620.0, 1060.0),
        (1500.0, 1060.0, 1500.0),
      ]) {
        final viewport = DetailsPanelViewport(
          width: hostWidth,
          child: const SizedBox.shrink(),
        );
        expect(
          viewport.backgroundLayoutWidth(contentWidth),
          expectedWidth,
          reason: 'Host width $hostWidth, visible content width $contentWidth',
        );
      }
      const viewport = DetailsPanelViewport(
        width: 1060,
        child: SizedBox.shrink(),
      );
      for (final width in [1060.0, 840.0, 620.0, 840.0, 1060.0]) {
        expect(viewport.backgroundLayoutWidth(width), 1060);
      }
    },
  );

  test('fullscreen panels retain the actual background layout width', () {
    const viewport = DetailsPanelViewport(width: 959, child: SizedBox.shrink());
    expect(viewport.sideBySide, isFalse);
    expect(viewport.backgroundLayoutWidth(800), 800);
  });
}
