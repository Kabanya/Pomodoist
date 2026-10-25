import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart';

/// Source curves for native skeletal, facial and arm-volume transitions.
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
    final accessors = <int, Float32List>{};
    Float32List read(int index) => accessors.putIfAbsent(index, () {
      final accessor = gltf['accessors'][index] as Map<String, dynamic>;
      final width = switch (accessor['type']) {
        'SCALAR' => 1,
        'VEC3' => 3,
        'VEC4' => 4,
        _ => throw const FormatException('Unsupported Pomo animation accessor'),
      };
      if (accessor['componentType'] != 5126 || accessor.containsKey('sparse')) {
        throw const FormatException(
          'Pomo animation curves must be dense floats',
        );
      }
      final view =
          gltf['bufferViews'][accessor['bufferView']] as Map<String, dynamic>;
      final offset =
          binaryOffset +
          (view['byteOffset'] as int? ?? 0) +
          (accessor['byteOffset'] as int? ?? 0);
      final values = Float32List((accessor['count'] as int) * width);
      for (var i = 0; i < values.length; i++) {
        values[i] = bytes.getFloat32(
          offset +
              (i ~/ width) * (view['byteStride'] as int? ?? width * 4) +
              (i % width) * 4,
          Endian.little,
        );
      }
      return values;
    });

    for (final dynamic animation in gltf['animations']) {
      final curves = <String, _Curve>{};
      final bones = <String, Map<String, _Curve>>{};
      for (final dynamic channel in animation['channels']) {
        final path = channel['target']['path'] as String;
        final node = gltf['nodes'][channel['target']['node']];
        final sampler = animation['samplers'][channel['sampler']];
        final interpolation = sampler['interpolation'] ?? 'LINEAR';
        if (interpolation != 'LINEAR' && interpolation != 'STEP') {
          throw const FormatException(
            'Pomo curves must use linear or step interpolation',
          );
        }
        final times = read(sampler['input'] as int);
        final weights = read(sampler['output'] as int);
        if (times.isEmpty || weights.length % times.length != 0) {
          throw const FormatException('Invalid Pomo morph curve');
        }
        final curve = _Curve(
          times,
          weights,
          rotation: path == 'rotation',
          step: interpolation == 'STEP',
        );
        final name = node['name'] as String;
        if (path == 'weights') {
          curves[name] = curve;
          if (name.endsWith('-body')) {
            final names =
                gltf['meshes'][node['mesh']]['extras']['targetNames'] as List;
            _blinkIndices[name] = [
              for (var i = 0; i < names.length; i++)
                if (names[i] == 'Blink.L' || names[i] == 'Blink.R') i,
            ];
          }
        } else {
          (bones[name] ??= {})[path] = curve;
        }
      }
      _clips[animation['name'] as String] = curves;
      _bones[animation['name'] as String] = bones;
    }
  }

  final _clips = <String, Map<String, _Curve>>{};
  final _bones = <String, Map<String, Map<String, _Curve>>>{};
  final _blinkIndices = <String, List<int>>{};

  static double transitionBlink(double progress) {
    final alpha = math
        .min((progress - .3) / .12, (.7 - progress) / .12)
        .clamp(0.0, 1.0);
    return alpha * alpha * (3 - 2 * alpha);
  }

  void applyBlink(Map<String, List<double>> pose, double amount) {
    for (final entry in _blinkIndices.entries) {
      for (final index in entry.value) {
        pose[entry.key]![index] = math.max(pose[entry.key]![index], amount);
      }
    }
  }

  Map<String, Matrix4> sampleBones(
    String clip,
    double seconds, {
    required bool loop,
  }) => {
    for (final entry in _bones[clip]!.entries)
      entry.key: Matrix4.compose(
        Vector3.array(entry.value['translation']!.at(seconds, loop)),
        Quaternion.fromFloat64List(
          Float64List.fromList(entry.value['rotation']!.at(seconds, loop)),
        ),
        Vector3.array(entry.value['scale']!.at(seconds, loop)),
      ),
  };

  static Matrix4 blendBone(Matrix4 from, Matrix4 to, double alpha) {
    if (alpha <= 0) return from.clone();
    if (alpha >= 1) return to.clone();
    final fromPosition = Vector3.zero(), toPosition = Vector3.zero();
    final fromRotation = Quaternion.identity(),
        toRotation = Quaternion.identity();
    final fromScale = Vector3.zero(), toScale = Vector3.zero();
    from.decompose(fromPosition, fromRotation, fromScale);
    to.decompose(toPosition, toRotation, toScale);
    return Matrix4.compose(
      fromPosition * (1 - alpha) + toPosition * alpha,
      Quaternion.fromFloat64List(
        Float64List.fromList(
          _slerp(fromRotation.storage, toRotation.storage, alpha),
        ),
      ),
      fromScale * (1 - alpha) + toScale * alpha,
    );
  }

  Map<String, List<double>> sample(
    String clip,
    double seconds, {
    required bool loop,
  }) => {
    for (final entry in _clips[clip]!.entries)
      entry.key: entry.value.at(seconds, loop),
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
  _Curve(this.times, this.weights, {this.rotation = false, this.step = false});
  final Float32List times;
  final Float32List weights;
  final bool rotation;
  final bool step;

  List<double> at(double seconds, bool loop) =>
      sample(loop ? seconds % times.last : seconds);

  List<double> sample(double seconds) {
    final count = weights.length ~/ times.length;
    final next = times.indexWhere((time) => time >= seconds);
    final end = next < 0 ? times.length - 1 : next;
    final start = end == 0 ? 0 : end - 1;
    if (step) {
      final index = seconds >= times[end] ? end : start;
      return weights.sublist(index * count, (index + 1) * count);
    }
    final alpha = end == start
        ? 0.0
        : ((seconds - times[start]) / (times[end] - times[start])).clamp(
            0.0,
            1.0,
          );
    if (rotation) {
      return _slerp(
        weights.sublist(start * count, (start + 1) * count),
        weights.sublist(end * count, (end + 1) * count),
        alpha,
      );
    }
    return List.generate(
      count,
      (i) =>
          weights[start * count + i] * (1 - alpha) +
          weights[end * count + i] * alpha,
    );
  }
}

List<double> _slerp(List<double> from, List<double> to, double alpha) {
  var dot = 0.0;
  for (var i = 0; i < 4; i++) {
    dot += from[i] * to[i];
  }
  final sign = dot < 0 ? -1.0 : 1.0;
  dot = dot.abs().clamp(0.0, 1.0);
  final angle = math.acos(dot);
  final a = dot > .9995
      ? 1 - alpha
      : math.sin((1 - alpha) * angle) / math.sin(angle);
  final b = dot > .9995 ? alpha : math.sin(alpha * angle) / math.sin(angle);
  final result = List.generate(4, (i) => from[i] * a + to[i] * sign * b);
  final length = math.sqrt(result.fold(0.0, (sum, v) => sum + v * v));
  return result.map((v) => v / length).toList();
}
