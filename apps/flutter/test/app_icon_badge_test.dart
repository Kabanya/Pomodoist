import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  for (final flavor in ['development', 'staging']) {
    test('$flavor badge is centered, styled and clear of rounded corners', () {
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
        inInclusiveRange(icon.width * 0.55, icon.width * 0.65),
        reason: 'The badge must be four times its original width',
      );
      expect(
        bottom - top,
        inInclusiveRange(icon.height * 0.20, icon.height * 0.25),
        reason: 'The badge must be four times its original height',
      );
      for (final x in [left + 8, right - 8]) {
        for (final y in [top + 8, bottom - 8]) {
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
          if (isText) {
            textPixels++;
            textLeft = math.min(textLeft, x);
            textRight = math.max(textRight, x);
            textTop = math.min(textTop, y);
            textBottom = math.max(textBottom, y);
          }
        }
      }
      expect(clipped, 0, reason: 'Rounded corners must not cut into the badge');
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
    });
  }
}
