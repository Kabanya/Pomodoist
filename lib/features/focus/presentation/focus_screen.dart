import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/action_feedback.dart';
import '../../../app/widgets/resizable_dialog.dart';
import '../domain/focus_models.dart';
import 'focus_stage.dart';
import 'focus_view_mode.dart';

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  String? _selectedPresetId;
  String? _activePresetOverrideRunId;
  String? _activePresetOverridePresetId;

  @override
  Widget build(BuildContext context) {
    final runValue = ref.watch(activeFocusRunProvider);
    final intervalValue = ref.watch(activeFocusIntervalProvider);
    final presetsValue = ref.watch(focusPresetsProvider);
    final remaining = ref.watch(activeFocusRemainingProvider);
    final viewMode = ref.watch(focusViewModeProvider);
    final timerVisualStyle = ref.watch(focusTimerVisualStyleProvider);
    final lastPresetId = ref.watch(lastFocusPresetIdProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final runForIntervals = runValue.value;
    final intervalsValue = runForIntervals == null
        ? null
        : ref.watch(focusIntervalsForRunProvider(runForIntervals.id));
    final loadError = presetsValue.hasError
        ? presetsValue.error
        : runValue.hasError
        ? runValue.error
        : intervalValue.hasError
        ? intervalValue.error
        : intervalsValue?.hasError ?? false
        ? intervalsValue?.error
        : null;
    final loading =
        presetsValue.isLoading ||
        runValue.isLoading ||
        intervalValue.isLoading ||
        (intervalsValue?.isLoading ?? false);

    final run = runValue.value;
    final interval = intervalValue.value;
    final presets = presetsValue.value ?? const [];
    final intervals = _mergeActiveInterval(
      run: run,
      activeInterval: interval,
      history: intervalsValue?.value ?? const <FocusIntervalItem>[],
    );
    final selectedPreset = _findPreset(
      presets,
      run?.presetId ?? _selectedPresetId ?? lastPresetId,
    );
    final effectivePreset = selectedPreset ?? _defaultPreset(presets);
    final activePreset = run == null
        ? null
        : _findPreset(presets, _activePresetId(run)) ?? _defaultPreset(presets);

    return Material(
      color: context.appColors.canvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 720;
            return KeyedSubtree(
              key: Key(
                desktop ? 'focus-layout-desktop' : 'focus-layout-compact',
              ),
              child: ListView(
                key: const Key('focus-stage-scroll'),
                padding: EdgeInsets.fromLTRB(
                  desktop ? 32 : 16,
                  desktop ? 28 : 18,
                  desktop ? 32 : 16,
                  32,
                ),
                children: [
                  Align(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _FocusHeader(),
                          SizedBox(height: desktop ? 24 : 20),
                          loadError != null
                              ? _FocusLoadError(error: loadError)
                              : loading
                              ? const _FocusLoading()
                              : run == null && interval == null
                              ? FocusIdleStage(
                                  presets: presets,
                                  selectedPreset: effectivePreset,
                                  compact: !desktop,
                                  viewMode: viewMode,
                                  onViewModeChanged: _setViewMode,
                                  onPresetSelected: _selectPreset,
                                  onStart: effectivePreset == null
                                      ? null
                                      : () => _startFocus(
                                          focusRepository,
                                          effectivePreset,
                                        ),
                                  onCustomize: effectivePreset == null
                                      ? null
                                      : () => _showPresetDialog(
                                          effectivePreset,
                                          presets,
                                        ),
                                  onCreate: () =>
                                      _showPresetDialog(null, presets),
                                )
                              : run == null ||
                                    interval == null ||
                                    interval.runId != run.id ||
                                    remaining == null
                              ? const _FocusTransition()
                              : FocusActiveStage(
                                  run: run,
                                  interval: interval,
                                  intervals: intervals,
                                  remaining: remaining,
                                  presets: presets,
                                  selectedPreset: activePreset,
                                  timerVisualStyle: timerVisualStyle,
                                  compact: !desktop,
                                  viewMode: viewMode,
                                  repository: focusRepository,
                                  onViewModeChanged: _setViewMode,
                                  onPresetChanged: (presetId) =>
                                      _changeActiveRunPreset(run, presetId),
                                  onCustomizePreset: (preset) =>
                                      _showPresetDialog(preset, presets),
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showPresetDialog(
    FocusPresetItem? preset,
    List<FocusPresetItem> presets,
  ) async {
    final result = await showDialog<_PresetDialogResult>(
      context: context,
      builder: (context) => _PresetFormDialog(preset: preset, presets: presets),
    );
    if (result == null) {
      return;
    }

    final repository = ref.read(focusRepositoryProvider);
    switch (result.action) {
      case _PresetDialogAction.save:
        final data = result.data!;
        if (preset == null) {
          final id = await repository.createPreset(data.toCreateInput());
          if (mounted) {
            _selectPreset(id);
          }
        } else {
          await repository.updatePreset(preset.id, data.toUpdateInput());
        }
      case _PresetDialogAction.delete:
        if (preset != null) {
          await repository.deletePreset(preset.id);
          if (!mounted) {
            return;
          }
          if (_selectedPresetId == preset.id) {
            setState(() => _selectedPresetId = null);
          }
          if (ref.read(lastFocusPresetIdProvider) == preset.id) {
            unawaited(
              ref.read(lastFocusPresetIdProvider.notifier).setPresetId(null),
            );
          }
        }
      case _PresetDialogAction.setDefault:
        if (preset != null) {
          await repository.setDefaultPreset(preset.id);
        }
    }
  }

  Future<void> _startFocus(
    FocusRepository repository,
    FocusPresetItem preset,
  ) async {
    unawaited(
      ref.read(lastFocusPresetIdProvider.notifier).setPresetId(preset.id),
    );
    try {
      await repository.startRun(StartFocusRunInput(presetId: preset.id));
    } catch (_) {
      if (mounted) {
        showActionFeedback(
          context,
          message: context.l10n.focusActionFailed,
          icon: Icons.error_outline,
          sound: ActionFeedbackSound.none,
          haptic: AppHapticCue.none,
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    showActionFeedback(
      context,
      message: context.l10n.focusStarted,
      icon: Icons.play_circle_outline,
      haptic: AppHapticCue.none,
    );
  }

  void _selectPreset(String id) {
    if (!mounted) {
      return;
    }
    setState(() => _selectedPresetId = id);
    unawaited(ref.read(lastFocusPresetIdProvider.notifier).setPresetId(id));
  }

  void _setViewMode(FocusViewMode mode) {
    unawaited(ref.read(focusViewModeProvider.notifier).setMode(mode));
  }

  FocusPresetItem? _findPreset(List<FocusPresetItem> presets, String? id) {
    if (id == null) {
      return null;
    }
    for (final preset in presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  FocusPresetItem? _defaultPreset(List<FocusPresetItem> presets) {
    for (final preset in presets) {
      if (preset.isDefault) {
        return preset;
      }
    }
    return presets.isEmpty ? null : presets.first;
  }

  String _activePresetId(FocusRunItem run) {
    final overrideId = _activePresetOverridePresetId;
    if (_activePresetOverrideRunId == run.id &&
        overrideId != null &&
        overrideId != run.presetId) {
      return overrideId;
    }
    return run.presetId;
  }

  void _changeActiveRunPreset(FocusRunItem run, String presetId) {
    setState(() {
      _activePresetOverrideRunId = run.id;
      _activePresetOverridePresetId = presetId;
    });
    unawaited(
      ref.read(focusRepositoryProvider).changeActiveRunPreset(presetId),
    );
    unawaited(
      ref.read(lastFocusPresetIdProvider.notifier).setPresetId(presetId),
    );
  }
}

List<FocusIntervalItem> _mergeActiveInterval({
  required FocusRunItem? run,
  required FocusIntervalItem? activeInterval,
  required List<FocusIntervalItem> history,
}) {
  if (run == null || activeInterval == null || activeInterval.runId != run.id) {
    return history;
  }
  return [
    for (final interval in history)
      if (interval.id != activeInterval.id &&
          (interval.runId != activeInterval.runId ||
              interval.sequenceNumber != activeInterval.sequenceNumber))
        interval,
    activeInterval,
  ];
}

class _FocusLoading extends StatelessWidget {
  const _FocusLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: CircularProgressIndicator(key: Key('focus-loading')),
      ),
    );
  }
}

class _FocusLoadError extends StatelessWidget {
  const _FocusLoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
        child: Text(
          context.l10n.focusLoadError(error),
          key: const Key('focus-load-error'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FocusTransition extends StatelessWidget {
  const _FocusTransition();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('focus-state-transition'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.preparingFocus),
          ],
        ),
      ),
    );
  }
}

class _FocusHeader extends StatelessWidget {
  const _FocusHeader();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('focus-heading'),
      header: true,
      child: Text(
        context.l10n.focusTitle,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}

class _PresetFormDialog extends StatefulWidget {
  const _PresetFormDialog({required this.preset, required this.presets});

  final FocusPresetItem? preset;
  final List<FocusPresetItem> presets;

  @override
  State<_PresetFormDialog> createState() => _PresetFormDialogState();
}

class _PresetFormDialogState extends State<_PresetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _workController;
  late final TextEditingController _shortBreakController;
  late final TextEditingController _longBreakController;
  late final TextEditingController _cadenceController;
  late bool _autoStartBreaks;
  late bool _autoStartWork;
  late bool _allowPause;
  late bool _strictMode;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    _nameController = TextEditingController(text: preset?.name ?? '');
    _workController = TextEditingController(
      text: _minutesText(preset?.workSeconds ?? 25 * 60),
    );
    _shortBreakController = TextEditingController(
      text: _minutesText(preset?.shortBreakSeconds ?? 5 * 60),
    );
    _longBreakController = TextEditingController(
      text: _minutesText(preset?.longBreakSeconds ?? 15 * 60),
    );
    _cadenceController = TextEditingController(
      text: '${preset?.intervalsBeforeLongBreak ?? 4}',
    );
    _autoStartBreaks = preset?.autoStartBreaks ?? false;
    _autoStartWork = preset?.autoStartWork ?? false;
    _allowPause = preset?.allowPause ?? true;
    _strictMode = preset?.strictMode ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _workController.dispose();
    _shortBreakController.dispose();
    _longBreakController.dispose();
    _cadenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preset = widget.preset;
    return ResizableDialog(
      title: Text(preset == null ? l10n.newPreset : l10n.customizePreset),
      initialSize: const Size(680, 620),
      minSize: const Size(360, 420),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('preset-name-field'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.name,
                prefixIcon: const Icon(Icons.label_outline),
              ),
              textInputAction: TextInputAction.next,
              validator: _validateName,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 440;
                final fieldWidth = twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: _MinutesField(
                        fieldKey: const Key('preset-work-minutes-field'),
                        controller: _workController,
                        label: l10n.workField,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _MinutesField(
                        fieldKey: const Key('preset-short-break-minutes-field'),
                        controller: _shortBreakController,
                        label: l10n.shortField,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _MinutesField(
                        fieldKey: const Key('preset-long-break-minutes-field'),
                        controller: _longBreakController,
                        label: l10n.longField,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        key: const Key('preset-cadence-field'),
                        controller: _cadenceController,
                        decoration: InputDecoration(
                          labelText: l10n.every,
                          suffixText: l10n.work,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) =>
                            _validateRange(value, min: 1, max: 12),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoStartBreaks,
              onChanged: (value) => setState(() => _autoStartBreaks = value),
              title: Text(l10n.autoStartBreaks),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoStartWork,
              onChanged: (value) => setState(() => _autoStartWork = value),
              title: Text(l10n.autoStartWork),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allowPause,
              onChanged: (value) => setState(() => _allowPause = value),
              title: Text(l10n.allowPause),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _strictMode,
              onChanged: (value) => setState(() => _strictMode = value),
              title: Text(l10n.strictMode),
            ),
          ],
        ),
      ),
      actions: [
        if (preset != null && !preset.isDefault)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _PresetDialogResult.delete()),
            child: Text(l10n.commonDelete),
          ),
        if (preset != null && !preset.isDefault)
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const _PresetDialogResult.setDefault()),
            child: Text(l10n.makeDefault),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('preset-save-button'),
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _PresetDialogResult.save(
        _PresetFormData(
          name: _nameController.text.trim(),
          workSeconds: _parseMinutes(_workController) * 60,
          shortBreakSeconds: _parseMinutes(_shortBreakController) * 60,
          longBreakSeconds: _parseMinutes(_longBreakController) * 60,
          intervalsBeforeLongBreak: int.parse(_cadenceController.text),
          autoStartBreaks: _autoStartBreaks,
          autoStartWork: _autoStartWork,
          allowPause: _allowPause,
          strictMode: _strictMode,
        ),
      ),
    );
  }

  String? _validateName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return context.l10n.nameRequired;
    }
    final duplicate = widget.presets.any(
      (preset) =>
          preset.id != widget.preset?.id &&
          preset.name.trim().toLowerCase() == trimmed.toLowerCase(),
    );
    if (duplicate) {
      return context.l10n.nameMustBeUnique;
    }
    return null;
  }

  static String? _validateRange(
    String? value, {
    required int min,
    required int max,
  }) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < min || parsed > max) {
      return '$min-$max';
    }
    return null;
  }

  static int _parseMinutes(TextEditingController controller) {
    return int.parse(controller.text);
  }

  static String _minutesText(int seconds) => '${(seconds / 60).round()}';
}

class _MinutesField extends StatelessWidget {
  const _MinutesField({
    required this.fieldKey,
    required this.controller,
    required this.label,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: context.l10n.minutesSuffix,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) =>
          _PresetFormDialogState._validateRange(value, min: 1, max: 180),
    );
  }
}

enum _PresetDialogAction { save, delete, setDefault }

class _PresetDialogResult {
  const _PresetDialogResult._(this.action, this.data);

  const _PresetDialogResult.save(_PresetFormData data)
    : this._(_PresetDialogAction.save, data);

  const _PresetDialogResult.delete() : this._(_PresetDialogAction.delete, null);

  const _PresetDialogResult.setDefault()
    : this._(_PresetDialogAction.setDefault, null);

  final _PresetDialogAction action;
  final _PresetFormData? data;
}

class _PresetFormData {
  const _PresetFormData({
    required this.name,
    required this.workSeconds,
    required this.shortBreakSeconds,
    required this.longBreakSeconds,
    required this.intervalsBeforeLongBreak,
    required this.autoStartBreaks,
    required this.autoStartWork,
    required this.allowPause,
    required this.strictMode,
  });

  final String name;
  final int workSeconds;
  final int shortBreakSeconds;
  final int longBreakSeconds;
  final int intervalsBeforeLongBreak;
  final bool autoStartBreaks;
  final bool autoStartWork;
  final bool allowPause;
  final bool strictMode;

  CreateFocusPresetInput toCreateInput() => CreateFocusPresetInput(
    name: name,
    workSeconds: workSeconds,
    shortBreakSeconds: shortBreakSeconds,
    longBreakSeconds: longBreakSeconds,
    intervalsBeforeLongBreak: intervalsBeforeLongBreak,
    autoStartBreaks: autoStartBreaks,
    autoStartWork: autoStartWork,
    allowPause: allowPause,
    strictMode: strictMode,
  );

  UpdateFocusPresetInput toUpdateInput() => UpdateFocusPresetInput(
    name: name,
    workSeconds: workSeconds,
    shortBreakSeconds: shortBreakSeconds,
    longBreakSeconds: longBreakSeconds,
    intervalsBeforeLongBreak: intervalsBeforeLongBreak,
    autoStartBreaks: autoStartBreaks,
    autoStartWork: autoStartWork,
    allowPause: allowPause,
    strictMode: strictMode,
  );
}
