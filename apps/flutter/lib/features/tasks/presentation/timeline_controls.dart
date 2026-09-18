part of 'timeline_screen.dart';

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: l10n.timelinePreviousDay,
          child: ShadIconButton.secondary(
            onPressed: () =>
                _goToDate(context, day.subtract(const Duration(days: 1))),
            icon: const Icon(LucideIcons.chevronLeft),
            width: 40,
            height: 40,
          ),
        ),
        AppDateTimePicker(
          builder: (context, picker) => ShadButton.secondary(
            focusNode: picker.focusNode,
            onPressed: () => _pickDate(context, day, picker),
            leading: const Icon(LucideIcons.calendar),
            child: Text(formatLocalDate(context, day)),
          ),
        ),
        Tooltip(
          message: l10n.timelineNextDay,
          child: ShadIconButton.secondary(
            onPressed: () =>
                _goToDate(context, day.add(const Duration(days: 1))),
            icon: const Icon(LucideIcons.chevronRight),
            width: 40,
            height: 40,
          ),
        ),
        ShadButton.outline(
          onPressed: _isSameDay(day, today)
              ? null
              : () => _goToDate(context, today),
          enabled: !(_isSameDay(day, today)),
          child: Text(l10n.today),
        ),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    DateTime initialDate,
    AppDateTimePickerState picker,
  ) async {
    final now = DateTime.now();
    final picked = await picker.pickDate(
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      helpText: context.l10n.timelinePickDate,
    );
    if (picked != null && context.mounted) {
      _goToDate(context, picked);
    }
  }

  void _goToDate(BuildContext context, DateTime date) {
    context.go('/timeline?date=${_formatRouteDate(_dateOnly(date))}');
  }
}

class _VisibleHoursControls extends ConsumerWidget {
  const _VisibleHoursControls({required this.visibleHours});

  final TimelineVisibleHours visibleHours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final hourWidth = ref.watch(timelineHourWidthProvider);
    final zoomIndex = timelineHourWidthLevels.indexOf(hourWidth);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.timelineVisibleHours,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.timelineStartHour,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      ShadSelect<int>(
                        key: const Key('timeline-start-minutes'),
                        initialValue: visibleHours.startMinutes,
                        onChanged: (value) {
                          if (value != null) {
                            unawaited(
                              ref
                                  .read(timelineVisibleHoursProvider.notifier)
                                  .setVisibleHours(
                                    value,
                                    visibleHours.endMinutes,
                                  ),
                            );
                          }
                        },
                        options: [
                          for (final value in _timeOptions)
                            if (value < visibleHours.endMinutes)
                              ShadOption(
                                value: value,
                                child: Text(_formatMinutes(value)),
                              ),
                        ],
                        selectedOptionBuilder: (context, value) =>
                            Text(_formatMinutes(value)),
                        placeholder: Text(l10n.timelineStartHour),
                        minWidth: 160,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.timelineEndHour,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      ShadSelect<int>(
                        key: const Key('timeline-end-minutes'),
                        initialValue: visibleHours.endMinutes,
                        onChanged: (value) {
                          if (value != null) {
                            unawaited(
                              ref
                                  .read(timelineVisibleHoursProvider.notifier)
                                  .setVisibleHours(
                                    visibleHours.startMinutes,
                                    value,
                                  ),
                            );
                          }
                        },
                        options: [
                          for (final value in _timeOptions)
                            if (value > visibleHours.startMinutes)
                              ShadOption(
                                value: value,
                                child: Text(_formatMinutes(value)),
                              ),
                        ],
                        selectedOptionBuilder: (context, value) =>
                            Text(_formatMinutes(value)),
                        placeholder: Text(l10n.timelineEndHour),
                        minWidth: 160,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: l10n.timelineZoomOut,
                      child: ShadIconButton.outline(
                        key: const Key('timeline-zoom-out'),
                        onPressed: zoomIndex == 0
                            ? null
                            : () => unawaited(
                                ref
                                    .read(timelineHourWidthProvider.notifier)
                                    .zoomOut(),
                              ),
                        icon: const Icon(LucideIcons.zoomOut),
                        enabled: !(zoomIndex == 0),
                        width: 40,
                        height: 40,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: l10n.timelineZoomIn,
                      child: ShadIconButton.outline(
                        key: const Key('timeline-zoom-in'),
                        onPressed:
                            zoomIndex == timelineHourWidthLevels.length - 1
                            ? null
                            : () => unawaited(
                                ref
                                    .read(timelineHourWidthProvider.notifier)
                                    .zoomIn(),
                              ),
                        icon: const Icon(LucideIcons.zoomIn),
                        enabled:
                            !(zoomIndex == timelineHourWidthLevels.length - 1),
                        width: 40,
                        height: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
