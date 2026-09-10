import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_motion.dart';
import 'app_theme_settings.dart';

bool get supportsMacosGlass =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool macosGlassReady(BuildContext context, WidgetRef ref) =>
    supportsMacosGlass &&
    ref.watch(
      macosGlassProvider.select(
        (windows) => windows[View.of(context).viewId] ?? false,
      ),
    );

// ShadAppBuilder paints an opaque background by default, above the native glass.
// Keep that default until this view is ready, and restore it as soon as glass ends.
final macosGlassRootBackgroundProvider = Provider.family<Color?, int>((
  ref,
  viewId,
) {
  if (!supportsMacosGlass) return null;
  final enabled = ref.watch(
    appThemeSettingsProvider.select(
      (settings) =>
          settings.activeTheme.backgrounds.type ==
          ThemeBackgroundType.macosGlass,
    ),
  );
  final ready = ref.watch(
    macosGlassProvider.select((windows) => windows[viewId] ?? false),
  );
  return enabled && ready ? Colors.transparent : null;
});

final macosGlassOpaqueFrameProvider = Provider<Future<void> Function(Duration)>(
  (ref) => (duration) async {
    // Keep the native material until Flutter's opaque transition has painted.
    await WidgetsBinding.instance.endOfFrame;
    if (duration > Duration.zero) await Future<void>.delayed(duration);
    await WidgetsBinding.instance.endOfFrame;
  },
);

final macosGlassProvider =
    NotifierProvider<MacosGlassController, Map<int, bool>>(
      MacosGlassController.new,
    );

class MacosGlassController extends Notifier<Map<int, bool>> {
  static const _channel = MethodChannel('pomodoist/macos_glass');
  final _requests = <int, ({bool enabled, bool dark})>{};
  final _versions = <int, int>{};
  final _queues = <int, Future<void>>{};
  int _generation = 0;
  bool _reduced = false;

  @override
  Map<int, bool> build() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'windowModeChanged') {
        final args = call.arguments;
        if (args is! Map ||
            args['viewId'] is! int ||
            args['fullScreen'] is! bool)
          return;
        final id = args['viewId'] as int;
        final request = _requests[id];
        if (request == null) return;
        // Cover the native layer until its eligibility in this window is known.
        state = {...state, id: false};
        await _schedule(id, request, Duration.zero);
        return;
      }
      if (call.method != 'transparencyChanged' ||
          call.arguments is! Map ||
          (call.arguments as Map)['reduceTransparency'] is! bool)
        return;
      _reduced = (call.arguments as Map)['reduceTransparency'] as bool;
      if (_reduced) {
        // Also invalidate replies issued before the accessibility change.
        for (final id in _requests.keys) {
          _versions[id] = ++_generation;
        }
        state = {for (final id in state.keys) id: false};
      } else {
        await Future.wait([
          for (final entry in _requests.entries.toList())
            _schedule(entry.key, entry.value, Duration.zero),
        ]);
      }
    });
    ref.onDispose(() => _channel.setMethodCallHandler(null));
    return {};
  }

  Future<void> update(
    int viewId, {
    required bool enabled,
    required bool dark,
    Duration duration = Duration.zero,
  }) {
    final request = (enabled: enabled, dark: dark);
    if (_requests[viewId] == request) return _queues[viewId] ?? Future.value();
    _requests[viewId] = request;
    return _schedule(viewId, request, duration);
  }

  Future<void> _schedule(
    int id,
    ({bool enabled, bool dark}) request,
    Duration duration,
  ) {
    final version = ++_generation;
    _versions[id] = version;
    if (!request.enabled || _reduced) state = {...state, id: false};
    bool current() => ref.mounted && _versions[id] == version;
    final pending = (_queues[id] ?? Future<void>.value()).then((_) async {
      if (!current()) return;
      try {
        if (!request.enabled) {
          await ref.read(macosGlassOpaqueFrameProvider)(duration);
          if (!current()) return;
        }
        final response = await _channel.invokeMapMethod<String, Object?>(
          'setGlass',
          {'viewId': id, 'enabled': request.enabled, 'dark': request.dark},
        );
        if (!current()) return;
        state = {
          ...state,
          id:
              request.enabled &&
              !_reduced &&
              response?['enabled'] == true &&
              response?['reduceTransparency'] == false,
        };
      } catch (_) {
        if (current()) state = {...state, id: false};
      }
    });
    _queues[id] = pending;
    return pending;
  }

  void forget(int viewId) {
    if (!ref.mounted) return;
    _requests.remove(viewId);
    _versions.remove(viewId);
    _queues.remove(viewId);
    state = {...state}..remove(viewId);
  }
}

/// One host per Flutter view; the desktop plugin's public IDs have an offset.
class MacosGlassHost extends ConsumerStatefulWidget {
  const MacosGlassHost({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<MacosGlassHost> createState() => _MacosGlassHostState();
}

class _MacosGlassHostState extends ConsumerState<MacosGlassHost> {
  MacosGlassController? _controller;
  int? _viewId;
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    if (supportsMacosGlass) {
      final enabled = ref.watch(
        appThemeSettingsProvider.select(
          (settings) =>
              settings.activeTheme.backgrounds.type ==
              ThemeBackgroundType.macosGlass,
        ),
      );
      final dark = Theme.of(context).brightness == Brightness.dark;
      final duration = AppMotion.duration(context, AppMotion.state);
      _viewId = View.of(context).viewId;
      final generation = ++_generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation) return;
        _controller = ref.read(macosGlassProvider.notifier);
        unawaited(
          _controller!.update(
            _viewId!,
            enabled: enabled,
            dark: dark,
            duration: duration,
          ),
        );
      });
    }
    return widget.child;
  }

  @override
  void dispose() {
    final id = _viewId;
    final controller = _controller;
    if (id != null && controller != null) {
      scheduleMicrotask(() => controller.forget(id));
    }
    super.dispose();
  }
}
