import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/focus/presentation/focus_view_mode.dart';
import 'keyboard_shortcuts.dart';

const appZoomPreferenceKey = 'app.zoomPercent';
const appZoomMinimum = 70;
const appZoomMaximum = 150;

final appZoomProvider = NotifierProvider<AppZoomController, int>(
  AppZoomController.new,
);

class AppZoomController extends Notifier<int> {
  bool _locallyChanged = false;

  @override
  int build() {
    unawaited(_load());
    return 100;
  }

  Future<void> _load() async {
    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      final saved = preferences?.get(appZoomPreferenceKey);
      if (ref.mounted && !_locallyChanged && saved is int) {
        state = saved.clamp(appZoomMinimum, appZoomMaximum);
      }
    } catch (error) {
      debugPrint('Could not load interface zoom: $error');
    }
  }

  Future<void> apply(AppZoomCommand command) async {
    _locallyChanged = true;
    final percent = switch (command) {
      AppZoomCommand.increase => state + 10,
      AppZoomCommand.decrease => state - 10,
      AppZoomCommand.reset => 100,
    }.clamp(appZoomMinimum, appZoomMaximum);
    state = percent;
    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      await preferences?.setInt(appZoomPreferenceKey, percent);
    } catch (error) {
      // Keep zoom usable for this session if local preferences are unavailable.
      debugPrint('Could not save interface zoom: $error');
    }
  }
}

MediaQueryData zoomedMediaQuery(
  MediaQueryData media,
  Size viewport,
  double scale,
) => media.copyWith(
  size: viewport / scale,
  devicePixelRatio: media.devicePixelRatio * scale,
  padding: media.padding / scale,
  viewPadding: media.viewPadding / scale,
  viewInsets: media.viewInsets / scale,
  systemGestureInsets: media.systemGestureInsets / scale,
  displayFeatures: [
    for (final feature in media.displayFeatures)
      DisplayFeature(
        bounds: Rect.fromLTWH(
          feature.bounds.left / scale,
          feature.bounds.top / scale,
          feature.bounds.width / scale,
          feature.bounds.height / scale,
        ),
        type: feature.type,
        state: feature.state,
      ),
  ],
);

class AppZoom extends ConsumerWidget {
  const AppZoom({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Browser zoom owns both keyboard handling and persistence on the web.
    if (kIsWeb) return child;
    final scale = ref.watch(appZoomProvider) / 100;
    final platform = ref.watch(shortcutTargetPlatformProvider);
    final media = MediaQuery.of(context);
    return CallbackShortcuts(
      bindings: {
        for (final entry in appZoomBindings(platform).entries)
          entry.key: () =>
              unawaited(ref.read(appZoomProvider.notifier).apply(entry.value)),
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          return ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: viewport.width / scale,
                  height: viewport.height / scale,
                  child: MediaQuery(
                    data: zoomedMediaQuery(media, viewport, scale),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
