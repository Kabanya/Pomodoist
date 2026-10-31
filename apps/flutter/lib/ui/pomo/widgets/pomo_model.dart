import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/ui/pomo/models/pomo_model_asset.dart';
import 'package:pomodoist/ui/pomo/models/pomo_morph_clips.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_texture_surface.dart';
import 'package:thermion_flutter/thermion_flutter.dart' as t;
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

/// A persistent native 3D scene; changing size or emotion keeps its GPU resources.
class PomoModel extends StatefulWidget {
  const PomoModel({required this.emotion, required this.animated, super.key});

  final PomoEmotion emotion;
  final bool animated;

  @override
  State<PomoModel> createState() => _PomoModelState();
}

class _PomoModelState extends State<PomoModel>
    with SingleTickerProviderStateMixin {
  static Future<void> _previousRelease = Future<void>.value();
  final _swapChains = <t.SwapChain>[];
  late final AnimationController _variant = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: widget.emotion == PomoEmotion.focus ? 1 : 0,
  )..addListener(_schedule);
  late final Future<void> _initializing;
  Future<void>? _updating;
  Future<void>? _releasing;
  t.ThermionViewer? _viewer;
  t.ThermionAsset? _asset;
  late t.ThermionAsset _instance;
  final _bones = <String, (int, t.ThermionEntity)>{};
  bool? _thinkingVisible;
  late Map<String, dynamic> _clips;
  List<String> _names = [];
  late PomoMorphClips _morphs;
  final _meshEntities = <String, t.ThermionEntity>{};
  final _morphEntities = <t.ThermionEntity>{};
  final _clipClock = Stopwatch();
  Map<String, List<double>>? _morphFrom;
  double _transitionSeconds = 0;
  bool _transitionBlinks = false;
  PomoEmotion? _appliedEmotion;
  bool? _appliedAnimated;
  bool _dirty = false;
  bool _ready = false;
  bool _failed = false;
  bool _surfaceReady = false;
  VoidCallback? _notifyTexture;
  (int, int)? _viewport;

  @override
  void initState() {
    super.initState();
    _initializing = _initialize();
  }

  Future<void> _initialize() async {
    await _previousRelease;
    try {
      final manifest =
          jsonDecode(
                await rootBundle.loadString('assets/pomo/model/manifest.json'),
              )
              as Map<String, dynamic>;
      _clips = manifest['clips'] as Map<String, dynamic>;
      final viewer = _viewer = await t.ThermionFlutterPlugin.createViewer();
      _swapChains.addAll(
        viewer.app.renderManager.getAttachedSwapChains(viewer.view),
      );
      if (!mounted) return;
      viewer.app.setTargetFramerate(30);
      await viewer.setAntiAliasing(false, true, false);
      await viewer.setBackgroundColor(0, 0, 0, 0);
      final camera = await viewer.getActiveCamera();
      await camera.lookAt(Vector3(0, .2, 3.8), focus: Vector3(0, -.025, 0));
      await camera.setProjection(
        t.Projection.Orthographic,
        -.64,
        .64,
        -.64,
        .64,
        .1,
        20,
      );
      // Filament supports one directional light; use points for the studio fills.
      for (final (position, intensity) in [
        (Vector3(-2.3, 2.7, 3), 18000000.0),
        (Vector3(2.5, 1, 2), 7200000.0),
        (Vector3(-.8, 2.1, -1.8), 10000000.0),
        (Vector3(0, -2, 3), 2800000.0),
      ]) {
        await viewer.addDirectLight(
          t.DirectLight.point(
            position: position,
            intensity: intensity,
            falloffRadius: 20,
          ),
        );
      }
      final packed = await rootBundle.load('assets/pomo/model/pomo.glb.gz');
      final bytes = await compute(
        decodePomoModel,
        packed.buffer.asUint8List(packed.offsetInBytes, packed.lengthInBytes),
      );
      if (!mounted) return;
      _morphs = PomoMorphClips(ByteData.sublistView(bytes));
      final asset = _asset = await viewer.loadGltfFromBuffer(bytes);
      _instance = asset.isInstance ? asset : await asset.getInstance(0);
      final bones = await _instance.getBones();
      final boneNames = await _instance.getBoneNames();
      for (var i = 0; i < bones.length; i++) {
        _bones[boneNames[i]] = (i, bones[i]);
      }
      _names = await asset.getGltfAnimationNames();
      if (!PomoEmotion.values.every(
        (emotion) =>
            _names.contains(emotion.name) && _clips.containsKey(emotion.name),
      )) {
        throw StateError('Pomo model is missing an emotion');
      }
      final materials = await asset.getMaterialInstancesAsMap();
      for (final entry in materials.entries) {
        final name = viewer.app.getNameForEntity(entry.key) ?? '';
        if (!name.startsWith('thinking-') && !name.startsWith('regular-')) {
          throw StateError('Unknown Pomo mesh: $name');
        }
        _meshEntities[name] = entry.key;
        await asset.setVisibilityLayer(
          entry.key,
          name.startsWith('thinking-')
              ? t.VisibilityLayers.LAYER_4
              : t.VisibilityLayers.LAYER_3,
        );
        for (final material in entry.value) {
          await material.setDepthWriteEnabled(true);
        }
      }
      await asset.releaseSourceData();
      if (!mounted) return;
      setState(() => _ready = true);
      _schedule();
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  @override
  void didUpdateWidget(PomoModel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emotion != widget.emotion ||
        oldWidget.animated != widget.animated) {
      _schedule();
    }
  }

  void _schedule() {
    _dirty = true;
    if (!_ready || !_surfaceReady || !mounted || _failed || _updating != null) {
      return;
    }
    _updating = _sync().whenComplete(() {
      _updating = null;
      if (_dirty && mounted && !_failed) _schedule();
    });
  }

  Future<void> _prepareTransition(PomoEmotion emotion, bool animated) async {
    final manager = _viewer!.app.animationManager;
    final previous = _appliedEmotion;
    final seconds =
        emotion == PomoEmotion.focus ||
            previous == PomoEmotion.focus ||
            _variant.value > 0
        ? .7
        : .25;
    final blend = animated && _appliedAnimated == true && previous != null;
    final blink = (emotion == PomoEmotion.focus) != (_variant.value >= .5);
    final boneFrom = <String, Matrix4>{
      if (blend)
        for (final entry in _bones.entries)
          entry.key: _viewer!.app.transformManager
              .getLocalTransform(entry.value.$2)
              .clone(),
    };
    await manager.removeBoneAnimationComponent(_instance);
    for (final entity in _morphEntities) {
      manager.removeMorphAnimationComponent(entity);
    }
    _morphEntities.clear();
    Map<String, List<double>>? from;
    if (blend) {
      final elapsed = _clipClock.elapsedMicroseconds / 1000000;
      from = _morphs.sample(
        previous.name,
        elapsed,
        loop: _clips[previous.name]['loop'] as bool,
      );
      if (_morphFrom != null && elapsed < _transitionSeconds) {
        from = PomoMorphClips.blend(
          _morphFrom!,
          from,
          Curves.easeInOut.transform(elapsed / _transitionSeconds),
        );
        if (_transitionBlinks) {
          _morphs.applyBlink(
            from,
            PomoMorphClips.transitionBlink(elapsed / _transitionSeconds),
          );
        }
      }
      final frameCount = (seconds * 60).ceil() + 1;
      final frames = [
        for (var i = 0; i < frameCount; i++)
          PomoMorphClips.blend(
            from,
            _morphs.sample(
              emotion.name,
              i / 60,
              loop: _clips[emotion.name]['loop'] as bool,
            ),
            Curves.easeInOut.transform(i / (frameCount - 1)),
          ),
      ];
      if (blink) {
        for (var i = 0; i < frameCount; i++) {
          _morphs.applyBlink(
            frames[i],
            PomoMorphClips.transitionBlink(i / (frameCount - 1)),
          );
        }
      }
      for (final name in from.keys) {
        final entity = _meshEntities[name]!;
        final count = from[name]!.length;
        if (!manager.setMorphAnimation(
          entity,
          [for (final frame in frames) ...frame[name]!],
          List.generate(count, (i) => i),
          count,
          frames.length,
          1000 / 60,
        )) {
          throw StateError('Cannot blend Pomo morphs: $name');
        }
        _morphEntities.add(entity);
      }
      if (!await manager.addBoneAnimationComponent(_instance)) {
        throw StateError('Cannot animate Pomo bones');
      }
      final poses = [
        for (var i = 0; i < frameCount; i++)
          _morphs.sampleBones(
            emotion.name,
            i / 60,
            loop: _clips[emotion.name]['loop'] as bool,
          ),
      ];
      // Snapshot the visible skeleton so an interrupted transition never restarts its old clip.
      for (final entry in _bones.entries) {
        if (!await manager.addBoneAnimation(
          _instance,
          0,
          entry.value.$1,
          [
            for (var i = 0; i < frameCount; i++)
              ...PomoMorphClips.blendBone(
                boneFrom[entry.key]!,
                poses[i][entry.key]!,
                Curves.easeInOut.transform(i / (frameCount - 1)),
              ).storage,
          ],
          frameCount,
          1000 / 60,
          maxDelta: 1,
        )) {
          throw StateError('Cannot blend Pomo bone: ${entry.key}');
        }
      }
    }
    _morphFrom = from;
    _transitionSeconds = blend ? seconds : 0;
    _transitionBlinks = blend && blink;
    if (!mounted) return;
    final target = emotion == PomoEmotion.focus ? 1.0 : 0.0;
    _variant.value = _variant.value >= .5 ? 1 : 0;
    if (blend) {
      unawaited(
        _variant.animateTo(
          target,
          duration: Duration(microseconds: (seconds * 1000000).round()),
          curve: Curves.easeInOut,
        ),
      );
    } else {
      _variant.value = target;
    }
    _clipClock
      ..reset()
      ..start();
  }

  Future<void> _sync() async {
    final viewer = _viewer!;
    final asset = _asset!;
    try {
      while (_dirty && mounted && !_failed) {
        _dirty = false;
        final emotion = widget.emotion;
        final animated = widget.animated;
        // Pomo owns this engine; Quiet must also stop texture notifications.
        if (!animated) t.ThermionFlutterPlugin.instance.pauseFrameScheduler();
        if (_appliedEmotion != emotion || _appliedAnimated != animated) {
          final index = _names.indexOf(emotion.name);
          final clip = _clips[emotion.name] as Map<String, dynamic>;
          _variant.stop();
          await viewer.setRendering(false);
          await _prepareTransition(emotion, animated);
          if (!mounted) return;
          if (animated) {
            if (_appliedAnimated != true) await asset.addAnimationComponent();
            await asset.playGltfAnimation(
              index,
              loop: clip['loop'] as bool,
              crossfade: _transitionSeconds,
            );
          } else {
            await viewer.setRendering(false);
            if (_appliedAnimated == true) {
              await asset.removeAnimationComponent();
            }
            await asset.setGltfAnimationTime(
              index,
              (clip['stillSeconds'] as num).toDouble(),
            );
          }
          _appliedEmotion = emotion;
          _appliedAnimated = animated;
        }
        final thinking = _variant.value >= .5;
        if (_thinkingVisible != thinking) {
          await viewer.setRendering(false);
          await viewer.setLayerVisibility(
            t.VisibilityLayers.LAYER_3,
            !thinking,
          );
          await viewer.setLayerVisibility(t.VisibilityLayers.LAYER_4, thinking);
          _thinkingVisible = thinking;
        }
        if (!mounted) return;
        final viewport = _viewport;
        if (viewport != null) {
          _viewport = null;
          await viewer.view.setViewport(viewport.$1, viewport.$2);
        }
        if (_surfaceReady) {
          if (animated) {
            await viewer.setRendering(true);
            t.ThermionFlutterPlugin.instance.resumeFrameScheduler();
          } else {
            await viewer.renderSingleFrame();
            if (mounted) _notifyTexture?.call();
          }
        }
      }
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  void _report(Object error, StackTrace stack) {
    if (!mounted) return;
    setState(() => _failed = true);
    _variant.stop();
    unawaited(_release());
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Pomo 3D',
        context: ErrorDescription('while loading or updating the Pomo model'),
      ),
    );
  }

  @override
  void dispose() {
    _variant.dispose();
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() =>
      _releasing ??= _previousRelease = _disposeScene().catchError(
        (Object error, StackTrace stack) => FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Pomo 3D cleanup',
          ),
        ),
      );

  Future<void> _disposeScene() async {
    Object? firstError;
    StackTrace? firstStack;
    Future<void> cleanup(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }

    await cleanup(() => _initializing);
    await cleanup(() async => await _updating);
    final viewer = _viewer;
    if (viewer != null) {
      await cleanup(() => viewer.setRendering(false));
      await cleanup(
        () =>
            t.ThermionFlutterPlugin.instance.destroyTextureForView(viewer.view),
      );
      await cleanup(() => viewer.dispose());
      for (final swapChain in _swapChains) {
        await cleanup(() async {
          if (viewer.app.renderManager.getAttachedViews(swapChain).isEmpty) {
            await viewer.app.destroySwapChain(swapChain);
          }
        });
      }
      await cleanup(
        () => t.ThermionFlutterPlugin.instance.onViewerDisposed(viewer.view),
      );
    }
    // Also release an engine left by a failed createViewer call.
    final app = viewer?.app ?? t.FilamentApp.instance;
    if (!kIsWeb && app != null) await cleanup(() => app.destroy());
    _viewer = null;
    _asset = null;
    _swapChains.clear();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }

  Widget _fallback() => Image.asset(
    'assets/pomo/${widget.emotion.name}-still.webp',
    fit: BoxFit.contain,
  );

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: !_ready || _failed
        ? _fallback()
        : t.ThermionWidgetInternal(
            view: _viewer!.view,
            onTextureUpdated: (descriptor) {
              if (!mounted) return;
              _surfaceReady = descriptor != null;
              _notifyTexture = descriptor == null
                  ? null
                  : () {
                      if (!descriptor.destroyed) {
                        descriptor.markTextureFrameAvailable();
                      }
                    };
              if (descriptor == null) return;
              _viewport = (descriptor.width, descriptor.height);
              _schedule();
            },
            surfaceWidgetBuilder: (descriptor, _) => descriptor == null
                ? _fallback()
                : PomoTextureSurface(
                    child: Texture(
                      textureId: descriptor.flutterTextureId,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
          ),
  );
}
