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
    required super.child,
    super.key,
  });

  final bool shown;

  static bool isShown(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CompactShellHeading>()
          ?.shown ??
      false;

  @override
  bool updateShouldNotify(CompactShellHeading oldWidget) =>
      shown != oldWidget.shown;
}
