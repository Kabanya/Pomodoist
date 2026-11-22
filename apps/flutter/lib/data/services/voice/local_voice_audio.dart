import 'dart:math' as math;
import 'dart:typed_data';

/// Converts the recorder's signed little-endian 16-bit mono PCM to model input.
List<Float32List> localVoiceSegments(Uint8List pcm, int rate) {
  final bytes = ByteData.sublistView(pcm);
  final samples = Float32List(bytes.lengthInBytes ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = bytes.getInt16(i * 2, Endian.little) / 32768;
  }
  return _splitAtQuietFrames(samples, rate);
}

/// Whisper has a 30-second input window. Prefer a quiet 20 ms frame near
/// the end of each window and leave room for the model's internal padding.
List<Float32List> _splitAtQuietFrames(Float32List samples, int rate) {
  final window = rate * 25;
  final frame = rate ~/ 50;
  final segments = <Float32List>[];
  var start = 0;
  while (start < samples.length) {
    final limit = math.min(start + window, samples.length);
    var end = limit;
    if (limit < samples.length) {
      var minEnergy = double.infinity;
      for (var i = limit - rate * 2; i + frame <= limit; i += frame) {
        var energy = 0.0;
        for (var j = i; j < i + frame; j++) {
          energy += samples[j] * samples[j];
        }
        if (energy <= minEnergy) {
          minEnergy = energy;
          end = i + frame ~/ 2;
        }
      }
    }
    final segment = Float32List.sublistView(samples, start, end);
    if (segment.any((sample) => sample.abs() > .003)) segments.add(segment);
    start = end;
  }
  return segments;
}
