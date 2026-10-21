import 'dart:convert';
import 'dart:typed_data';

/// Facial and arm-volume curves used while Filament blends the skeleton.
class PomoMorphClips {
  PomoMorphClips(ByteData bytes) {
    final jsonLength = bytes.getUint32(12, Endian.little);
    final gltf =
        jsonDecode(
              utf8.decode(
                bytes.buffer.asUint8List(bytes.offsetInBytes + 20, jsonLength),
              ),
            )
            as Map<String, dynamic>;
    final binaryOffset = 28 + jsonLength;
    List<double> read(int index) {
      final accessor = gltf['accessors'][index] as Map<String, dynamic>;
      if (accessor['componentType'] != 5126 ||
          accessor['type'] != 'SCALAR' ||
          accessor.containsKey('sparse')) {
        throw const FormatException(
          'Pomo morph curves must be dense float scalars',
        );
      }
      final view =
          gltf['bufferViews'][accessor['bufferView']] as Map<String, dynamic>;
      final offset =
          binaryOffset +
          (view['byteOffset'] as int? ?? 0) +
          (accessor['byteOffset'] as int? ?? 0);
      return List.generate(
        accessor['count'] as int,
        (i) => bytes.getFloat32(offset + i * 4, Endian.little),
      );
    }

    for (final dynamic animation in gltf['animations']) {
      final curves = <String, _Curve>{};
      for (final dynamic channel in animation['channels']) {
        if (channel['target']['path'] != 'weights') continue;
        final node = gltf['nodes'][channel['target']['node']];
        final sampler = animation['samplers'][channel['sampler']];
        if (sampler['interpolation'] != 'LINEAR') {
          throw const FormatException(
            'Pomo morph curves must use linear interpolation',
          );
        }
        final times = read(sampler['input'] as int);
        final weights = read(sampler['output'] as int);
        if (times.isEmpty || weights.length % times.length != 0) {
          throw const FormatException('Invalid Pomo morph curve');
        }
        curves[node['name'] as String] = _Curve(times, weights);
      }
      _clips[animation['name'] as String] = curves;
    }
  }

  final _clips = <String, Map<String, _Curve>>{};

  Map<String, List<double>> sample(
    String clip,
    double seconds, {
    required bool loop,
  }) => {
    for (final entry in _clips[clip]!.entries)
      entry.key: entry.value.sample(
        loop ? seconds % entry.value.times.last : seconds,
      ),
  };

  static Map<String, List<double>> blend(
    Map<String, List<double>> from,
    Map<String, List<double>> to,
    double alpha,
  ) => {
    for (final entry in to.entries)
      entry.key: List.generate(
        entry.value.length,
        (i) => from[entry.key]![i] * (1 - alpha) + entry.value[i] * alpha,
      ),
  };
}

class _Curve {
  _Curve(this.times, this.weights);
  final List<double> times;
  final List<double> weights;

  List<double> sample(double seconds) {
    final count = weights.length ~/ times.length;
    final next = times.indexWhere((time) => time >= seconds);
    final end = next < 0 ? times.length - 1 : next;
    final start = end == 0 ? 0 : end - 1;
    final alpha = end == start
        ? 0.0
        : ((seconds - times[start]) / (times[end] - times[start])).clamp(
            0.0,
            1.0,
          );
    return List.generate(
      count,
      (i) =>
          weights[start * count + i] * (1 - alpha) +
          weights[end * count + i] * alpha,
    );
  }
}
