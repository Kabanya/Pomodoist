import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/config/app_zoom_dependencies.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/data/repositories/settings/app_zoom_repository.dart'
    show appZoomMinimum, appZoomMaximum;

export 'package:pomodoist/data/repositories/settings/app_zoom_repository.dart'
    show appZoomPreferenceKey, appZoomMinimum, appZoomMaximum;

final appZoomProvider = NotifierProvider<AppZoomController, int>(
  AppZoomController.new,
);

final appZoomBindingsProvider = Provider(
  (ref) => appZoomBindings(ref.watch(shortcutTargetPlatformProvider)),
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
      final saved = (await ref.read(appZoomRepositoryProvider).read())
          .getOrThrow();
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
      (await ref.read(appZoomRepositoryProvider).write(percent)).getOrThrow();
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
