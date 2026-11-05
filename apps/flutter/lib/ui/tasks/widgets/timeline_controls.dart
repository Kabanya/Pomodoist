part of 'timeline_screen.dart';

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.day,
    required this.today,
    required this.compact,
    required this.presentation,
  });

  final DateTime day;
  final DateTime today;
  final bool compact;
  final TimelineDayPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dateControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l10n.timelinePreviousDay,
          child: ShadIconButton.secondary(
            onPressed: () =>
                _goToDate(context, DateTime(day.year, day.month, day.day - 1)),
            icon: Icon(
              rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
            ),
            width: 44,
            height: 44,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          fit: compact ? FlexFit.tight : FlexFit.loose,
          child: AppDateTimePicker(
            builder: (context, picker) => ShadButton.secondary(
              focusNode: picker.focusNode,
              height: 44,
              width: compact ? null : 176,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => _pickDate(context, picker),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (MediaQuery.textScalerOf(context).scale(16) <= 20 &&
                      (!compact ||
                          MediaQuery.sizeOf(context).width >= 360)) ...[
                    const Icon(LucideIcons.calendar, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      MaterialLocalizations.of(context).formatMediumDate(day),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: l10n.timelineNextDay,
          child: ShadIconButton.secondary(
            onPressed: () =>
                _goToDate(context, DateTime(day.year, day.month, day.day + 1)),
            icon: Icon(
              rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
            ),
            width: 44,
            height: 44,
          ),
        ),
      ],
    );
    final settings = _TimelineControlsPopover(
      compact: compact,
      onToday: isSameLocalDay(day, today)
          ? null
          : () => _goToDate(context, today),
      presentation: presentation,
    );
    if (compact) {
      return Row(
        children: [
          Expanded(child: dateControls),
          const SizedBox(width: 12),
          settings,
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 8,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(320, constraints.maxWidth),
            ),
            child: dateControls,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _TimelineControlsPopover(rangeOnly: true),
              const SizedBox(width: 12),
              settings,
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    AppDateTimePickerState picker,
  ) async {
    final now = DateTime.now();
    final picked = await picker.pickDate(
      initialDate: day,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      helpText: context.l10n.timelinePickDate,
    );
    if (picked != null && context.mounted) _goToDate(context, picked);
  }

  void _goToDate(BuildContext context, DateTime date) {
    context.go('/timeline?date=${_formatRouteDate(timelineDateOnly(date))}');
  }
}

class _TimelineControlsPopover extends ConsumerStatefulWidget {
  const _TimelineControlsPopover({
    this.rangeOnly = false,
    this.compact = false,
    this.onToday,
    this.presentation,
  });

  final bool rangeOnly;
  final bool compact;
  final VoidCallback? onToday;
  final TimelineDayPresentation? presentation;

  @override
  ConsumerState<_TimelineControlsPopover> createState() =>
      _TimelineControlsPopoverState();
}

class _TimelineControlsPopoverState
    extends ConsumerState<_TimelineControlsPopover> {
  final _popover = ShadPopoverController();
  final _group = Object();

  ({ShadAnchorAuto anchor, double maxHeight})? _placement;

  void _toggle() {
    if (!_popover.isOpen) {
      final box = context.findRenderObject() as RenderBox?;
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (box != null && overlay != null) {
        final media = MediaQuery.of(context);
        final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
        setState(
          () => _placement = actionMenuPlacement(
            origin & box.size,
            Rect.fromLTRB(
              media.padding.left,
              media.padding.top,
              overlay.size.width - media.padding.right,
              overlay.size.height -
                  math.max(media.padding.bottom, media.viewInsets.bottom),
            ),
          ),
        );
      }
    }
    _popover.toggle();
  }

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visibleHours = ref.watch(
      timelineViewModelProvider.select((state) => state.visibleHours),
    );
    final presentation = widget.presentation;
    return ShadPopover(
      controller: _popover,
      groupId: _group,
      anchor: _placement?.anchor,
      popover: (context) => SizedBox(
        width: math.min(256, MediaQuery.sizeOf(context).width - 64),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(
              420,
              _placement?.maxHeight ?? MediaQuery.sizeOf(context).height / 2,
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.rangeOnly || widget.compact)
                  _VisibleHoursControls(group: _group),
                if (!widget.rangeOnly) ...[
                  if (widget.compact) const SizedBox(height: 12),
                  const _TimelineZoomControls(),
                  ShadButton.ghost(
                    onPressed: widget.onToday == null
                        ? null
                        : () {
                            _popover.hide();
                            widget.onToday!();
                          },
                    child: Text(l10n.today),
                  ),
                  if (presentation != null)
                    _TimelineProjectsButton(
                      presentation: presentation,
                      onOpen: _popover.hide,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      child: widget.rangeOnly
          ? Tooltip(
              message: l10n.timelineVisibleHours,
              child: ShadButton.outline(
                key: const Key('timeline-hours-menu'),
                foregroundColor: context.appColors.primaryText,
                height: 44,
                onPressed: _toggle,
                trailing: const Icon(LucideIcons.chevronDown, size: 18),
                child: Text(
                  '${_formatMinutes(visibleHours.startMinutes)} – '
                  '${_formatMinutes(visibleHours.endMinutes)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.merge(AppTheme.monoTextStyle),
                ),
              ),
            )
          : Tooltip(
              message: MaterialLocalizations.of(context).moreButtonTooltip,
              child: ShadIconButton.outline(
                key: const Key('timeline-settings'),
                foregroundColor: context.appColors.primaryText,
                onPressed: _toggle,
                icon: const Icon(LucideIcons.slidersHorizontal),
                width: 44,
                height: 44,
              ),
            ),
    );
  }
}

class _VisibleHoursControls extends ConsumerWidget {
  const _VisibleHoursControls({required this.group});

  final Object group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final visibleHours = ref.watch(
      timelineViewModelProvider.select((state) => state.visibleHours),
    );
    final vm = ref.read(timelineViewModelProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.timelineVisibleHours,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final isStart in [true, false]) ...[
          Text(isStart ? l10n.timelineStartHour : l10n.timelineEndHour),
          const SizedBox(height: 4),
          ShadSelect<int>(
            groupId: group,
            key: Key(
              isStart ? 'timeline-start-minutes' : 'timeline-end-minutes',
            ),
            initialValue: isStart
                ? visibleHours.startMinutes
                : visibleHours.endMinutes,
            onChanged: (value) {
              if (value != null) {
                unawaited(
                  vm.setVisibleHours(
                    isStart ? value : visibleHours.startMinutes,
                    isStart ? visibleHours.endMinutes : value,
                  ),
                );
              }
            },
            options: [
              for (final value in _timeOptions)
                if (isStart
                    ? value < visibleHours.endMinutes
                    : value > visibleHours.startMinutes)
                  ShadOption(value: value, child: Text(_formatMinutes(value))),
            ],
            selectedOptionBuilder: (context, value) =>
                Text(_formatMinutes(value)),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TimelineZoomControls extends ConsumerWidget {
  const _TimelineZoomControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hourWidth = ref.watch(
      timelineViewModelProvider.select((state) => state.hourWidth),
    );
    final vm = ref.read(timelineViewModelProvider.notifier);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: l10n.timelineZoomOut,
          child: ShadIconButton.outline(
            key: const Key('timeline-zoom-out'),
            onPressed: hourWidth == timelineHourWidthLevels.first
                ? null
                : () => unawaited(vm.zoomOut()),
            icon: const Icon(LucideIcons.zoomOut),
            width: 44,
            height: 44,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: l10n.timelineZoomIn,
          child: ShadIconButton.outline(
            key: const Key('timeline-zoom-in'),
            onPressed: hourWidth == timelineHourWidthLevels.last
                ? null
                : () => unawaited(vm.zoomIn()),
            icon: const Icon(LucideIcons.zoomIn),
            width: 44,
            height: 44,
          ),
        ),
      ],
    );
  }
}
