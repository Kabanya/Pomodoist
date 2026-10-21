import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_destination.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_layout.dart';
import 'package:pomodoist/ui/core/widgets/bottom_panel_surface.dart';
import 'package:pomodoist/ui/onboarding/widgets/learning_tour_overlay.dart';

/// The shell and settings preview use the same navigation geometry.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.preferences,
    required this.selected,
    required this.onSelected,
    this.preview = false,
    this.onEditRequested,
    this.editing = false,
    this.enabled = true,
    this.onReorder,
    super.key,
  });

  final BottomNavigationPreferences preferences;
  final BottomNavigationDestination? selected;
  final ValueChanged<BottomNavigationDestination> onSelected;
  final bool preview;
  final ValueChanged<BottomNavigationDestination>? onEditRequested;
  final bool editing;
  final bool enabled;
  final void Function(int from, int to)? onReorder;

  @override
  Widget build(BuildContext context) {
    final destinations = preferences.destinations;
    if (destinations.isEmpty) return const SizedBox.shrink();
    if (editing) return _editingPanel(context);
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
        final widths = [
          for (final destination in destinations)
            !soft
                ? contentWidth / destinations.length
                : destination == active
                ? contentWidth - inactiveWidth * (destinations.length - 1)
                : inactiveWidth,
        ];
        final activeIndex = active == null ? -1 : destinations.indexOf(active);
        final hasAccent = soft && activeIndex >= 0;
        final target = BottomNavigationFrame(
          widths: widths,
          labels: [
            for (final destination in destinations)
              !soft || destination == active ? 1.0 : 0.0,
          ],
          accentStart: hasAccent
              ? widths.take(activeIndex).fold(0.0, (sum, width) => sum + width)
              : 0,
          accentWidth: hasAccent ? widths[activeIndex] : 0,
          accentOpacity: hasAccent ? 1 : 0,
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
                    child: Stack(
                      children: [
                        if (soft)
                          PositionedDirectional(
                            start: frame.accentStart,
                            width: frame.accentWidth,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: ExcludeSemantics(
                                child: Opacity(
                                  opacity: frame.accentOpacity.clamp(0.0, 1.0),
                                  child: AnimatedContainer(
                                    duration: AppMotion.duration(
                                      context,
                                      AppMotion.state,
                                    ),
                                    curve: AppMotion.curve,
                                    decoration: BoxDecoration(
                                      color: context.appColors.accentTint,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < destinations.length;
                              index++
                            )
                              SizedBox(
                                width: frame.widths[index],
                                child:
                                    !preview &&
                                        (destinations[index] ==
                                                BottomNavigationDestination
                                                    .focus ||
                                            destinations[index] ==
                                                BottomNavigationDestination
                                                    .projects)
                                    ? LearningTourAnchor(
                                        id:
                                            destinations[index] ==
                                                BottomNavigationDestination
                                                    .focus
                                            ? LearningTourAnchorId.focusMobile
                                            : LearningTourAnchorId
                                                  .projectsMobile,
                                        child: _DestinationButton(
                                          destination: destinations[index],
                                          selected:
                                              destinations[index] == active,
                                          showBackground: !soft,
                                          labelProgress: frame.labels[index],
                                          labelsBelow: layout.labelsBelow,
                                          textStyle: textStyle,
                                          onTap: () =>
                                              onSelected(destinations[index]),
                                          onEdit:
                                              !preview &&
                                                  enabled &&
                                                  onEditRequested != null
                                              ? () => onEditRequested!(
                                                  destinations[index],
                                                )
                                              : null,
                                        ),
                                      )
                                    : _DestinationButton(
                                        destination: destinations[index],
                                        selected: destinations[index] == active,
                                        showBackground: !soft,
                                        labelProgress: frame.labels[index],
                                        labelsBelow: layout.labelsBelow,
                                        textStyle: textStyle,
                                        onTap: () =>
                                            onSelected(destinations[index]),
                                        onEdit:
                                            !preview &&
                                                enabled &&
                                                onEditRequested != null
                                            ? () => onEditRequested!(
                                                destinations[index],
                                              )
                                            : null,
                                      ),
                              ),
                          ],
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

  Widget _editingPanel(BuildContext context) {
    final destinations = preferences.destinations;
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(
          destinations.length * 48.0,
          constraints.maxWidth - 36,
        );
        final width = destinations.length >= 4
            ? available
            : math.min(available, destinations.length * 56.0);
        final itemWidth = width / destinations.length;
        Widget button(BottomNavigationDestination destination) => Tooltip(
          message: destination.label(context),
          child: SizedBox(
            width: itemWidth,
            height: 48,
            child: Material(
              color: destination == selected
                  ? colors.accentTint
                  : colors.surface,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: enabled ? () => onSelected(destination) : null,
                borderRadius: BorderRadius.circular(8),
                child: Semantics(
                  label: destination.label(context),
                  selected: destination == selected,
                  child: ExcludeSemantics(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          destination.icon,
                          size: 22,
                          color: destination == selected
                              ? colors.accent
                              : colors.secondaryText,
                        ),
                        PositionedDirectional(
                          top: 2,
                          end: 2,
                          child: Icon(
                            LucideIcons.gripVertical,
                            size: 10,
                            color: colors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final panel = SizedBox(
          width: width + 36,
          child: BottomPanelSurface(
            bottomSpacing: preview ? 0 : 12,
            trackClearance: !preview,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  for (var index = 0; index < destinations.length; index++)
                    DragTarget<BottomNavigationDestination>(
                      onWillAcceptWithDetails: (details) =>
                          enabled &&
                          onReorder != null &&
                          details.data != destinations[index],
                      onAcceptWithDetails: (details) => onReorder?.call(
                        destinations.indexOf(details.data),
                        index,
                      ),
                      builder: (context, candidates, rejected) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                candidates.isNotEmpty ||
                                    destinations[index] == selected
                                ? colors.accent
                                : Colors.transparent,
                          ),
                        ),
                        child: Draggable<BottomNavigationDestination>(
                          data: destinations[index],
                          axis: Axis.horizontal,
                          maxSimultaneousDrags: enabled && onReorder != null
                              ? 1
                              : 0,
                          onDragStarted: () => onSelected(destinations[index]),
                          feedback: button(destinations[index]),
                          childWhenDragging: Opacity(
                            opacity: .35,
                            child: button(destinations[index]),
                          ),
                          child: button(destinations[index]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        return Align(
          heightFactor: 1,
          child: width + 36 > constraints.maxWidth
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: panel,
                )
              : panel,
        );
      },
    );
  }
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.showBackground,
    required this.labelProgress,
    required this.labelsBelow,
    required this.textStyle,
    required this.onTap,
    this.onEdit,
  });

  final BottomNavigationDestination destination;
  final bool selected;
  final bool showBackground;
  final double labelProgress;
  final bool labelsBelow;
  final TextStyle textStyle;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

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
      hint: onEdit == null ? null : context.l10n.bottomNavigationEditHint,
      customSemanticsActions: onEdit == null
          ? null
          : {
              CustomSemanticsAction(
                label: context.l10n.settingsBottomNavigationEdit,
              ): onEdit!,
            },
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.state),
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: selected && showBackground
                ? colors.accentTint
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: CallbackShortcuts(
              bindings: onEdit == null
                  ? const {}
                  : {
                      const SingleActivator(
                        LogicalKeyboardKey.f10,
                        shift: true,
                      ): onEdit!,
                      const SingleActivator(LogicalKeyboardKey.contextMenu):
                          onEdit!,
                    },
              child: GestureDetector(
                onSecondaryTapDown: onEdit == null ? null : (_) => onEdit!(),
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onEdit,
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
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                icon,
                                Flexible(
                                  child: ClipRect(
                                    child: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      widthFactor: labelProgress,
                                      child: Opacity(
                                        opacity: labelProgress.clamp(0.0, 1.0),
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
