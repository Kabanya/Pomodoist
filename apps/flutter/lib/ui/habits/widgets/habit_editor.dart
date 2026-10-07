import 'package:flutter/material.dart';
import 'package:pomodoist/routing/habit_detail_navigation.dart';
import 'package:pomodoist/ui/core/widgets/task_details_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/ui/habits/widgets/habit_icon.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';

String habitDayPeriodLabel(BuildContext context, HabitDayPeriod period) {
  final l = context.l10n;
  return switch (period) {
    HabitDayPeriod.automatic => l.habitPeriodAutomatic,
    HabitDayPeriod.anytime => l.habitPeriodAnytime,
    HabitDayPeriod.morning => l.calendarMorning,
    HabitDayPeriod.afternoon => l.calendarAfternoon,
    HabitDayPeriod.evening => l.calendarEvening,
    HabitDayPeriod.night => l.habitPeriodNight,
  };
}

class HabitDetailsHost extends ConsumerWidget {
  const HabitDetailsHost({
    required this.habitId,
    required this.child,
    super.key,
  });

  final String? habitId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void close() {
      if (!ref.read(habitsViewModelProvider).saving) closeHabitDetails(context);
    }

    return DetailsPanelHost(
      onClose: close,
      panel: habitId == null
          ? null
          : SafeArea(
              child: _HabitDetailsContent(habitId: habitId!, onClose: close),
            ),
      child: child,
    );
  }
}

class _HabitDetailsContent extends ConsumerWidget {
  const _HabitDetailsContent({required this.habitId, required this.onClose});

  final String habitId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (habitId == newHabitDetailsId) {
      return HabitEditor(key: ValueKey(habitId), onClose: onClose);
    }
    final view = ref.watch(habitsViewModelProvider);
    final habit = view.habits.where((habit) => habit.id == habitId).firstOrNull;
    if (habit != null) {
      return HabitEditor(
        key: ValueKey(habitId),
        habit: habit,
        onClose: onClose,
      );
    }
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              tooltip: l.commonClose,
              onPressed: onClose,
              icon: const Icon(LucideIcons.x),
            ),
          ),
          Expanded(
            child: Center(
              child: view.loading
                  ? const CircularProgressIndicator()
                  : Text(view.loadError ? l.habitLoadError : l.habitsEmpty),
            ),
          ),
          if (view.loadError)
            ShadButton.ghost(
              onPressed: ref.read(habitsViewModelProvider.notifier).retry,
              child: Text(l.commonRetry),
            ),
        ],
      ),
    );
  }
}

class HabitEditor extends ConsumerStatefulWidget {
  const HabitEditor({this.habit, required this.onClose, super.key});
  final Habit? habit;
  final VoidCallback onClose;
  @override
  ConsumerState<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends ConsumerState<HabitEditor> {
  late final TextEditingController _title, _target;
  late DateTime _start;
  DateTime? _end;
  late Set<int> _weekdays;
  late bool _daily, _reminder;
  late TimeOfDay _time;
  late HabitDayPeriod _dayPeriod;
  late bool _customPeriods;
  late final Set<HabitDayPeriod> _selectedPeriods;
  late final Map<HabitDayPeriod, TextEditingController> _periodControllers;
  Map<HabitDayPeriod, int> get _periodTargets => {
    for (final p in _selectedPeriods)
      p: int.tryParse(_periodControllers[p]!.text) ?? 0,
  };
  String? _icon, _project;
  int _duration = 0;
  bool _error = false;
  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    final schedule = habit?.scheduleHistory.last;
    _icon = habit?.icon;
    _title = TextEditingController(text: habit?.title ?? '');
    _target = TextEditingController(text: '${schedule?.targetPerDay ?? 1}');
    _target.addListener(_targetChanged);
    _dayPeriod = schedule?.dayPeriod ?? HabitDayPeriod.automatic;
    final targets = schedule?.periodTargets ?? <HabitDayPeriod, int>{};
    final manual =
        _dayPeriod != HabitDayPeriod.automatic &&
        _dayPeriod != HabitDayPeriod.anytime;
    _customPeriods = targets.isNotEmpty || manual;
    _selectedPeriods = targets.isNotEmpty
        ? targets.keys.toSet()
        : manual
        ? {_dayPeriod}
        : {};
    _periodControllers = {
      for (final p in HabitDayPeriod.values.skip(2))
        p: TextEditingController(
          text:
              '${targets[p] ?? (manual && p == _dayPeriod ? schedule!.targetPerDay : 1)}',
        )..addListener(_targetChanged),
    };
    _start = schedule?.startDate ?? ref.read(habitsViewModelProvider).today;
    _end = schedule?.endDate;
    _duration = _end == null ? 0 : -1;
    _weekdays = (schedule?.weekdays ?? [1, 2, 3, 4, 5, 6, 7]).toSet();
    _daily = _weekdays.length == 7;
    _reminder = habit?.reminderMinutes != null;
    final minutes = habit?.reminderMinutes ?? 1200;
    _time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    final projects = ref.read(habitsViewModelProvider).projects;
    _project = projects.any((p) => p.id == habit?.projectId)
        ? habit?.projectId
        : null;
  }

  void _targetChanged() => setState(() {});

  @override
  void dispose() {
    for (final controller in _periodControllers.values) {
      controller.removeListener(_targetChanged);
      controller.dispose();
    }
    _title.dispose();
    _target.removeListener(_targetChanged);
    _target.dispose();
    super.dispose();
  }

  String _date(DateTime day) =>
      DateFormat.yMMMd(context.l10n.localeName).format(day);
  Future<void> _pickDate(bool start, AppDateTimePickerState picker) async {
    final selected = await picker.pickDate(
      initialDate: start ? _start : (_end ?? _start),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: start ? context.l10n.habitStart : context.l10n.habitEnd,
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _start = selected;
        if (_duration > 0) _end = habitEndAfterDays(_start, _duration);
      } else {
        _end = selected;
        _duration = -1;
      }
    });
  }

  Future<void> _save() async {
    if (_customPeriods && _selectedPeriods.isEmpty) {
      setState(() => _error = true);
      return;
    }
    final saved = await ref
        .read(habitsViewModelProvider.notifier)
        .save(
          id: widget.habit?.id,
          title: _title.text,
          icon: _icon,
          startDate: _start,
          endDate: _end,
          weekdays: _daily
              ? [1, 2, 3, 4, 5, 6, 7]
              : (_weekdays.toList()..sort()),
          target: _target.text,
          projectId:
              ref
                  .read(habitsViewModelProvider)
                  .projects
                  .any((p) => p.id == _project)
              ? _project
              : null,
          reminderMinutes: _reminder ? _time.hour * 60 + _time.minute : null,
          dayPeriod: _customPeriods ? HabitDayPeriod.automatic : _dayPeriod,
          periodTargets: _customPeriods ? _periodTargets : const {},
        );
    if (!mounted) return;
    if (saved) {
      widget.onClose();
    } else {
      setState(() => _error = true);
    }
  }

  Widget _field(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Semantics(label: label, child: child),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final l = context.l10n, view = ref.watch(habitsViewModelProvider);
    final colors = context.appColors;
    final allowed = view.reminderStatus != HabitReminderStatus.unsupported;
    final reminderMessage = switch (view.reminderStatus) {
      HabitReminderStatus.denied => l.habitReminderDenied,
      HabitReminderStatus.unsupported => l.habitReminderUnavailable,
      HabitReminderStatus.failed => l.habitReminderFailed,
      _ => null,
    };
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.habit == null ? l.habitNew : l.habitEdit,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Tooltip(
                  message: l.commonClose,
                  child: ShadIconButton.ghost(
                    enabled: !view.saving,
                    onPressed: widget.onClose,
                    width: 44,
                    height: 44,
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(
                      l.habitName,
                      Row(
                        children: [
                          HabitIconButton(
                            icon: _icon,
                            onPressed: view.saving
                                ? null
                                : () => showHabitIconPicker(
                                    context,
                                    icon: _icon,
                                    onSave: (icon) async {
                                      if (!mounted) return false;
                                      setState(() => _icon = icon);
                                      return true;
                                    },
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ShadInput(
                              controller: _title,
                              maxLength: 200,
                              enabled: !view.saving,
                              placeholder: Text(l.habitName),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _field(
                      l.habitFrequency,
                      ShadTabs<bool>(
                        value: _daily,
                        scrollable: true,
                        gap: 0,
                        tabBarAlignment: AlignmentDirectional.centerStart
                            .resolve(Directionality.of(context)),
                        tabs: [
                          ShadTab(
                            value: true,
                            height: 44,
                            enabled: !view.saving,
                            child: Text(l.habitDaily),
                          ),
                          ShadTab(
                            value: false,
                            height: 44,
                            enabled: !view.saving,
                            child: Text(l.habitWeekdays),
                          ),
                        ],
                        onChanged: (value) => setState(() => _daily = value),
                      ),
                    ),
                    if (!_daily)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (var d = 1; d <= 7; d++)
                              Semantics(
                                selected: _weekdays.contains(d),
                                child: ShadButton.secondary(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  backgroundColor: _weekdays.contains(d)
                                      ? colors.accentTint
                                      : colors.surfaceTint,
                                  foregroundColor: _weekdays.contains(d)
                                      ? colors.accent
                                      : colors.secondaryText,
                                  enabled: !view.saving,
                                  onPressed: () => setState(
                                    () => _weekdays.contains(d)
                                        ? _weekdays.remove(d)
                                        : _weekdays.add(d),
                                  ),
                                  child: Text(
                                    DateFormat.E(
                                      l.localeName,
                                    ).format(DateTime(2026, 9, 28 + d - 1)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (!_customPeriods)
                      _field(
                        l.habitTarget,
                        ShadInput(
                          controller: _target,
                          enabled: !view.saving,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                        ),
                      ),
                    _field(
                      l.habitDayPeriod,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ShadSelect<String>(
                            key: ValueKey(
                              _customPeriods ? 'custom' : _dayPeriod.name,
                            ),
                            initialValue: _customPeriods
                                ? 'custom'
                                : _dayPeriod.name,
                            enabled: !view.saving,
                            padding: const EdgeInsets.all(12),
                            options: [
                              ShadOption(
                                value: 'automatic',
                                child: Text(l.habitPeriodAutomatic),
                              ),
                              ShadOption(
                                value: 'anytime',
                                child: Text(l.habitPeriodAnytime),
                              ),
                              ShadOption(
                                value: 'custom',
                                child: Text(l.habitPeriodCustom),
                              ),
                            ],
                            selectedOptionBuilder: (context, mode) => Text(
                              mode == 'custom'
                                  ? l.habitPeriodCustom
                                  : habitDayPeriodLabel(
                                      context,
                                      HabitDayPeriod.values.byName(mode),
                                    ),
                            ),
                            onChanged: (mode) {
                              if (mode == null) return;
                              if (_customPeriods && mode != 'custom') {
                                final total = _periodTargets.values.fold(
                                  0,
                                  (a, b) => a + b,
                                );
                                if (total >= 1 && total <= 99) {
                                  _target.text = '$total';
                                }
                              }
                              if (mode == 'custom' &&
                                  _selectedPeriods.isEmpty) {
                                _periodControllers[HabitDayPeriod.morning]!
                                        .text =
                                    _target.text;
                              }
                              setState(() {
                                _customPeriods = mode == 'custom';
                                if (!_customPeriods) {
                                  _dayPeriod = HabitDayPeriod.values.byName(
                                    mode,
                                  );
                                }
                                if (_customPeriods &&
                                    _selectedPeriods.isEmpty) {
                                  _selectedPeriods.add(HabitDayPeriod.morning);
                                }
                              });
                            },
                          ),
                          if (_customPeriods) ...[
                            const SizedBox(height: 12),
                            Text(
                              l.habitPeriodTargetsHint,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.mutedText),
                            ),
                            for (final period in HabitDayPeriod.values.skip(2))
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ShadCheckbox(
                                        value: _selectedPeriods.contains(
                                          period,
                                        ),
                                        enabled: !view.saving,
                                        onChanged: (selected) => setState(
                                          () => selected
                                              ? _selectedPeriods.add(period)
                                              : _selectedPeriods.remove(period),
                                        ),
                                        label: Text(
                                          habitDayPeriodLabel(context, period),
                                        ),
                                      ),
                                    ),
                                    if (_selectedPeriods.contains(period))
                                      SizedBox(
                                        width: 72,
                                        child: Semantics(
                                          label:
                                              '${habitDayPeriodLabel(context, period)}: ${l.habitTarget}',
                                          child: ShadInput(
                                            controller:
                                                _periodControllers[period],
                                            enabled: !view.saving,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                              LengthLimitingTextInputFormatter(
                                                2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            Text(
                              '${l.habitTarget}: ${_periodTargets.values.fold(0, (a, b) => a + b)}',
                            ),
                          ],
                          if (!_customPeriods &&
                              _dayPeriod == HabitDayPeriod.automatic) ...[
                            const SizedBox(height: 8),
                            Text(
                              l.habitPeriodExplanation(
                                habitDayPeriodLabel(
                                  context,
                                  resolveHabitDayPeriod(
                                    target: int.tryParse(_target.text) ?? 1,
                                    reminderMinutes: _reminder
                                        ? _time.hour * 60 + _time.minute
                                        : null,
                                  ),
                                ),
                                (int.tryParse(_target.text) ?? 1) > 1
                                    ? l.habitPeriodMultipleReason
                                    : !_reminder
                                    ? l.habitPeriodNoTimeReason
                                    : l.habitPeriodReminderReason,
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.mutedText),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _field(
                      l.habitStart,
                      AppDateTimePicker(
                        builder: (context, picker) => ShadButton.outline(
                          enabled: !view.saving,
                          height: 44,
                          foregroundColor: colors.primaryText,
                          onPressed: () => _pickDate(true, picker),
                          leading: Icon(
                            LucideIcons.calendar,
                            size: 16,
                            color: colors.secondaryText,
                          ),
                          child: Text(_date(_start)),
                        ),
                      ),
                    ),
                    _field(
                      l.habitEnd,
                      ShadSelect<int>(
                        key: ValueKey(_duration),
                        initialValue: _duration,
                        enabled: !view.saving,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        options: [
                          ShadOption(value: 0, child: Text(l.habitForever)),
                          for (final d in [7, 21, 30, 365])
                            ShadOption(
                              value: d,
                              child: Text(l.habitDurationDays(d)),
                            ),
                          ShadOption(value: -1, child: Text(l.habitCustom)),
                        ],
                        selectedOptionBuilder: (context, value) => Text(
                          value == 0
                              ? l.habitForever
                              : value == -1
                              ? l.habitCustom
                              : l.habitDurationDays(value),
                        ),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _duration = value;
                            _end = value == 0
                                ? null
                                : value > 0
                                ? habitEndAfterDays(_start, value)
                                : (_end ?? _start);
                          });
                        },
                      ),
                    ),
                    if (_end != null)
                      _field(
                        l.habitEnd,
                        AppDateTimePicker(
                          builder: (context, picker) => ShadButton.outline(
                            enabled: !view.saving,
                            height: 44,
                            foregroundColor: colors.primaryText,
                            onPressed: () => _pickDate(false, picker),
                            leading: Icon(
                              LucideIcons.calendar,
                              size: 16,
                              color: colors.secondaryText,
                            ),
                            child: Text(_date(_end!)),
                          ),
                        ),
                      ),
                    _field(
                      l.habitProject,
                      ShadSelect<String>(
                        key: ValueKey(_project),
                        initialValue: _project ?? '',
                        enabled: !view.saving,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        options: [
                          ShadOption(value: '', child: Text(l.habitNoProject)),
                          for (final p in view.projects)
                            ShadOption(value: p.id, child: Text(p.name)),
                        ],
                        selectedOptionBuilder: (context, value) => Text(
                          view.projects
                                  .where((p) => p.id == value)
                                  .firstOrNull
                                  ?.name ??
                              l.habitNoProject,
                        ),
                        onChanged: (value) => setState(
                          () => _project = value == '' ? null : value,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: allowed && !view.saving
                          ? () => setState(() => _reminder = !_reminder)
                          : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.habitReminder,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Semantics(
                              label: l.habitReminder,
                              child: ShadSwitch(
                                value: _reminder,
                                enabled: allowed && !view.saving,
                                onChanged: (value) =>
                                    setState(() => _reminder = value),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_reminder)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _field(
                          l.habitReminderTime,
                          AppDateTimePicker(
                            builder: (context, picker) => ShadButton.outline(
                              enabled: allowed && !view.saving,
                              height: 44,
                              foregroundColor: colors.primaryText,
                              leading: Icon(
                                LucideIcons.clock,
                                size: 16,
                                color: colors.secondaryText,
                              ),
                              onPressed: () async {
                                final value = await picker.pickTime(
                                  initialTime: _time,
                                  helpText: l.habitReminderTime,
                                );
                                if (value != null && mounted) {
                                  setState(() => _time = value);
                                }
                              },
                              child: Text(_time.format(context)),
                            ),
                          ),
                        ),
                      ),
                    if (reminderMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          reminderMessage,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.mutedText),
                        ),
                      ),
                    if (view.reminderStatus == HabitReminderStatus.failed)
                      ShadButton.ghost(
                        onPressed: () => ref
                            .read(habitsViewModelProvider.notifier)
                            .retryReminders(),
                        child: Text(l.commonRetry),
                      ),
                    if (_error)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          l.habitSaveError,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ShadButton(
              enabled: !view.saving,
              onPressed: _save,
              leading: view.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              child: Text(l.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}
