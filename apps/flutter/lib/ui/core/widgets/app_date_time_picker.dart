import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/localization/app_date_formatter.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:pomodoist/ui/core/themes/app_theme.dart';

/// A persistent anchor for date/time panels, including inside manual overlays.
class AppDateTimePicker extends StatefulWidget {
  const AppDateTimePicker({required this.builder, super.key});

  final Widget Function(BuildContext context, AppDateTimePickerState picker)
  builder;

  /// Manual overlay hosts can let the focused picker handle Back first.
  static bool dismissFocused() {
    final picker = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<AppDateTimePickerState>();
    if (picker?._request == null) return false;
    picker!._finish(null);
    return true;
  }

  @override
  State<AppDateTimePicker> createState() => AppDateTimePickerState();
}

class AppDateTimePickerState extends State<AppDateTimePicker> {
  final focusNode = FocusNode();
  final _popover = ShadPopoverController();
  final _group = Object();
  Completer<Object?>? _request;
  Widget _content = const SizedBox.shrink();
  double _panelWidth = 440;
  LocalHistoryEntry? _backEntry;
  ({Rect anchor, Size size})? _geometry;
  ScrollNotificationObserverState? _scrollObserver;
  bool _geometryUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _popover.addListener(_onToggle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (observer != _scrollObserver) {
      _scrollObserver?.removeListener(_onScroll);
      _scrollObserver = observer;
      _scrollObserver?.addListener(_onScroll);
    }
  }

  void _onScroll(ScrollNotification notification) => _scheduleGeometryUpdate();

  ({Rect anchor, Size size})? _readGeometry() {
    final trigger = context.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (trigger is! RenderBox ||
        !trigger.hasSize ||
        overlay is! RenderBox ||
        !overlay.hasSize) {
      return null;
    }
    return (
      anchor: Rect.fromPoints(
        trigger.localToGlobal(Offset.zero, ancestor: overlay),
        trigger.localToGlobal(
          trigger.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      size: overlay.size,
    );
  }

  void _scheduleGeometryUpdate() {
    if (_request == null || _geometryUpdateScheduled) return;
    _geometryUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryUpdateScheduled = false;
      if (!mounted || _request == null) return;
      final geometry = _readGeometry();
      if (geometry != _geometry) setState(() => _geometry = geometry);
    });
  }

  Future<DateTime?> pickDate({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    String? helpText,
  }) => _show<DateTime>(
    (submit) => _DatePanel(
      key: UniqueKey(),
      initialDate: initialDate,
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      helpText: helpText,
      groupId: _group,
      onSubmit: (value) => submit(value.date),
      onCancel: () => _finish(null),
    ),
    width: 560,
  );

  /// Edits a local schedule draft; a null time represents an all-day task.
  Future<({DateTime date, TimeOfDay? time})?> pickSchedule({
    required DateTime initialDate,
    required TimeOfDay initialTime,
    required bool initialAllDay,
    required DateTime firstDate,
    required DateTime lastDate,
    String? helpText,
  }) => _show<({DateTime date, TimeOfDay? time})>(
    (submit) => _DatePanel(
      key: UniqueKey(),
      initialDate: initialDate,
      initialTime: initialTime,
      initialAllDay: initialAllDay,
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      helpText: helpText,
      groupId: _group,
      onSubmit: submit,
      onCancel: () => _finish(null),
    ),
    width: 680,
  );

  Future<TimeOfDay?> pickTime({
    required TimeOfDay initialTime,
    String? helpText,
  }) {
    if (!mounted) return Future.value(null);
    final material = MaterialLocalizations.of(context);
    final use24Hours = pickerUses24Hours(
      material,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return _show<TimeOfDay>(
      (submit) => _TimePanel(
        key: UniqueKey(),
        initialTime: initialTime,
        use24Hours: use24Hours,
        helpText: helpText,
        onSubmit: submit,
        onCancel: () => _finish(null),
      ),
    );
  }

  Future<T?> _show<T>(
    Widget Function(ValueChanged<T>) content, {
    double width = 440,
  }) async {
    // Context-menu items dismiss after invoking their callback.
    await Future<void>.value();
    if (!mounted) return null;
    _finish(null);
    final request = Completer<Object?>();
    setState(() {
      _request = request;
      _panelWidth = width;
      _geometry = _readGeometry();
      _content = content((value) {
        if (identical(_request, request)) _finish(value);
      });
    });
    if (Router.maybeOf(context) == null) {
      final route = ModalRoute.of(context);
      if (route != null) {
        _backEntry = LocalHistoryEntry(
          onRemove: () {
            _backEntry = null;
            _finish(null);
          },
        );
        route.addLocalHistoryEntry(_backEntry!);
      }
    }
    _popover.show();
    return await request.future as T?;
  }

  void _onToggle() {
    if (!_popover.isOpen) _finish(null);
  }

  void _finish(Object? result) {
    final request = _request;
    if (request == null) return;
    _request = null;
    final back = _backEntry;
    _backEntry = null;
    back?.remove();
    _popover.hide();
    request.complete(result);
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _request == null) focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    final request = _request;
    _request = null;
    _backEntry?.remove();
    request?.complete(null);
    _scrollObserver?.removeListener(_onScroll);
    _popover.removeListener(_onToggle);
    _popover.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localMedia = MediaQuery.of(context);
    final media = MediaQuery.maybeOf(Overlay.of(context).context) ?? localMedia;
    final colors = context.appColors;
    _scheduleGeometryUpdate();
    final anchor =
        _geometry?.anchor ??
        Rect.fromCenter(
          center: media.size.center(Offset.zero),
          width: 0,
          height: 0,
        );
    final space = pickerAvailableSpace(
      anchor,
      _geometry?.size ?? media.size,
      viewPadding: media.viewPadding,
      viewInsets: media.viewInsets,
    );
    // Include the popover's padding and border in the available rectangle.
    final width = math.max(1.0, math.min(_panelWidth - 26, space.width - 26));
    final height = math.max(1.0, space.height - 26);
    final centerX = space.width <= width + 26
        ? space.center.dx
        : anchor.center.dx.clamp(
            space.left + (width + 26) / 2,
            space.right - (width + 26) / 2,
          );
    final panel = ShadPopover(
      controller: _popover,
      groupId: _group,
      // Start inside the chosen visible area: its top stays valid even when
      // calendar rows, text scale, or validation messages change the height.
      anchor: ShadGlobalAnchor(Offset(centerX, space.top)),
      padding: const EdgeInsets.all(12),
      decoration: ShadDecoration(
        color: colors.surface,
        border: ShadBorder.all(
          color: colors.border,
          radius: BorderRadius.circular(12),
        ),
      ),
      popover: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: height),
        child: SizedBox(
          width: width,
          child: Material(type: MaterialType.transparency, child: _content),
        ),
      ),
      child: widget.builder(context, this),
    );
    if (Router.maybeOf(context) == null) return panel;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (_request == null) return false;
        _finish(null);
        return true;
      },
      child: panel,
    );
  }
}

/// Chooses a visible rectangle above or below the trigger in overlay coordinates.
Rect pickerAvailableSpace(
  Rect anchor,
  Size viewport, {
  EdgeInsets viewPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  final left = (math.max(viewPadding.left, viewInsets.left) + 12).clamp(
    0.0,
    viewport.width,
  );
  final top = (math.max(viewPadding.top, viewInsets.top) + 12).clamp(
    0.0,
    viewport.height,
  );
  final visible = Rect.fromLTRB(
    left,
    top,
    math.max(
      left,
      viewport.width - math.max(viewPadding.right, viewInsets.right) - 12,
    ),
    math.max(
      top,
      viewport.height - math.max(viewPadding.bottom, viewInsets.bottom) - 12,
    ),
  );
  final aboveBottom = (anchor.top - 8).clamp(visible.top, visible.bottom);
  final belowTop = (anchor.bottom + 8).clamp(visible.top, visible.bottom);
  final above = aboveBottom - visible.top;
  final below = visible.bottom - belowTop;
  // If neither side can hold a control, use the visible area and allow overlap.
  if (math.max(above, below) < 48) return visible;
  return above > below
      ? Rect.fromLTRB(visible.left, visible.top, visible.right, aboveBottom)
      : Rect.fromLTRB(visible.left, belowTop, visible.right, visible.bottom);
}

bool pickerUses24Hours(
  MaterialLocalizations material, {
  required bool alwaysUse24HourFormat,
}) => switch (material.timeOfDayFormat(
  alwaysUse24HourFormat: alwaysUse24HourFormat,
)) {
  TimeOfDayFormat.h_colon_mm_space_a ||
  TimeOfDayFormat.a_space_h_colon_mm => false,
  _ => true,
};

// Material numbers Sunday as 0; ShadCalendar compares DateTime.weekday (1–7).
int pickerWeekStartsOn(MaterialLocalizations material) =>
    material.firstDayOfWeekIndex == 0
    ? DateTime.sunday
    : material.firstDayOfWeekIndex;

/// Validates localized keyboard input against the caller's existing date range.
DateTime? parsePickerDate(
  String text,
  MaterialLocalizations material, {
  required DateTime firstDate,
  required DateTime lastDate,
  AppDateFormatter? formatter,
}) {
  final date = formatter == null
      ? material.parseCompactDate(text.trim())
      : formatter.parse(text);
  if (date == null ||
      date.isBefore(DateUtils.dateOnly(firstDate)) ||
      date.isAfter(DateUtils.dateOnly(lastDate))) {
    return null;
  }
  return date;
}

/// Converts editable clock fields; an empty field never reuses an old value.
TimeOfDay? parsePickerTime(
  String hourText,
  String minuteText, {
  required bool use24Hours,
  required DayPeriod period,
}) {
  final hour = int.tryParse(hourText);
  final minute = int.tryParse(minuteText);
  if (hour == null ||
      minute == null ||
      hourText.length > 2 ||
      minuteText.length > 2 ||
      minute < 0 ||
      minute > 59 ||
      hour < (use24Hours ? 0 : 1) ||
      hour > (use24Hours ? 23 : 12)) {
    return null;
  }
  return TimeOfDay(
    hour: use24Hours ? hour : hour % 12 + (period == DayPeriod.pm ? 12 : 0),
    minute: minute,
  );
}

class _DatePanel extends StatefulWidget {
  const _DatePanel({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.groupId,
    required this.onSubmit,
    required this.onCancel,
    this.initialTime,
    this.initialAllDay = true,
    this.helpText,
    super.key,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Object groupId;
  final String? helpText;
  final TimeOfDay? initialTime;
  final bool initialAllDay;
  final ValueChanged<({DateTime date, TimeOfDay? time})> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_DatePanel> createState() => _DatePanelState();
}

class _DatePanelState extends State<_DatePanel> {
  final _input = TextEditingController();
  final _timeKey = GlobalKey();
  DateTime? _selected;
  late TimeOfDay? _time = widget.initialTime;
  late bool _allDay = widget.initialAllDay;
  bool _initialized = false;
  bool _invalid = false;
  AppDateFormatter? _formatter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final formatter = AppDateFormatter.of(context);
    final previous = _formatter;
    _formatter = formatter;
    if (_initialized) {
      if (previous != null &&
          (previous.mode != formatter.mode ||
              previous.locale != formatter.locale)) {
        _selected = parsePickerDate(
          _input.text,
          MaterialLocalizations.of(context),
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          formatter: formatter,
        );
      }
      return;
    }
    _initialized = true;
    final date = DateUtils.dateOnly(widget.initialDate);
    _selected = date.isBefore(widget.firstDate)
        ? widget.firstDate
        : date.isAfter(widget.lastDate)
        ? widget.lastDate
        : date;
    _input.text = formatter.format(_selected!);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _select(DateTime date) => setState(() {
    _selected = date;
    _input.text = _formatter!.format(date);
    _invalid = false;
  });

  void _submit() {
    final date = parsePickerDate(
      _input.text,
      MaterialLocalizations.of(context),
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      formatter: _formatter,
    );
    if (date == null) {
      setState(() => _invalid = true);
      return;
    }
    if (widget.initialTime != null && !_allDay && _time == null) return;
    widget.onSubmit((date: date, time: _allDay ? null : _time));
  }

  Widget _presets(BuildContext context) {
    final now = DateTime.now();
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, days, icon) in [
          (l10n.today, 0, LucideIcons.calendarCheck),
          (l10n.tomorrow, 1, LucideIcons.calendar),
          (l10n.pickerInOneWeek, 7, LucideIcons.calendarPlus),
        ])
          Builder(
            builder: (context) {
              final date = DateTime(now.year, now.month, now.day + days);
              final enabled =
                  !date.isBefore(widget.firstDate) &&
                  !date.isAfter(widget.lastDate);
              final selected = _selected == date;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Semantics(
                  selected: selected,
                  child: ShadButton.ghost(
                    key: ValueKey('picker-preset-$days'),
                    expands: true,
                    enabled: enabled,
                    onPressed: enabled ? () => _select(date) : null,
                    height: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    backgroundColor: selected
                        ? context.appColors.accentTint
                        : null,
                    foregroundColor: selected
                        ? context.appColors.accent
                        : context.appColors.primaryText,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Icon(icon, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label),
                                Text(
                                  _formatter!.format(date),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: context.appColors.secondaryText,
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
              );
            },
          ),
      ],
    );
  }

  Widget _calendar(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: material.dateInputLabel,
          child: ShadInput(
            key: const Key('picker-date-input'),
            controller: _input,
            placeholder: Text(_formatter!.inputHint),
            trailing: const Icon(LucideIcons.calendar, size: 18),
            onSubmitted: (_) => _submit(),
            onChanged: (text) => setState(() {
              _invalid = false;
              _selected = parsePickerDate(
                text,
                material,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                formatter: _formatter,
              );
            }),
          ),
        ),
        if (_invalid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _formatter!.parse(_input.text) == null
                  ? material.invalidDateFormatLabel
                  : material.dateOutOfRangeLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.appColors.error),
            ),
          ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ShadCalendar(
            key: ValueKey(
              _selected == null
                  ? null
                  : DateTime(_selected!.year, _selected!.month),
            ),
            selected: _selected,
            initialMonth: _selected ?? widget.initialDate,
            fromMonth: widget.firstDate,
            toMonth: widget.lastDate,
            selectableDayPredicate: (day) =>
                !day.isBefore(widget.firstDate) &&
                !day.isAfter(widget.lastDate),
            weekStartsOn: pickerWeekStartsOn(material),
            captionLayout: ShadCalendarCaptionLayout.dropdown,
            dayButtonSize: math.max(
              44,
              MediaQuery.textScalerOf(context).scale(44),
            ),
            monthConstraints: BoxConstraints.tightFor(
              width:
                  7 * math.max(44, MediaQuery.textScalerOf(context).scale(44)),
            ),
            navigationButtonSize: 44,
            headerHeight: math.max(
              44,
              MediaQuery.textScalerOf(context).scale(44),
            ),
            dayButtonPadding: EdgeInsets.zero,
            allowDeselection: false,
            groupId: widget.groupId,
            onChanged: (date) {
              if (date != null) _select(date);
            },
          ),
        ),
      ],
    );
  }

  Widget _clock(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 24),
      Row(
        children: [
          Expanded(child: Text(context.l10n.allDay)),
          ShadSwitch(
            key: const Key('picker-all-day'),
            padding: const EdgeInsets.symmetric(vertical: 10),
            value: _allDay,
            onChanged: (value) => setState(() => _allDay = value),
          ),
        ],
      ),
      const SizedBox(height: 12),
      IgnorePointer(
        ignoring: _allDay,
        child: ExcludeFocus(
          excluding: _allDay,
          child: Opacity(
            opacity: _allDay ? .45 : 1,
            child: _TimeEditor(
              key: _timeKey,
              initialTime: widget.initialTime!,
              use24Hours: pickerUses24Hours(
                MaterialLocalizations.of(context),
                alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                  context,
                ),
              ),
              allowWheels: true,
              enabled: !_allDay,
              onChanged: (value) => setState(() => _time = value),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final withTime = widget.initialTime != null;
    final canSave = _allDay || _time != null;
    final summary = _selected == null
        ? null
        : '${_formatter!.format(_selected!)} · ${withTime && !_allDay && _time != null ? _time!.format(context) : context.l10n.allDay}';
    return _PickerFrame(
      onSubmit: canSave ? _submit : null,
      onCancel: widget.onCancel,
      summary: summary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.helpText ??
                (withTime
                    ? context.l10n.pickerDateAndTime
                    : MaterialLocalizations.of(context).datePickerHelpText),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (constraints.maxWidth >= (withTime ? 620 : 500) * scale) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: (withTime ? 232 : 160) * scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _presets(context),
                          if (withTime) _clock(context),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _calendar(context)),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _presets(context),
                  const SizedBox(height: 12),
                  _calendar(context),
                  if (withTime) _clock(context),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TimePanel extends StatefulWidget {
  const _TimePanel({
    required this.initialTime,
    required this.use24Hours,
    required this.onSubmit,
    required this.onCancel,
    this.helpText,
    super.key,
  });
  final TimeOfDay initialTime;
  final bool use24Hours;
  final String? helpText;
  final ValueChanged<TimeOfDay> onSubmit;
  final VoidCallback onCancel;
  @override
  State<_TimePanel> createState() => _TimePanelState();
}

class _TimePanelState extends State<_TimePanel> {
  late TimeOfDay? _value = widget.initialTime;
  @override
  Widget build(BuildContext context) => _PickerFrame(
    onCancel: widget.onCancel,
    onSubmit: _value == null ? null : () => widget.onSubmit(_value!),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.helpText ??
              MaterialLocalizations.of(context).timePickerDialHelpText,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _TimeEditor(
          initialTime: widget.initialTime,
          use24Hours: widget.use24Hours,
          onChanged: (value) => setState(() => _value = value),
        ),
      ],
    ),
  );
}

class _TimeEditor extends StatefulWidget {
  const _TimeEditor({
    required this.initialTime,
    required this.use24Hours,
    required this.onChanged,
    this.allowWheels = false,
    this.enabled = true,
    super.key,
  });
  final TimeOfDay initialTime;
  final bool use24Hours;
  final ValueChanged<TimeOfDay?> onChanged;
  final bool allowWheels;
  final bool enabled;
  @override
  State<_TimeEditor> createState() => _TimeEditorState();
}

// Keep invalid drafts visible instead of silently clamping them to a valid time.
class _TimeInputController extends ShadTimePickerTextEditingController {
  _TimeInputController({required super.text});
  @override
  String adjustText(String newText) => newText;
}

class _TimeEditorState extends State<_TimeEditor> {
  late final _hour = _TimeInputController(text: _hourText(widget.initialTime));
  late final _minute = _TimeInputController(
    text: widget.initialTime.minute.toString().padLeft(2, '0'),
  );
  late DayPeriod _period = widget.initialTime.period;
  late bool _wheels = widget.allowWheels;
  final _hourFocus = FocusNode();
  String _hourText(TimeOfDay time) =>
      (widget.use24Hours
              ? time.hour
              : time.hourOfPeriod == 0
              ? 12
              : time.hourOfPeriod)
          .toString()
          .padLeft(2, '0');
  TimeOfDay? get _value => parsePickerTime(
    _hour.text,
    _minute.text,
    use24Hours: widget.use24Hours,
    period: _period,
  );

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    _hourFocus.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged(_value);
  }

  void _set(TimeOfDay time) {
    _hour.text = _hourText(time);
    _minute.text = time.minute.toString().padLeft(2, '0');
    _period = time.period;
    _changed();
  }

  void _offset(int delta) {
    final value = _value;
    if (value == null) return;
    final minutes = (value.hour * 60 + value.minute + delta) % 1440;
    _set(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
  }

  Widget _field(BuildContext context, {required bool hour}) {
    final label = hour
        ? MaterialLocalizations.of(context).timePickerHourLabel
        : MaterialLocalizations.of(context).timePickerMinuteLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: label,
                child: ShadTimePickerField(
                  key: ValueKey(hour ? 'picker-hour' : 'picker-minute'),
                  controller: hour ? _hour : _minute,
                  focusNode: hour ? _hourFocus : null,
                  enabled: widget.enabled,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 26,
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall!.merge(AppTheme.monoTextStyle),
                  onChanged: (_) => _changed(),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final up in [true, false])
                  ShadIconButton.ghost(
                    key: ValueKey(
                      'picker-${hour ? "hour" : "minute"}-${up ? "increase" : "decrease"}',
                    ),
                    width: 44,
                    height: 44,
                    enabled: widget.enabled && _value != null,
                    onPressed: widget.enabled && _value != null
                        ? () => _offset((hour ? 60 : 1) * (up ? 1 : -1))
                        : null,
                    icon: Semantics(
                      label:
                          '${up ? context.l10n.pickerIncrease : context.l10n.pickerDecrease} $label',
                      child: Icon(
                        up ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final valid = widget.enabled && _value != null;
    final fields = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _field(context, hour: true)),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 28),
          child: Text(':', style: Theme.of(context).textTheme.headlineSmall),
        ),
        Expanded(child: _field(context, hour: false)),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_wheels)
          Row(
            children: [
              Expanded(
                child: _TimeWheel(
                  label: material.timePickerHourLabel,
                  value: int.parse(_hour.text) - (widget.use24Hours ? 0 : 1),
                  count: widget.use24Hours ? 24 : 12,
                  first: widget.use24Hours ? 0 : 1,
                  enabled: widget.enabled,
                  onChanged: (value) {
                    _hour.text = value.toString();
                    _changed();
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(':'),
              ),
              Expanded(
                child: _TimeWheel(
                  label: material.timePickerMinuteLabel,
                  value: int.parse(_minute.text),
                  count: 60,
                  enabled: widget.enabled,
                  onChanged: (value) {
                    _minute.text = value.toString();
                    _changed();
                  },
                ),
              ),
            ],
          )
        else
          fields,
        if (!widget.use24Hours)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ShadButton.outline(
              enabled: widget.enabled,
              onPressed: widget.enabled
                  ? () {
                      _period = _period == DayPeriod.am
                          ? DayPeriod.pm
                          : DayPeriod.am;
                      _changed();
                    }
                  : null,
              child: Text(
                _period == DayPeriod.am
                    ? material.anteMeridiemAbbreviation
                    : material.postMeridiemAbbreviation,
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (widget.allowWheels)
          ShadButton.outline(
            key: const Key('picker-time-input-toggle'),
            enabled: valid,
            leading: Icon(
              _wheels ? LucideIcons.keyboard : LucideIcons.list,
              size: 18,
            ),
            onPressed: valid
                ? () {
                    setState(() => _wheels = !_wheels);
                    if (!_wheels) _hourFocus.requestFocus();
                  }
                : null,
            child: Text(
              _wheels
                  ? context.l10n.pickerEnterTime
                  : context.l10n.pickerTimeWheels,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final minutes in [-5, 5, 15])
                ShadButton.outline(
                  key: ValueKey('picker-offset-$minutes'),
                  enabled: valid,
                  onPressed: valid ? () => _offset(minutes) : null,
                  child: Text(
                    context.l10n.pickerMinuteOffset(
                      '${minutes > 0 ? '+' : '−'}${minutes.abs()}',
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _TimeWheel extends StatefulWidget {
  const _TimeWheel({
    required this.label,
    required this.value,
    required this.count,
    required this.onChanged,
    required this.enabled,
    this.first = 0,
  });
  final String label;
  final int value;
  final int count;
  final int first;
  final bool enabled;
  final ValueChanged<int> onChanged;
  @override
  State<_TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<_TimeWheel> {
  late final _scroll = FixedExtentScrollController(initialItem: widget.value);
  final _focus = FocusNode();
  bool _focused = false;
  @override
  void didUpdateWidget(_TimeWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _scroll.hasClients &&
        _scroll.selectedItem != widget.value) {
      _scroll.jumpToItem(widget.value);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (!widget.enabled) return;
    final next = (_scroll.selectedItem + delta).clamp(0, widget.count - 1);
    _scroll.jumpToItem(next);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 8),
      Focus(
        focusNode: _focus,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (_, event) {
          if (!widget.enabled || event is KeyUpEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _move(event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          excludeSemantics: true,
          label: widget.label,
          value: (widget.value + widget.first).toString().padLeft(2, '0'),
          increasedValue:
              ((widget.value + 1).clamp(0, widget.count - 1) + widget.first)
                  .toString()
                  .padLeft(2, '0'),
          decreasedValue:
              ((widget.value - 1).clamp(0, widget.count - 1) + widget.first)
                  .toString()
                  .padLeft(2, '0'),
          enabled: widget.enabled,
          onIncrease: widget.enabled ? () => _move(1) : null,
          onDecrease: widget.enabled ? () => _move(-1) : null,
          child: Listener(
            onPointerDown: widget.enabled ? (_) => _focus.requestFocus() : null,
            onPointerSignal: (event) {
              if (widget.enabled && event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (_) => _move(event.scrollDelta.dy > 0 ? 1 : -1),
                );
              }
            },
            child: SizedBox(
              height:
                  5 * math.max(44, MediaQuery.textScalerOf(context).scale(44)),
              child: Stack(
                children: [
                  Align(
                    child: Container(
                      height: math.max(
                        44,
                        MediaQuery.textScalerOf(context).scale(44),
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.accentTint,
                        border: _focused
                            ? Border.all(color: context.appColors.accent)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.touch,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                      scrollbars: false,
                    ),
                    child: ListWheelScrollView.useDelegate(
                      controller: _scroll,
                      physics: const FixedExtentScrollPhysics(),
                      itemExtent: math.max(
                        44,
                        MediaQuery.textScalerOf(context).scale(44),
                      ),
                      diameterRatio: 100,
                      perspective: .001,
                      onSelectedItemChanged: (index) =>
                          widget.onChanged(index + widget.first),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: widget.count,
                        builder: (context, index) => GestureDetector(
                          onTap: widget.enabled
                              ? () => _scroll.jumpToItem(index)
                              : null,
                          child: Center(
                            child: Text(
                              (index + widget.first).toString().padLeft(2, '0'),
                              style: Theme.of(context).textTheme.titleLarge!
                                  .merge(AppTheme.monoTextStyle)
                                  .copyWith(
                                    color: index == widget.value
                                        ? context.appColors.primaryText
                                        : context.appColors.secondaryText,
                                  ),
                            ),
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
    ],
  );
}

class _PickerFrame extends StatelessWidget {
  const _PickerFrame({
    required this.child,
    required this.onCancel,
    required this.onSubmit,
    this.summary,
  });
  final Widget child;
  final VoidCallback onCancel;
  final VoidCallback? onSubmit;
  final String? summary;
  @override
  Widget build(BuildContext context) {
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        if (summary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              summary!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadButton.outline(
              onPressed: onCancel,
              child: Text(context.l10n.commonCancel),
            ),
            ShadButton(
              enabled: onSubmit != null,
              onPressed: onSubmit,
              child: Text(context.l10n.commonSave),
            ),
          ],
        ),
      ],
    );
    return ShortcutHintsScope(
      enabled: onSubmit != null,
      hints: [ShortcutHint(context.l10n.commonSave, 'Enter')],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              onSubmit?.call(),
          const SingleActivator(LogicalKeyboardKey.escape): onCancel,
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight < 180) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [child, footer],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [const ShortcutHintsBar(), child],
                    ),
                  ),
                ),
                footer,
              ],
            );
          },
        ),
      ),
    );
  }
}
