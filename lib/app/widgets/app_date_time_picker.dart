import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

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
  LocalHistoryEntry? _backEntry;

  @override
  void initState() {
    super.initState();
    _popover.addListener(_onToggle);
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
      onSubmit: submit,
      onCancel: () => _finish(null),
    ),
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

  Future<T?> _show<T>(Widget Function(ValueChanged<T>) content) async {
    // Context-menu items dismiss after invoking their callback.
    await Future<void>.value();
    if (!mounted) return null;
    _finish(null);
    final request = Completer<Object?>();
    setState(() {
      _request = request;
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
    _popover.removeListener(_onToggle);
    _popover.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = context.appColors;
    final anchorBox = focusNode.context?.findRenderObject();
    final anchorX =
        anchorBox is RenderBox && anchorBox.attached && anchorBox.hasSize
        ? anchorBox.localToGlobal(anchorBox.size.center(Offset.zero)).dx
        : media.size.width / 2;
    final panel = ShadPopover(
      controller: _popover,
      groupId: _group,
      // The library positions against the full overlay, including the keyboard.
      anchor: media.viewInsets.bottom > 0
          ? ShadGlobalAnchor(Offset(anchorX, media.padding.top + 12))
          : null,
      padding: const EdgeInsets.all(12),
      decoration: ShadDecoration(
        color: colors.surface,
        border: ShadBorder.all(
          color: colors.border,
          radius: BorderRadius.circular(12),
        ),
      ),
      popover: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(1, math.min(320, media.size.width - 48)),
          maxHeight: math.max(
            1,
            media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                48,
          ),
        ),
        child: SingleChildScrollView(
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
}) {
  final date = material.parseCompactDate(text.trim());
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
    this.helpText,
    super.key,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Object groupId;
  final String? helpText;
  final ValueChanged<DateTime> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_DatePanel> createState() => _DatePanelState();
}

class _DatePanelState extends State<_DatePanel> {
  final _input = TextEditingController();
  DateTime? _selected;
  bool _initialized = false;
  bool _invalid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final date = DateUtils.dateOnly(widget.initialDate);
    _selected = date.isBefore(widget.firstDate)
        ? widget.firstDate
        : date.isAfter(widget.lastDate)
        ? widget.lastDate
        : date;
    _input.text = MaterialLocalizations.of(
      context,
    ).formatCompactDate(_selected!);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final date = parsePickerDate(
      _input.text,
      MaterialLocalizations.of(context),
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
    );
    if (date == null) {
      setState(() => _invalid = true);
      return;
    }
    widget.onSubmit(date);
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.helpText ?? material.datePickerHelpText,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Semantics(
          label: material.dateInputLabel,
          child: ShadInput(
            autofocus: true,
            controller: _input,
            placeholder: Text(material.dateHelpText),
            onSubmitted: (_) => _submit(),
            onChanged: (text) => setState(() {
              _invalid = false;
              _selected = parsePickerDate(
                text,
                material,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
              );
            }),
          ),
        ),
        if (_invalid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              material.parseCompactDate(_input.text.trim()) == null
                  ? material.invalidDateFormatLabel
                  : material.dateOutOfRangeLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.appColors.error),
            ),
          ),
        const SizedBox(height: 8),
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
            allowDeselection: false,
            groupId: widget.groupId,
            onChanged: (date) {
              if (date == null) return;
              setState(() {
                _selected = date;
                _input.text = material.formatCompactDate(date);
                _invalid = false;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        _PickerActions(onCancel: widget.onCancel, onSubmit: _submit),
      ],
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
  final _hourFocus = FocusNode();
  late final _hour = ShadTimePickerTextEditingController(
    text:
        (widget.use24Hours
                ? widget.initialTime.hour
                : (widget.initialTime.hourOfPeriod == 0
                      ? 12
                      : widget.initialTime.hourOfPeriod))
            .toString()
            .padLeft(2, '0'),
    min: widget.use24Hours ? 0 : 1,
    max: widget.use24Hours ? 23 : 12,
  );
  late final _minute = ShadTimePickerTextEditingController(
    text: widget.initialTime.minute.toString().padLeft(2, '0'),
  );
  late DayPeriod _period = widget.initialTime.period;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hourFocus.requestFocus();
    });
  }

  TimeOfDay? get _value => parsePickerTime(
    _hour.text,
    _minute.text,
    use24Hours: widget.use24Hours,
    period: _period,
  );

  @override
  void dispose() {
    _hourFocus.dispose();
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _value;
    if (value != null) widget.onSubmit(value);
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.helpText ?? material.timePickerDialHelpText,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          // Use the exported fields: ShadTimePicker 0.56.3 retains its old
          // value when an input is cleared, allowing an unintended submission.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              ShadTimePickerField(
                focusNode: _hourFocus,
                controller: _hour,
                label: Text(material.timePickerHourLabel),
                onChanged: (_) => setState(() {}),
              ),
              ShadTimePickerField(
                controller: _minute,
                label: Text(material.timePickerMinuteLabel),
                onChanged: (_) => setState(() {}),
              ),
              if (!widget.use24Hours)
                ShadButton.outline(
                  onPressed: () => setState(() {
                    _period = _period == DayPeriod.am
                        ? DayPeriod.pm
                        : DayPeriod.am;
                  }),
                  child: Text(
                    _period == DayPeriod.am
                        ? material.anteMeridiemAbbreviation
                        : material.postMeridiemAbbreviation,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _PickerActions(
            onCancel: widget.onCancel,
            onSubmit: _value == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _PickerActions extends StatelessWidget {
  const _PickerActions({required this.onCancel, required this.onSubmit});
  final VoidCallback onCancel;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        ShadButton.ghost(
          onPressed: onCancel,
          child: Text(material.cancelButtonLabel),
        ),
        ShadButton(
          onPressed: onSubmit,
          enabled: onSubmit != null,
          child: Text(material.okButtonLabel),
        ),
      ],
    );
  }
}
