import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Adapts the native renderer's texture coordinates to the Flutter surface.
class PomoTextureSurface extends StatelessWidget {
  const PomoTextureSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipY: defaultTargetPlatform == TargetPlatform.linux,
    child: child,
  );
}
