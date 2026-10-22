import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_texture_surface.dart';

void main() {
  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('native texture orientation on ${platform.name}', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 10,
                height: 10,
                child: PomoTextureSurface(
                  child: Column(
                    children: const [
                      Expanded(
                        child: ColoredBox(
                          color: Color(0xffff0000),
                          child: SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: Color(0xff0000ff),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        // Linux GL textures arrive bottom-up; the Flutter surface must swap rows.
        final top = bytes.getUint32((2 * 10 + 5) * 4);
        final bottom = bytes.getUint32((7 * 10 + 5) * 4);
        expect(top, platform == TargetPlatform.linux ? 0x0000ffff : 0xff0000ff);
        expect(
          bottom,
          platform == TargetPlatform.linux ? 0xff0000ff : 0x0000ffff,
        );
        image.dispose();
      });
    }, variant: TargetPlatformVariant({platform}));
  }
}
