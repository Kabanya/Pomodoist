import 'package:pomodoist/ui/tasks/widgets/voice_panel_clearance.dart';
import 'package:flutter/material.dart';

import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

/// Shared bottom chrome. Hosts own safe areas and the panel's place in layout.
class BottomPanelSurface extends StatelessWidget {
  const BottomPanelSurface({
    required this.child,
    this.floating = true,
    this.bottomSpacing = 8,
    this.surfaceKey,
    this.trackClearance = true,
    super.key,
  });

  final Widget child;
  final bool floating;
  final double bottomSpacing;
  final Key? surfaceKey;

  /// Settings previews must not move floating controls in the application shell.
  final bool trackClearance;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = floating ? BorderRadius.circular(12) : BorderRadius.zero;
    final panel = Padding(
      padding: floating
          ? EdgeInsets.fromLTRB(12, 0, 12, bottomSpacing)
          : EdgeInsets.zero,
      child: AnimatedContainer(
        key: surfaceKey,
        duration: AppMotion.duration(context, AppMotion.state),
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: colors.surface,
          border: floating
              ? Border.all(color: colors.border)
              : Border(top: BorderSide(color: colors.border)),
          borderRadius: floating ? radius : null,
          boxShadow: floating
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: floating ? Clip.antiAlias : Clip.none,
          child: child,
        ),
      ),
    );
    return floating && trackClearance
        ? VoicePanelBottomClearance(child: panel)
        : panel;
  }
}
