import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/ui/pomo/models/pomo_model_asset.dart';
import 'package:pomodoist/ui/pomo/models/pomo_morph_clips.dart';
import 'package:thermion_flutter/thermion_flutter.dart' as t;
import 'package:vector_math/vector_math_64.dart' show Vector3;

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
  final _materials = <(t.MaterialInstance, bool)>[];
  late Map<String, dynamic> _clips;
  List<String> _names = [];
  late PomoMorphClips _morphs;
  final _meshEntities = <String, t.ThermionEntity>{};
  final _morphEntities = <t.ThermionEntity>{};
  final _clipClock = Stopwatch();
  Map<String, List<double>>? _morphFrom;
  PomoEmotion? _appliedEmotion;
  bool? _appliedAnimated;
  bool _dirty = false;
  bool _ready = false;
  bool _failed = false;
  bool _surfaceReady = false;
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
          _materials.add((material, name.startsWith('thinking-')));
        }
      }
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
      final target = widget.emotion == PomoEmotion.focus ? 1.0 : 0.0;
      if (widget.animated && _ready) {
        unawaited(_variant.animateTo(target));
      } else {
        _variant.value = target;
      }
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

  void _prepareMorphTransition(PomoEmotion emotion, bool animated) {
    final manager = _viewer!.app.animationManager;
    for (final entity in _morphEntities) {
      manager.removeMorphAnimationComponent(entity);
    }
    _morphEntities.clear();
    final previous = _appliedEmotion;
    Map<String, List<double>>? from;
    if (animated && _appliedAnimated == true && previous != null) {
      final elapsed = _clipClock.elapsedMicroseconds / 1000000;
      from = _morphs.sample(
        previous.name,
        elapsed,
        loop: _clips[previous.name]['loop'] as bool,
      );
      if (_morphFrom != null && elapsed < .25) {
        from = PomoMorphClips.blend(_morphFrom!, from, elapsed / .25);
      }
      // Filament crossfades transforms only; native morph tracks complete the blend.
      final frames = [
        for (var i = 0; i < 16; i++)
          PomoMorphClips.blend(
            from,
            _morphs.sample(
              emotion.name,
              i / 60,
              loop: _clips[emotion.name]['loop'] as bool,
            ),
            i / 15,
          ),
      ];
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
    }
    _morphFrom = from;
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
        if (_appliedEmotion != emotion || _appliedAnimated != animated) {
          final index = _names.indexOf(emotion.name);
          final clip = _clips[emotion.name] as Map<String, dynamic>;
          _prepareMorphTransition(emotion, animated);
          if (animated) {
            if (_appliedAnimated != true) await asset.addAnimationComponent();
            await asset.playGltfAnimation(
              index,
              loop: clip['loop'] as bool,
              crossfade: _appliedAnimated == true ? .25 : 0,
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
        final focus = _variant.value;
        await viewer.setLayerVisibility(t.VisibilityLayers.LAYER_3, focus < 1);
        await viewer.setLayerVisibility(t.VisibilityLayers.LAYER_4, focus > 0);
        for (final (material, thinking) in _materials) {
          await material.setTransparencyMode(t.TransparencyMode.DEFAULT);
          await material.setDepthWriteEnabled(focus == 0 || focus == 1);
          await material.setParameterFloat4(
            'baseColorFactor',
            1,
            1,
            1,
            thinking ? focus : 1 - focus,
          );
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
          } else {
            await viewer.renderSingleFrame();
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
    await _initializing;
    await _updating;
    final viewer = _viewer;
    if (viewer == null) return;
    try {
      await t.ThermionFlutterPlugin.instance.destroyTextureForView(viewer.view);
    } finally {
      await viewer.dispose();
      for (final swapChain in _swapChains) {
        if (viewer.app.renderManager.getAttachedViews(swapChain).isEmpty) {
          await viewer.app.destroySwapChain(swapChain);
        }
      }
      await t.ThermionFlutterPlugin.instance.onViewerDisposed(viewer.view);
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
              if (!mounted || descriptor == null) return;
              _surfaceReady = true;
              _viewport = (descriptor.width, descriptor.height);
              _schedule();
            },
            surfaceWidgetBuilder: (descriptor, _) => descriptor == null
                ? _fallback()
                : Texture(
                    textureId: descriptor.flutterTextureId,
                    filterQuality: FilterQuality.low,
                  ),
          ),
  );
}
