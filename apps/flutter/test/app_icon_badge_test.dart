import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';

import '../tool/generate_app_icons.dart' show renderBuildIcon;

void main() {
  for (final flavor in ['development', 'staging']) {
    test(
      '$flavor environment badge is centered within its rim and unclipped',
      () {
        final icon = img.decodePng(
          File(
            'assets/branding/app_icons/generated/$flavor/icon-light-pomo-macos.png',
          ).readAsBytesSync(),
        )!;
        final isDevelopment = flavor == 'development';
        final background = isDevelopment ? [32, 72, 172] : [255, 202, 72];
        var left = icon.width;
        var right = 0;
        var top = icon.height;
        var bottom = 0;
        for (var y = 0; y < icon.height * 0.4; y++) {
          for (var x = 0; x < icon.width; x++) {
            final pixel = icon.getPixel(x, y);
            if (pixel.a == 255 &&
                (pixel.r - background[0]).abs() < 3 &&
                (pixel.g - background[1]).abs() < 3 &&
                (pixel.b - background[2]).abs() < 3) {
              left = math.min(left, x);
              right = math.max(right, x);
              top = math.min(top, y);
              bottom = math.max(bottom, y);
            }
          }
        }
        expect(
          right - left,
          inInclusiveRange(icon.width * 0.40, icon.width * 0.44),
          reason: 'Leave room for the mode badge on the right',
        );
        expect(
          bottom - top,
          inInclusiveRange(icon.height * 0.14, icon.height * 0.16),
          reason: 'Keep the environment badge above the leaves',
        );
        for (final x in [left + 2, right - 2]) {
          for (final y in [top + 2, bottom - 2]) {
            final corner = icon.getPixel(x, y);
            expect(
              (corner.r - background[0]).abs() +
                  (corner.g - background[1]).abs() +
                  (corner.b - background[2]).abs(),
              greaterThan(20),
              reason: 'Badge corners must follow the rounded silhouette',
            );
          }
        }
        var clipped = 0;
        var textPixels = 0;
        var textLeft = icon.width;
        var textRight = 0;
        var textTop = icon.height;
        var textBottom = 0;
        for (var y = top + 1; y < bottom; y++) {
          for (var x = left + 1; x < right; x++) {
            final pixel = icon.getPixel(x, y);
            if (pixel.a != 255) clipped++;
            final isText = isDevelopment
                ? pixel.r > 220 && pixel.g > 220 && pixel.b > 220
                : pixel.r < 60 && pixel.g < 60 && pixel.b < 60;
            // Ignore artwork visible outside the badge's rounded corners.
            if (isText &&
                x > left + (right - left) * .08 &&
                x < right - (right - left) * .08 &&
                y > top + (bottom - top) * .15 &&
                y < bottom - (bottom - top) * .15) {
              textPixels++;
              textLeft = math.min(textLeft, x);
              textRight = math.max(textRight, x);
              textTop = math.min(textTop, y);
              textBottom = math.max(textBottom, y);
            }
          }
        }
        expect(
          clipped,
          0,
          reason: 'Rounded corners must not cut into the badge',
        );
        expect(
          textPixels,
          greaterThan(800),
          reason: 'Flavor label must be visible',
        );
        expect(
          (textLeft + textRight) / 2,
          closeTo((left + right) / 2, 4),
          reason: 'The visible letters must be horizontally centered',
        );
        expect(
          (textTop + textBottom) / 2,
          closeTo((top + bottom) / 2, 4),
          reason: 'The visible letters must be vertically centered',
        );
      },
    );
  }
  test(
    'Classic mode badges are horizontal, bottom-centered and omitted for production release',
    () {
      final artwork = img.Image(width: 512, height: 512, numChannels: 3);
      img.fill(artwork, color: img.ColorRgb8(240, 32, 32));
      const colors = {
        'debug': [232, 154, 255],
        'profile': [66, 241, 238],
        'release': [180, 255, 104],
      };
      for (final flavor in AppFlavor.values) {
        for (final mode in colors.keys) {
          final icon = renderBuildIcon(
            artwork,
            flavor,
            mode,
            choice: AppIconChoice.classic,
          );
          if (flavor.isProduction && mode == 'release') {
            expect(img.encodePng(icon), img.encodePng(artwork));
            continue;
          }
          final color = colors[mode]!;
          final pixels = icon
              .where(
                (pixel) =>
                    pixel.r == color[0] &&
                    pixel.g == color[1] &&
                    pixel.b == color[2],
              )
              .map((pixel) => (pixel.x, pixel.y))
              .toList();
          expect(pixels.length, greaterThan(15000));
          final left = pixels.map((pixel) => pixel.$1).reduce(math.min);
          final right = pixels.map((pixel) => pixel.$1).reduce(math.max);
          final top = pixels.map((pixel) => pixel.$2).reduce(math.min);
          final bottom = pixels.map((pixel) => pixel.$2).reduce(math.max);
          expect((left + right) / 2, closeTo(255.5, 1));
          expect(right - left, greaterThan((bottom - top) * 3));
          expect(top, greaterThan(380));
          expect(bottom, lessThan(492));
          final oldPosition = icon.getPixel(450, 240);
          expect([oldPosition.r, oldPosition.g, oldPosition.b], [240, 32, 32]);
        }
      }
    },
  );
  test(
    'all nine combinations preserve the artwork and select the correct badges',
    () {
      final artwork = img.Image(width: 512, height: 512, numChannels: 3);
      img.fill(artwork, color: img.ColorRgb8(240, 32, 32));
      const modeColors = {
        'debug': [232, 154, 255],
        'profile': [66, 241, 238],
        'release': [180, 255, 104],
      };
      for (final flavor in AppFlavor.values) {
        for (final mode in modeColors.keys) {
          final icon = renderBuildIcon(artwork, flavor, mode);
          final clean = flavor.isProduction && mode == 'release';
          if (clean) {
            expect(img.encodePng(icon), img.encodePng(artwork));
          } else {
            final expected = modeColors[mode]!;
            final matches = icon
                .where(
                  (pixel) =>
                      pixel.r == expected[0] &&
                      pixel.g == expected[1] &&
                      pixel.b == expected[2],
                )
                .map((pixel) => (pixel.x, pixel.y))
                .toList();
            expect(matches.length, greaterThan(15000), reason: '$flavor/$mode');
            expect(
              matches.every(
                (pixel) => pixel.$1 > 390 && pixel.$2 > 75 && pixel.$2 < 450,
              ),
              isTrue,
            );
            final environment = icon.getPixel(100, 50);
            expect(
              [environment.r, environment.g, environment.b],
              switch (flavor) {
                AppFlavor.development => [32, 72, 172],
                AppFlavor.staging => [255, 202, 72],
                AppFlavor.production => [51, 51, 51],
              },
            );
          }
          // The face area must keep its original pixels in every combination.
          for (var y = 300; y < 500; y += 20) {
            for (var x = 20; x < 380; x += 20) {
              final pixel = icon.getPixel(x, y);
              expect([pixel.r, pixel.g, pixel.b], [240, 32, 32]);
            }
          }
          for (final choice in AppIconChoice.values) {
            expect(
              File(
                '${appIconDirectory(flavor, mode)}/${choice.id}.png',
              ).existsSync(),
              isTrue,
            );
          }
        }
      }
      expect(
        () => renderBuildIcon(artwork, AppFlavor.production, 'invalid'),
        throwsArgumentError,
      );
    },
  );
}
