import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'all sound families ship complete PCM audio assets with smooth boundaries',
    () {
      final pubspec =
          loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
      final registered = (pubspec['flutter']['assets'] as YamlList)
          .whereType<String>();
      for (final family in ['soft_kalimba', 'neon_pulse', 'orbit_bloom']) {
        for (final cue in ['start', 'pause', 'resume', 'complete']) {
          final path = 'assets/sounds/$family/focus_$cue.wav';
          expect(
            registered.any(
              (entry) => entry == path || entry == 'assets/sounds/$family/',
            ),
            isTrue,
            reason: '$path must be bundled',
          );
          final bytes = File(path).readAsBytesSync();
          final data = ByteData.sublistView(bytes);
          expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
          expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
          expect(data.getUint16(20, Endian.little), 1);
          expect(data.getUint16(22, Endian.little), 2);
          expect(data.getUint32(24, Endian.little), 44100);
          expect(data.getUint16(34, Endian.little), 16);
          expect(data.getUint32(40, Endian.little), bytes.length - 44);
          expect(bytes.length, greaterThan(44));
          for (final offset in [44, 46, bytes.length - 4, bytes.length - 2]) {
            expect(
              data.getInt16(offset, Endian.little),
              0,
              reason: '$path has silent boundaries',
            );
          }
          var peak = 0;
          for (var offset = 44; offset < bytes.length; offset += 2) {
            final value = data.getInt16(offset, Endian.little).abs();
            if (value > peak) peak = value;
          }
          expect(
            peak,
            inInclusiveRange(1, 13046),
            reason: '$path must retain headroom',
          );
        }
      }
    },
  );
}
