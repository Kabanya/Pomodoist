import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_destination.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_layout.dart';
import 'package:pomodoist/ui/core/widgets/bottom_panel_surface.dart';

/// The shell and settings preview use the same navigation geometry.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.preferences,
    required this.selected,
    required this.onSelected,
    this.preview = false,
    super.key,
  });

  final BottomNavigationPreferences preferences;
  final BottomNavigationDestination? selected;
  final ValueChanged<BottomNavigationDestination> onSelected;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final destinations = preferences.destinations;
    if (destinations.isEmpty) return const SizedBox.shrink();
    final layout = bottomNavigationLayout(
      preferences.style,
      destinations.length,
    );
    final soft = preferences.style == BottomNavigationStyle.soft;
    final textStyle =
        (layout.labelsBelow
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.labelMedium)!
            .copyWith(fontWeight: FontWeight.w600);
    final active = destinations.contains(selected) ? selected : null;
    var labelWidth = 0.0;
    var labelHeight = 0.0;
    for (final destination in destinations) {
      final painter = TextPainter(
        text: TextSpan(text: destination.label(context), style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      labelHeight = math.max(labelHeight, painter.height);
      if (destination == active) labelWidth = painter.width;
      painter.dispose();
    }
    final height = math.max(
      layout.labelsBelow ? 64.0 : 48.0,
      labelHeight + (layout.labelsBelow ? 38 : 12),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Surface margins and border/padding consume 36 logical pixels.
        final minimumWidth = destinations.length * 44.0;
        final available = math.max(minimumWidth, constraints.maxWidth - 36);
        final natural =
            destinations.length * 48.0 + (active == null ? 0 : labelWidth + 8);
        final contentWidth = layout.expands
            ? available
            : math.min(available, natural);
        final inactiveWidth = active == null
            ? contentWidth / destinations.length
            : 44.0;
        final target = BottomNavigationFrame(
          widths: [
            for (final destination in destinations)
              !soft
                  ? contentWidth / destinations.length
                  : destination == active
                  ? contentWidth - inactiveWidth * (destinations.length - 1)
                  : inactiveWidth,
          ],
          labels: [
            for (final destination in destinations)
              !soft || destination == active ? 1.0 : 0.0,
          ],
        );
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return TweenAnimationBuilder<BottomNavigationFrame>(
          // Configuration changes start in their final layout; only route
          // changes retarget the current frame. Reduce Motion snaps immediately.
          key: ValueKey((
            preferences.style,
            destinations.map((d) => d.name).join(','),
            reduceMotion,
          )),
          tween: BottomNavigationTween(end: target),
          duration: AppMotion.duration(context, AppMotion.navigation),
          curve: AppMotion.navigationCurve,
          builder: (context, frame, _) {
            final panel = SizedBox(
              width: frame.contentWidth + 36,
              child: BottomPanelSurface(
                bottomSpacing: preview ? 0 : 12,
                trackClearance: !preview,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: SizedBox(
                    height: height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
                          SizedBox(
                            width: frame.widths[index],
                            child: _DestinationButton(
                              destination: destinations[index],
                              selected: destinations[index] == active,
                              labelProgress: frame.labels[index],
                              labelsBelow: layout.labelsBelow,
                              textStyle: textStyle,
                              onTap: () => onSelected(destinations[index]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            return Align(
              heightFactor: 1,
              child: frame.contentWidth + 36 > constraints.maxWidth + .001
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: panel,
                    )
                  : panel,
            );
          },
        );
      },
    );
  }
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.labelProgress,
    required this.labelsBelow,
    required this.textStyle,
    required this.onTap,
  });

  final BottomNavigationDestination destination;
  final bool selected;
  final double labelProgress;
  final bool labelsBelow;
  final TextStyle textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = destination.label(context);
    final foreground = selected ? colors.accent : colors.secondaryText;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle.copyWith(color: foreground),
      textAlign: TextAlign.center,
    );
    final icon = Icon(destination.icon, size: 22, color: foreground);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.state),
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: selected ? colors.accentTint : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: ExcludeSemantics(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: labelsBelow ? 2 : 4,
                    vertical: 6,
                  ),
                  child: labelsBelow
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [icon, const SizedBox(height: 4), text],
                        )
                      // The icon stays centred in its own slot; the label grows
                      // from the leading edge as a cropped overlay while the
                      // inactive slots are collapsed to a sliver.
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            icon,
                            Positioned.fill(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: ClipRect(
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        widthFactor: labelProgress,
                                        child: Opacity(
                                          opacity: labelProgress.clamp(
                                            0.0,
                                            1.0,
                                          ),
                                          child: Padding(
                                            padding:
                                                const EdgeInsetsDirectional.only(
                                                  start: 6,
                                                ),
                                            child: text,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
