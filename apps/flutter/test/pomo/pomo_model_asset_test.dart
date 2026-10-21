import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/pomo/models/pomo_model_asset.dart';

void main() {
  test('model decoding restores every byte', () {
    final original = Uint8List(24);
    final header = ByteData.sublistView(original);
    header.setUint32(0, 0x46546c67, Endian.little);
    header.setUint32(4, 2, Endian.little);
    header.setUint32(8, original.length, Endian.little);
    original[23] = 127;
    expect(
      decodePomoModel(Uint8List.fromList(gzip.encode(original))),
      original,
    );
  });

  test('corrupt gzip and invalid GLB are rejected for the still fallback', () {
    expect(() => decodePomoModel(Uint8List(4)), throwsA(isA<Exception>()));
    expect(
      () => decodePomoModel(Uint8List.fromList(gzip.encode([1, 2, 3]))),
      throwsFormatException,
    );
    expect(
      () => decodePomoModel(Uint8List.fromList(gzip.encode(Uint8List(24)))),
      throwsFormatException,
    );
  });
}
