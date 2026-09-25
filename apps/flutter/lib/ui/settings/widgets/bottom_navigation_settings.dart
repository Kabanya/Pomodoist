import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton, LucideIcons;

import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_bottom_navigation.dart';
import 'package:pomodoist/ui/core/widgets/bottom_navigation_destination.dart';
import 'package:pomodoist/ui/settings/view_models/bottom_navigation_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class BottomNavigationSettings extends ConsumerWidget {
  const BottomNavigationSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(bottomNavigationProvider);
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l10n.settingsBottomNavigation,
          subtitle: l10n.settingsBottomNavigationDescription,
          control: settings.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsBottomNavigationLoadError),
                ShadButton.outline(
                  onPressed: () => ref.invalidate(bottomNavigationProvider),
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
            data: (preferences) => ShadButton.outline(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _NavigationEditor(
                  initial: preferences,
                  onSave: ref.read(bottomNavigationProvider.notifier).save,
                ),
              ),
              child: Text(l10n.settingsBottomNavigationEdit),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavigationEditor extends StatefulWidget {
  const _NavigationEditor({required this.initial, required this.onSave});
  final BottomNavigationPreferences initial;
  final Future<void> Function(BottomNavigationPreferences) onSave;

  @override
  State<_NavigationEditor> createState() => _NavigationEditorState();
}

class _NavigationEditorState extends State<_NavigationEditor> {
  late var _draft = widget.initial;
  late BottomNavigationDestination? _preview = _draft.destinations.firstOrNull;
  bool _saving = false;
  bool _failed = false;

  void _edit(BottomNavigationPreferences value) => setState(() {
    _draft = value;
    _failed = false;
    if (!_draft.destinations.contains(_preview)) {
      _preview = _draft.destinations.firstOrNull;
    }
  });

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(_draft);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = _draft.destinations;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(l10n.settingsBottomNavigation),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final style in BottomNavigationStyle.values)
                      ChoiceChip(
                        label: Text(
                          style == BottomNavigationStyle.soft
                              ? l10n.settingsBottomNavigationSoft
                              : l10n.settingsBottomNavigationLabels,
                        ),
                        selected: _draft.style == style,
                        onSelected: _saving
                            ? null
                            : (_) => _edit(_draft.copyWith(style: style)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.settingsBottomNavigationPreview,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                if (destinations.isEmpty)
                  Text(l10n.settingsBottomNavigationEmpty)
                else
                  AppBottomNavigation(
                    preferences: _draft,
                    selected: _preview,
                    preview: true,
                    onSelected: (destination) =>
                        setState(() => _preview = destination),
                  ),
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.settingsBottomNavigationCount(
                      destinations.length,
                      bottomNavigationMaxDestinations,
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (var index = 0; index < destinations.length; index++)
                  Row(
                    children: [
                      Icon(destinations[index].icon, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(destinations[index].label(context))),
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        tooltip:
                            '${l10n.settingsBottomNavigationEarlier}: ${destinations[index].label(context)}',
                        onPressed: _saving || index == 0
                            ? null
                            : () => _edit(_draft.move(index, index - 1)),
                        icon: const Icon(LucideIcons.arrowUp, size: 18),
                      ),
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        tooltip:
                            '${l10n.settingsBottomNavigationLater}: ${destinations[index].label(context)}',
                        onPressed: _saving || index == destinations.length - 1
                            ? null
                            : () => _edit(_draft.move(index, index + 1)),
                        icon: const Icon(LucideIcons.arrowDown, size: 18),
                      ),
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        tooltip:
                            '${l10n.settingsBottomNavigationRemove}: ${destinations[index].label(context)}',
                        onPressed: _saving
                            ? null
                            : () => _edit(_draft.remove(destinations[index])),
                        icon: const Icon(LucideIcons.x, size: 18),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Text(
                  l10n.settingsBottomNavigationAdd,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final destination
                        in BottomNavigationDestination.values)
                      if (!destinations.contains(destination))
                        ShadButton.outline(
                          height: 44,
                          expands: true,
                          enabled:
                              !_saving &&
                              destinations.length <
                                  bottomNavigationMaxDestinations,
                          onPressed: () => _edit(_draft.add(destination)),
                          leading: Icon(destination.icon, size: 18),
                          child: Text(
                            destination.label(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton.ghost(
                      enabled: !_saving && destinations.isNotEmpty,
                      onPressed: () => _edit(_draft.copyWith(destinations: [])),
                      child: Text(l10n.settingsBottomNavigationClear),
                    ),
                    ShadButton.ghost(
                      enabled: !_saving,
                      onPressed: () => _edit(BottomNavigationPreferences()),
                      child: Text(l10n.settingsBottomNavigationDefaults),
                    ),
                  ],
                ),
                if (_failed)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.settingsSaveError,
                      style: TextStyle(color: context.appColors.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          ShadButton.ghost(
            enabled: !_saving,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          ShadButton(
            enabled: !_saving,
            onPressed: _save,
            leading: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}
