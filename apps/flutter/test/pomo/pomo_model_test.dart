import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/pomo/models/pomo_morph_clips.dart';
import 'package:pomodoist/ui/pomo/models/pomo_model_asset.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('variant handoff blinks without opening an already closed eye', () {
    final clips = PomoMorphClips(
      ByteData.sublistView(
        decodePomoModel(
          File('assets/pomo/model/pomo.glb.gz').readAsBytesSync(),
        ),
      ),
    );
    expect(PomoMorphClips.transitionBlink(0), 0);
    expect(PomoMorphClips.transitionBlink(.5), 1);
    expect(PomoMorphClips.transitionBlink(1), 0);
    final pose = clips.sample('focus', .2, loop: true);
    final original = [...pose['thinking-body']!];
    clips.applyBlink(pose, 1);
    expect(pose['thinking-body']!.take(2), [1.0, 1.0]);
    expect(pose['thinking-body']!.skip(2), original.skip(2));
    clips.applyBlink(pose, .1);
    expect(pose['thinking-body']!.take(2), [1.0, 1.0]);
  });
  test(
    'bone transitions preserve poses, rotations and interrupted movement',
    () {
      final clips = PomoMorphClips(
        ByteData.sublistView(
          decodePomoModel(
            File('assets/pomo/model/pomo.glb.gz').readAsBytesSync(),
          ),
        ),
      );
      final calm = clips.sampleBones('calm', .8, loop: true);
      final focus = clips.sampleBones('focus', .7, loop: true);
      expect(calm.length, 19);
      expect(focus.keys, unorderedEquals(calm.keys));
      for (final name in calm.keys) {
        final from = calm[name]!;
        final to = focus[name]!;
        expect(
          PomoMorphClips.blendBone(from, to, 0).storage,
          orderedEquals(from.storage),
        );
        expect(
          PomoMorphClips.blendBone(from, to, 1).storage,
          orderedEquals(to.storage),
        );
        final mid = PomoMorphClips.blendBone(from, to, .5);
        expect(mid.storage.every((v) => v.isFinite), true);
        expect(
          PomoMorphClips.blendBone(mid, from, 0).storage,
          orderedEquals(mid.storage),
        );
      }
      final halfTurn = Matrix4.rotationY(3.141592653589793);
      final mid = PomoMorphClips.blendBone(Matrix4.identity(), halfTurn, .5);
      final direction = mid.transform3(Vector3(0, 0, 1));
      expect(direction.length, closeTo(1, 1e-6));
      expect(direction.x.abs(), closeTo(1, 1e-6));
      expect(direction.z, closeTo(0, 1e-6));
      for (final emotion in PomoEmotion.values) {
        expect(
          clips.sampleBones(emotion.name, 0, loop: false).keys,
          unorderedEquals(calm.keys),
        );
      }
    },
  );
  test(
    'morph blending preserves endpoints, interrupted blends and loop boundaries',
    () {
      final clips = PomoMorphClips(
        ByteData.sublistView(
          decodePomoModel(
            File('assets/pomo/model/pomo.glb.gz').readAsBytesSync(),
          ),
        ),
      );
      final a = clips.sample('calm', .8, loop: true);
      final b = clips.sample('focus', .25, loop: true);
      for (final emotion in PomoEmotion.values) {
        expect(
          clips.sample(emotion.name, 0, loop: false).keys,
          unorderedEquals(a.keys),
        );
      }
      expect(PomoMorphClips.blend(a, b, 0), a);
      expect(PomoMorphClips.blend(a, b, 1), b);
      final mid = PomoMorphClips.blend(a, b, .5);
      final interrupted = PomoMorphClips.blend(mid, a, .5);
      for (final name in a.keys) {
        for (var i = 0; i < a[name]!.length; i++) {
          expect(mid[name]![i], closeTo((a[name]![i] + b[name]![i]) / 2, 1e-6));
          expect(
            interrupted[name]![i],
            closeTo(a[name]![i] * .75 + b[name]![i] * .25, 1e-6),
          );
        }
      }
      expect(
        clips.sample('focus', 6, loop: true),
        clips.sample('focus', 0, loop: true),
      );
      expect(
        clips.sample('sad', 10, loop: false),
        clips.sample('sad', .9, loop: false),
      );
    },
  );
  test('runtime model has skinned meshes and every complete emotion clip', () {
    final bytes = decodePomoModel(
      File('assets/pomo/model/pomo.glb.gz').readAsBytesSync(),
    );
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(0, Endian.little), 0x46546c67);
    expect(data.getUint32(4, Endian.little), 2);
    expect(data.getUint32(8, Endian.little), bytes.length);
    final jsonLength = data.getUint32(12, Endian.little);
    final gltf =
        jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)))
            as Map<String, dynamic>;
    final manifest =
        jsonDecode(File('assets/pomo/model/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(manifest['modelSha256'], sha256.convert(bytes).toString());
    final packed = File('assets/pomo/model/pomo.glb.gz').readAsBytesSync();
    expect(manifest['compressedSha256'], sha256.convert(packed).toString());
    expect(manifest['compressedBytes'], packed.length);
    expect(manifest['decodedBytes'], bytes.length);
    expect(manifest['source'], 'pomo_3_0_2_all_animations_linked.blend');
    expect(manifest['sourceVersion'], '3.0.2');
    final clips = manifest['clips'] as Map<String, dynamic>;
    final animations = gltf['animations'] as List<dynamic>;
    expect(
      animations.map((dynamic a) => a['name']),
      unorderedEquals(PomoEmotion.values.map((e) => e.name)),
    );
    final nodes = gltf['nodes'] as List<dynamic>;
    final accessors = gltf['accessors'] as List<dynamic>;
    final views = gltf['bufferViews'] as List<dynamic>;
    final hand = (gltf['meshes'] as List<dynamic>).singleWhere(
      (dynamic mesh) => mesh['name'] == 'thinking-arm.l',
    );
    final handTriangles = (hand['primitives'] as List<dynamic>).fold<int>(
      0,
      (total, dynamic primitive) =>
          total + (accessors[primitive['indices']]['count'] as int) ~/ 3,
    );
    expect(handTriangles, inInclusiveRange(1, 16000));
    expect(manifest['simplification'][0]['runtimeTriangles'], handTriangles);
    final binaryOffset = 20 + jsonLength + 8;
    expect(gltf['skins'], isNotEmpty);
    expect(
      (gltf['samplers'] as List).every((dynamic s) => s['minFilter'] == 9729),
      isTrue,
    );
    // Filament's sparse morph path loses the body on Metal.
    expect(accessors.any((dynamic a) => a.containsKey('sparse')), isFalse);
    for (final dynamic mesh in gltf['meshes'] as List) {
      for (final dynamic primitive in mesh['primitives'] as List) {
        final attributes = primitive['attributes'] as Map;
        // Blender's shader-mask color attributes are not glTF vertex colors.
        expect(
          attributes.keys.any(
            (dynamic k) => (k as String).startsWith('COLOR_'),
          ),
          isFalse,
        );
        expect(attributes.containsKey('TEXCOORD_2'), isFalse);
        expect(attributes.containsKey('TEXCOORD_0'), isTrue);
        if ((mesh['name'] as String).endsWith('-body')) {
          expect(attributes.containsKey('TANGENT'), isTrue);
        }
      }
    }
    expect(
      nodes.where((dynamic n) => n.containsKey('skin')).length,
      greaterThanOrEqualTo(3),
    );
    expect(nodes.any((dynamic n) => n['name'] == 'thinking-arm.l'), isTrue);
    for (final dynamic animation in animations) {
      final clip = clips[animation['name']] as Map<String, dynamic>;
      final duration = (clip['durationMs'] as num) / 1000;
      expect(clip['stillSeconds'], inInclusiveRange(0, duration));
      final channels = animation['channels'] as List<dynamic>;
      expect(
        channels.any((dynamic c) => c['target']['path'] == 'rotation'),
        isTrue,
      );
      expect(
        channels.any((dynamic c) => c['target']['path'] == 'weights'),
        isTrue,
      );
      var longest = 0.0;
      for (final dynamic sampler in animation['samplers']) {
        final accessor =
            accessors[sampler['input'] as int] as Map<String, dynamic>;
        final view =
            views[accessor['bufferView'] as int] as Map<String, dynamic>;
        final offset =
            binaryOffset +
            (view['byteOffset'] as int? ?? 0) +
            (accessor['byteOffset'] as int? ?? 0);
        var previous = -1.0;
        for (var i = 0; i < (accessor['count'] as int); i++) {
          final time = data.getFloat32(offset + i * 4, Endian.little);
          expect(time.isFinite, isTrue);
          if (i == 0) expect(time, closeTo(0, 0.000001));
          expect(time, greaterThan(previous));
          previous = time;
        }
        if (previous > longest) longest = previous;
      }
      expect(longest, closeTo(duration, 0.00001));
    }
    expect(clips['focus']['scene'], '10 | Thinking reference');
    expect(clips['focus']['durationMs'], 6000);
    expect(clips['rest']['durationMs'], 4000);
    expect(clips['tired']['durationMs'], 4000);
    expect(clips['sad']['durationMs'], 900);
  });
}
