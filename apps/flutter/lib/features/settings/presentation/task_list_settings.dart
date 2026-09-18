import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../../app/config/app_l10n.dart';
import '../../../app/config/task_time.dart';
import '../../../app/config/providers.dart';
import 'settings_components.dart';

class TaskListStyleSettings extends ConsumerWidget {
  const TaskListStyleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final style = ref.watch(taskListStyleProvider);
    final spacing = ref.watch(taskRowSpacingProvider);
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l10n.settingsTaskListStyle,
          subtitle: l10n.settingsTaskListStyleDescription,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in TaskListStyle.values)
                ChoiceChip(
                  label: Text(
                    option == TaskListStyle.modern
                        ? l10n.settingsTaskListModern
                        : l10n.settingsTaskListClassic,
                  ),
                  selected: style == option,
                  onSelected: (_) async {
                    try {
                      await ref
                          .read(taskListStyleProvider.notifier)
                          .setStyle(option);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.settingsSaveError)),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
        SettingsRow(
          title: l10n.settingsTaskRowSpacing,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in TaskRowSpacing.values)
                ChoiceChip(
                  label: Text(switch (option) {
                    TaskRowSpacing.compact =>
                      l10n.settingsTaskRowSpacingCompact,
                    TaskRowSpacing.comfortable =>
                      l10n.settingsTaskRowSpacingComfortable,
                    TaskRowSpacing.spacious =>
                      l10n.settingsTaskRowSpacingSpacious,
                  }),
                  selected: spacing == option,
                  onSelected: (_) async {
                    try {
                      await ref
                          .read(taskRowSpacingProvider.notifier)
                          .setSpacing(option);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.settingsSaveError)),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class DefaultTimedBlockDurationSettings extends ConsumerStatefulWidget {
  const DefaultTimedBlockDurationSettings({super.key});

  @override
  ConsumerState<DefaultTimedBlockDurationSettings> createState() =>
      _DefaultTimedBlockDurationSettingsState();
}

class _DefaultTimedBlockDurationSettingsState
    extends ConsumerState<DefaultTimedBlockDurationSettings> {
  static const _presets = [15, 30, 45, 60, 90, 120];

  final _controller = TextEditingController();
  int? _shownMinutes;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _showMinutes(
      ref.read(quickAddDefaultTimedBlockMinutesProvider),
      notify: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.listen<int>(
      quickAddDefaultTimedBlockMinutesProvider,
      (_, next) => _showMinutes(next),
    );
    final minutes = ref.watch(quickAddDefaultTimedBlockMinutesProvider);
    final timeDisplayMode = ref.watch(taskTimeDisplayModeProvider);
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l10n.settingsDefaultTimedBlockTitle,
          subtitle: l10n.settingsDefaultTimedBlockSubtitle,
          controlWidth: 320,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _presets)
                    ChoiceChip(
                      key: ValueKey('settings-default-block-$preset'),
                      label: Text(l10n.durationMinutes(preset)),
                      selected: minutes == preset,
                      onSelected: (_) => _setMinutes(preset),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('settings-default-timed-block-minutes-input'),
                controller: _controller,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l10n.settingsDefaultTimedBlockCustomLabel,
                  suffixText: l10n.minutesSuffix,
                  errorText: _errorText,
                  prefixIcon: const Icon(LucideIcons.clock),
                ),
                onChanged: _saveCustomMinutes,
              ),
            ],
          ),
        ),
        SettingsRow(
          title: l10n.settingsTaskTimeDisplayTitle,
          subtitle: l10n.settingsTaskTimeDisplaySubtitle,
          controlWidth: 320,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('settings-task-time-display-smart'),
                label: Text(l10n.settingsTaskTimeDisplaySmart),
                selected: timeDisplayMode == TaskTimeDisplayMode.smart,
                onSelected: (_) =>
                    _setTimeDisplayMode(TaskTimeDisplayMode.smart),
              ),
              ChoiceChip(
                key: const ValueKey('settings-task-time-display-range'),
                label: Text(l10n.settingsTaskTimeDisplayRange),
                selected: timeDisplayMode == TaskTimeDisplayMode.range,
                onSelected: (_) =>
                    _setTimeDisplayMode(TaskTimeDisplayMode.range),
              ),
              ChoiceChip(
                key: const ValueKey('settings-task-time-display-start-only'),
                label: Text(l10n.settingsTaskTimeDisplayStartOnly),
                selected: timeDisplayMode == TaskTimeDisplayMode.startOnly,
                onSelected: (_) =>
                    _setTimeDisplayMode(TaskTimeDisplayMode.startOnly),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMinutes(int minutes, {bool notify = true}) {
    if (_shownMinutes == minutes) {
      return;
    }
    void update() {
      _shownMinutes = minutes;
      _errorText = null;
      _controller.value = TextEditingValue(
        text: '$minutes',
        selection: TextSelection.collapsed(offset: '$minutes'.length),
      );
    }

    if (notify) {
      setState(update);
    } else {
      update();
    }
  }

  void _setMinutes(int minutes) {
    setState(() => _errorText = null);
    saveSetting(
      context,
      ref
          .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
          .setMinutes(minutes),
    );
  }

  void _saveCustomMinutes(String raw) {
    final minutes = int.tryParse(raw);
    if (minutes == null ||
        minutes < minQuickAddTimedBlockMinutes ||
        minutes > maxQuickAddTimedBlockMinutes) {
      setState(() => _errorText = context.l10n.settingsDefaultTimedBlockError);
      return;
    }
    setState(() => _errorText = null);
    saveSetting(
      context,
      ref
          .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
          .setMinutes(minutes),
    );
  }

  void _setTimeDisplayMode(TaskTimeDisplayMode mode) {
    saveSetting(
      context,
      ref.read(taskTimeDisplayModeProvider.notifier).setMode(mode),
    );
  }
}
