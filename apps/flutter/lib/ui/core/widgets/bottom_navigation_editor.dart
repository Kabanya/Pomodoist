import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_destination.dart';
import 'package:pomodoist/ui/core/widgets/bottom_panel_surface.dart';

/// Overlays the route body; Scaffold keeps the editable dock below this card.
class BottomNavigationEditor extends StatelessWidget {
  const BottomNavigationEditor({
    required this.preferences,
    required this.selected,
    required this.saving,
    required this.failed,
    required this.onMove,
    required this.onReplace,
    required this.onStyleChanged,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final BottomNavigationPreferences preferences;
  final BottomNavigationDestination selected;
  final bool saving;
  final bool failed;
  final ValueChanged<int> onMove;
  final ValueChanged<BottomNavigationDestination> onReplace;
  final ValueChanged<BottomNavigationStyle> onStyleChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final index = preferences.destinations.indexOf(selected);
    return BlockSemantics(
      child: Stack(
        children: [
          Positioned.fill(
            child: ModalBarrier(
              dismissible: !saving,
              onDismiss: onCancel,
              semanticsLabel: l10n.commonCancel,
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: BottomPanelSurface(
                  bottomSpacing: 0,
                  trackClearance: false,
                  child: FocusTraversalGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.bottomNavigationEditingTitle,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              IconButton(
                                autofocus: true,
                                tooltip: l10n.commonClose,
                                constraints: const BoxConstraints.tightFor(
                                  width: 48,
                                  height: 48,
                                ),
                                onPressed: saving ? null : onCancel,
                                icon: const Icon(LucideIcons.x, size: 20),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  l10n.bottomNavigationEditingHelp,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colors.secondaryText),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceTint,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(selected.icon, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          selected.label(context),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: l10n
                                            .settingsBottomNavigationEarlier,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 48,
                                              height: 48,
                                            ),
                                        onPressed: saving || index <= 0
                                            ? null
                                            : () => onMove(-1),
                                        icon: const BackButtonIcon(),
                                      ),
                                      IconButton(
                                        tooltip:
                                            l10n.settingsBottomNavigationLater,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 48,
                                              height: 48,
                                            ),
                                        onPressed:
                                            saving ||
                                                index >=
                                                    preferences
                                                            .destinations
                                                            .length -
                                                        1
                                            ? null
                                            : () => onMove(1),
                                        icon: Transform.flip(
                                          flipX: true,
                                          child: const BackButtonIcon(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n.bottomNavigationReplace,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: colors.secondaryText),
                                ),
                                const SizedBox(height: 8),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final columns =
                                        constraints.maxWidth >= 288 &&
                                            MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(1) <=
                                                1.3
                                        ? 3
                                        : 2;
                                    return Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final destination
                                            in BottomNavigationDestination
                                                .values)
                                          SizedBox(
                                            width:
                                                (constraints.maxWidth -
                                                    (columns - 1) * 8) /
                                                columns,
                                            child: Tooltip(
                                              message: destination.label(
                                                context,
                                              ),
                                              child: OutlinedButton(
                                                onPressed: saving
                                                    ? null
                                                    : () => onReplace(
                                                        destination,
                                                      ),
                                                style: OutlinedButton.styleFrom(
                                                  minimumSize: const Size(
                                                    0,
                                                    48,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 12,
                                                      ),
                                                  alignment:
                                                      AlignmentDirectional
                                                          .centerStart,
                                                  backgroundColor:
                                                      destination == selected
                                                      ? colors.accentTint
                                                      : preferences.destinations
                                                            .contains(
                                                              destination,
                                                            )
                                                      ? colors.surfaceTint
                                                      : colors.surface,
                                                  foregroundColor:
                                                      destination == selected
                                                      ? colors.accent
                                                      : colors.primaryText,
                                                  side: BorderSide(
                                                    color:
                                                        destination == selected
                                                        ? colors.accent
                                                        : colors.border,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  textStyle: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                child: Semantics(
                                                  selected:
                                                      destination == selected,
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        destination.icon,
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          destination.label(
                                                            context,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    for (final style
                                        in BottomNavigationStyle.values)
                                      ChoiceChip(
                                        label: Text(
                                          style == BottomNavigationStyle.soft
                                              ? l10n.settingsBottomNavigationSoft
                                              : l10n.settingsBottomNavigationLabels,
                                        ),
                                        selected: preferences.style == style,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.padded,
                                        onSelected: saving
                                            ? null
                                            : (_) => onStyleChanged(style),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (failed)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                l10n.settingsSaveError,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: ShadButton.outline(
                                  height: 48,
                                  expands: true,
                                  enabled: !saving,
                                  onPressed: onCancel,
                                  child: Text(l10n.commonCancel),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ShadButton(
                                  height: 48,
                                  expands: true,
                                  enabled: !saving,
                                  onPressed: onSave,
                                  leading: saving
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : null,
                                  child: Text(l10n.commonSave),
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
        ],
      ),
    );
  }
}
