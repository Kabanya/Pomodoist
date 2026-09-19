import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/core/view_models/app_zoom_view_model.dart';

class AppZoom extends ConsumerWidget {
  const AppZoom({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return child;
    final scale = ref.watch(appZoomProvider) / 100;
    final bindings = ref.watch(appZoomBindingsProvider);
    final media = MediaQuery.of(context);
    return CallbackShortcuts(
      bindings: {
        for (final entry in bindings.entries)
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
