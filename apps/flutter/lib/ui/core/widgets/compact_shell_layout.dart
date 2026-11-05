import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const compactShellBreakpoint = 820.0;

bool usesCompactMobileLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < compactShellBreakpoint &&
    (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

class CompactShellHeading extends InheritedWidget {
  const CompactShellHeading({
    required this.shown,
    this.onMenuPressed,
    required super.child,
    super.key,
  });

  final bool shown;
  final VoidCallback? onMenuPressed;

  static VoidCallback? menuActionOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CompactShellHeading>()
      ?.onMenuPressed;

  static bool isShown(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CompactShellHeading>()
          ?.shown ??
      false;

  @override
  bool updateShouldNotify(CompactShellHeading oldWidget) =>
      shown != oldWidget.shown || onMenuPressed != oldWidget.onMenuPressed;
}
