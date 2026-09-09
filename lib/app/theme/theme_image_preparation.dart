import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

const themeImageMaxBytes = 50 * 1024 * 1024;

class ThemeImageTooLargeException implements Exception {
  const ThemeImageTooLargeException();

  @override
  String toString() => 'Theme image exceeds the 50 MB limit';
}

Future<Uint8List> prepareThemeImage(Uint8List bytes) async {
  if (bytes.length > themeImageMaxBytes) {
    throw const ThemeImageTooLargeException();
  }
  if (bytes.isEmpty) throw const FormatException('Empty theme image');
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    if (kIsWeb) {
      // The web decoder owns the buffer and supports intrinsic size callbacks;
      // encoded ImageDescriptor dimensions are unavailable on web.
      final ownedBuffer = buffer;
      buffer = null;
      codec = await ui.instantiateImageCodecWithSize(
        ownedBuffer,
        getTargetSize: _targetSize,
      );
    } else {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = _targetSize(descriptor.width, descriptor.height);
      codec = await descriptor.instantiateCodec(
        targetWidth: size.width,
        targetHeight: size.height,
      );
    }
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('Cannot encode theme image');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } on Exception {
    throw const FormatException('Unsupported or invalid theme image');
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

ui.TargetImageSize _targetSize(int width, int height) {
  final scale = math.min(1.0, 2560 / math.max(width, height));
  return ui.TargetImageSize(
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}
