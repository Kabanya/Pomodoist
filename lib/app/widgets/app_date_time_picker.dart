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
    final width = math.max(1.0, math.min(320.0, space.width - 26));
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
