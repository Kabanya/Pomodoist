import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Pomo bundle contains only model assets and fallback stills', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().where(
      (path) => path.startsWith('assets/pomo/'),
    );
    expect(
      assets,
      unorderedEquals([
        'assets/pomo/manifest.json',
        'assets/pomo/model/manifest.json',
        'assets/pomo/model/pomo.glb.gz',
        for (final emotion in PomoEmotion.values)
          'assets/pomo/${emotion.name}-still.webp',
      ]),
    );
  });

  test('all bundled Pomo assets fit the decimal 10 MB budget', () {
    final size = Directory('assets/pomo')
        .listSync(recursive: true)
        .whereType<File>()
        .fold<int>(0, (total, file) => total + file.lengthSync());
    expect(size, lessThanOrEqualTo(10000000));
    expect(File('assets/pomo/model/pomo.glb').existsSync(), isFalse);
  });

  for (final emotion in PomoEmotion.values) {
    test(
      '${emotion.name} fallback decodes to a visible transparent still',
      () async {
        final bytes = await File(
          'assets/pomo/${emotion.name}-still.webp',
        ).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          expect(codec.frameCount, 1);
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, 384);
            expect(frame.image.height, 384);
            final data = (await frame.image.toByteData())!;
            final pixels = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            var transparent = false;
            var visible = false;
            for (var i = 3; i < pixels.length; i += 4) {
              transparent |= pixels[i] == 0;
              visible |= pixels[i] > 0;
            }
            expect(transparent, isTrue);
            expect(visible, isTrue);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      },
    );
  }
}
