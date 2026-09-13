import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/theme_image_preparation.dart';

void main() {
  test(
    'rejects empty, oversized and undecodable input before returning image data',
    () async {
      await expectLater(prepareThemeImage(Uint8List(0)), throwsFormatException);
      await expectLater(
        prepareThemeImage(Uint8List(50 * 1024 * 1024 + 1)),
        throwsA(isA<ThemeImageTooLargeException>()),
      );
      await expectLater(
        prepareThemeImage(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    },
  );

  test(
    'normalization preserves aspect ratio, caps the longest side and never upscales',
    () async {
      for (final (width, height, expectedWidth, expectedHeight) in [
        (3000, 1500, 2560, 1280),
        (1500, 3000, 1280, 2560),
        (3000, 1, 2560, 1),
        (3, 5, 3, 5),
      ]) {
        final output = await prepareThemeImage(await _png(width, height));
        expect(output.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(output);
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, expectedWidth);
          expect(frame.image.height, expectedHeight);
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      }
    },
  );

  test(
    'animated input becomes a PNG containing only the first frame',
    () async {
      // A 1 x 1 GIF with a red first frame and a blue second frame.
      final gif = Uint8List.fromList([
        71,
        73,
        70,
        56,
        57,
        97,
        1,
        0,
        1,
        0,
        128,
        0,
        0,
        255,
        0,
        0,
        0,
        0,
        255,
        33,
        249,
        4,
        0,
        10,
        0,
        0,
        0,
        44,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        2,
        2,
        68,
        1,
        0,
        33,
        249,
        4,
        0,
        10,
        0,
        0,
        0,
        44,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        2,
        2,
        76,
        1,
        0,
        59,
      ]);
      final output = await prepareThemeImage(gif);
      expect(output.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(output);
      final frame = await codec.getNextFrame();
      try {
        expect(codec.frameCount, 1);
        expect((await frame.image.toByteData())!.buffer.asUint8List(), [
          255,
          0,
          0,
          255,
        ]);
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF123456), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
