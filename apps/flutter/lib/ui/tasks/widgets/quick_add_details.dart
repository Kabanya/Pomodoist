import 'package:pomodoist/ui/core/localization/app_date_formatter.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pomodoist/domain/models/tasks/task_focus_estimate.dart';
import 'quick_add_focus_estimate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadBorder,
        ShadButton,
        ShadButtonSize,
        ShadTheme,
        ShadDecoration,
        ShadPopover,
        ShadGlobalAnchor,
        ShadPopoverController;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_details_view_model.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_project_picker.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_toolbar_layout.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_metadata_edit.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_text_controller.dart';

class QuickAddDetails extends ConsumerWidget {
  const QuickAddDetails({
    super.key,
    required this.controller,
    this.defaultDate,
    this.defaultSchedule,
    this.projectId,
    this.inheritedProjectName,
    this.priority,
    this.enabled = true,
    this.onChanged,
    this.touchTargets = false,
    this.desktop = false,
    this.iconsOnly = false,
    this.onNaturalWidthChanged,
    this.trailing,
  });

  final QuickAddTextController controller;
  final DateTime? defaultDate;
  final TaskSchedule? defaultSchedule;
  final String? projectId;
  final String? inheritedProjectName;
  final int? priority;
  final bool enabled;
  final VoidCallback? onChanged;
  final bool touchTargets;
  final bool desktop;
  final bool iconsOnly;
  final ValueChanged<double>? onNaturalWidthChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(quickAddDetailsViewModelProvider);
    final viewModel = ref.read(quickAddDetailsViewModelProvider.notifier);
    final allProjects = viewState.allProjects;
    final projects = viewState.projects;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.trim().isEmpty && onNaturalWidthChanged == null) {
          return const SizedBox.shrink();
        }
        final now = viewModel.now();
        final analysis = viewModel.analyze(
          value.text,
          now: now,
          defaultDate: defaultDate,
        );
        final parsed = analysis.parsed;
        final colors = context.appColors;
        final schedule =
            parsed.schedule ??
            (parsed.dueDate == null && !parsed.hasInvalidExplicitDate
                ? defaultSchedule
                : null);
        final canEdit =
            enabled &&
            (value.composing.isCollapsed || !value.composing.isValid);
        var projectName = inheritedProjectName ?? context.l10n.navInbox;
        String? selectedProjectId = inheritedProjectName == null
            ? projectId ?? inboxProjectId
            : null;
        for (final project in allProjects) {
          if (project.name.toLowerCase() ==
              inheritedProjectName?.toLowerCase()) {
            selectedProjectId = project.id;
          }
          if (project.id == projectId && inheritedProjectName == null) {
            projectName = project.displayName(context.l10n);
          }
        }
        if (parsed.project case final name?) {
          projectName = name;
          selectedProjectId = null;
          for (final project in allProjects) {
            if (project.name.toLowerCase() == name.toLowerCase()) {
              projectName = project.displayName(context.l10n);
              selectedProjectId = project.id;
              break;
            }
          }
        }
        void edit(Set<QuickAddTokenKind> kinds, String? token) {
          if (!enabled) return;
          final current = controller.value;
          final next = rewriteQuickAddMetadata(
            current,
            viewModel.analyze(
              current.text,
              now: viewModel.now(),
              defaultDate: defaultDate,
              includeInvalidScheduling: true,
            ),
            kinds,
            token,
          );
          if (next != current) {
            controller.value = next;
            onChanged?.call();
          }
        }

        TaskSchedule? currentSchedule() {
          final current = viewModel
              .analyze(
                controller.text,
                now: viewModel.now(),
                defaultDate: defaultDate,
                includeInvalidScheduling: true,
              )
              .parsed;
          return current.schedule ??
              (current.dueDate == null && !current.hasInvalidExplicitDate
                  ? defaultSchedule
                  : null);
        }

        Future<void> changeDate(AppDateTimePickerState picker) async {
          final current = currentSchedule();
          final initial = current?.displayDate ?? viewModel.now();
          final picked = await picker.pickSchedule(
            initialDate: initial,
            initialTime: TimeOfDay.fromDateTime(
              current?.start?.toLocal() ?? viewModel.now(),
            ),
            initialAllDay: current?.isAllDay ?? true,
            firstDate: DateTime(1),
            lastDate: DateTime(9999, 12, 31),
          );
          if (picked == null || !context.mounted) return;
          final latest = currentSchedule();
          final time = picked.time;
          final start = DateTime(
            picked.date.year,
            picked.date.month,
            picked.date.day,
            time?.hour ?? 0,
            time?.minute ?? 0,
          );
          edit(
            quickAddSchedulingKinds,
            quickAddScheduleToken(
              time == null
                  ? TaskSchedule.allDay(picked.date)
                  : TaskSchedule.timed(
                      start: start,
                      end: start.add(
                        latest?.duration ?? viewModel.defaultTimedBlockDuration,
                      ),
                      timeZone: latest?.timeZone,
                    ),
            ),
          );
        }

        Future<void> changeTime(AppDateTimePickerState picker) async {
          final current = currentSchedule();
          final time = await picker.pickTime(
            initialTime: TimeOfDay.fromDateTime(
              current?.start?.toLocal() ?? viewModel.now(),
            ),
          );
          if (time == null || !context.mounted) return;
          final latest = currentSchedule();
          final date = latest?.displayDate ?? viewModel.now();
          final start = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          edit(
            quickAddSchedulingKinds,
            quickAddScheduleToken(
              TaskSchedule.timed(
                start: start,
                end: start.add(
                  latest?.duration ?? viewModel.defaultTimedBlockDuration,
                ),
              ),
            ),
          );
        }

        final dateLabel = schedule == null
            ? context.l10n.noDate
            : AppDateFormatter.of(context).format(schedule.displayDate);
        final timeLabel = schedule?.isTimed == true
            ? TimeOfDay.fromDateTime(schedule!.start!.toLocal()).format(context)
            : null;
        final scheduleLabel = timeLabel == null
            ? dateLabel
            : '$dateLabel · $timeLabel';
        final estimate = estimateFocusIntervalsForTaskDuration(
          schedule: schedule,
          durationSeconds: null,
          explicitEstimate: parsed.estimatedFocusIntervals,
          isFocusEstimateManual: parsed.estimatedFocusIntervals != null,
          preset: viewState.focusPreset,
        );
        if (onNaturalWidthChanged != null) {
          final theme = ShadTheme.of(context);
          final scaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          final labels = [
            scheduleLabel,
            projectName,
            'P${parsed.priority ?? priority ?? 4}',
            estimate == null
                ? context.l10n.quickAddFocusEstimate
                : context.l10n.quickAddEstimatedPomodoros(estimate),
          ];
          var width = 3 * 8.0;
          for (var index = 0; index < labels.length; index++) {
            width += quickAddLabeledButtonWidth(
              labels[index],
              theme: theme,
              textScaler: scaler,
              textDirection: direction,
              trailingWidth: index < 3 ? 12 : 0,
            );
          }
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => onNaturalWidthChanged?.call(width),
          );
        }
        if (value.text.trim().isEmpty) return const SizedBox.shrink();
        final inlineEstimate =
            !desktop && MediaQuery.sizeOf(context).width < 820;
        final estimateControl = QuickAddFocusEstimateChip(
          estimate: estimate,
          manual: parsed.estimatedFocusIntervals != null,
          workSeconds: viewState.focusPreset?.workSeconds,
          enabled: canEdit,
          touchTargets: touchTargets || inlineEstimate,
          desktop: desktop,
          iconsOnly: iconsOnly,
          onChanged: (count) => edit({
            QuickAddTokenKind.focusEstimate,
          }, count == null ? null : '${count}p'),
        );
        return Padding(
          padding: EdgeInsets.only(top: desktop ? 0 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: inlineEstimate
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: touchTargets || desktop ? 8 : 4,
                runSpacing: touchTargets || desktop ? 8 : 4,
                children: [
                  AppDateTimePicker(
                    builder: (context, picker) => _DetailsMenu(
                      touchTargets: touchTargets,
                      desktop: desktop,
                      iconsOnly: iconsOnly,
                      focusNode: picker.focusNode,
                      label: scheduleLabel,
                      semanticLabel:
                          '${context.l10n.taskSchedule}: ${timeLabel == null ? dateLabel : '$dateLabel · $timeLabel'}',
                      icon: LucideIcons.calendar,
                      color: colors.quickAddTokenColor(QuickAddTokenKind.date),
                      enabled: canEdit,
                      content: (close) => SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.pickerDateAndTime,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    scheduleLabel,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: colors.secondaryText),
                                  ),
                                ],
                              ),
                            ),
                            _scheduleOption(
                              context,
                              context.l10n.timelinePickDate,
                              LucideIcons.calendar,
                              dateLabel,
                              () {
                                close();
                                changeDate(picker);
                              },
                            ),
                            _scheduleOption(
                              context,
                              context.l10n.quickAddChangeTime,
                              LucideIcons.clock,
                              timeLabel,
                              () {
                                close();
                                changeTime(picker);
                              },
                            ),
                            _scheduleOption(
                              context,
                              context.l10n.allDay,
                              LucideIcons.sun,
                              null,
                              () {
                                close();
                                edit(
                                  quickAddSchedulingKinds,
                                  quickAddScheduleToken(
                                    TaskSchedule.allDay(
                                      currentSchedule()?.displayDate ??
                                          viewModel.now(),
                                    ),
                                  ),
                                );
                              },
                              checked: schedule?.isAllDay ?? false,
                            ),
                            const Divider(),
                            _scheduleOption(
                              context,
                              context.l10n.quickAddResetDetails,
                              LucideIcons.rotateCcw,
                              null,
                              () {
                                close();
                                edit(quickAddSchedulingKinds, null);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _DetailsMenu(
                    touchTargets: touchTargets,
                    desktop: desktop,
                    iconsOnly: iconsOnly,
                    label: projectName,
                    semanticLabel:
                        '${context.l10n.kanbanProjectField}: $projectName',
                    icon: LucideIcons.hash,
                    color: colors.quickAddTokenColor(QuickAddTokenKind.project),
                    enabled: canEdit,
                    content: (close) => QuickAddProjectPicker(
                      projects: projects,
                      selectedProjectId: selectedProjectId,
                      touchTargets: touchTargets,
                      projectToken: viewModel.projectToken,
                      onClose: close,
                      onSelected: (token) {
                        close();
                        edit({QuickAddTokenKind.project}, token);
                      },
                    ),
                  ),
                  _DetailsMenu(
                    touchTargets: touchTargets,
                    desktop: desktop,
                    iconsOnly: iconsOnly,
                    label: touchTargets || desktop
                        ? 'P${parsed.priority ?? priority ?? 4}'
                        : context.l10n.priority(
                            parsed.priority ?? priority ?? 4,
                          ),
                    semanticLabel: context.l10n.priority(
                      parsed.priority ?? priority ?? 4,
                    ),
                    icon: LucideIcons.flag,
                    color: colors.quickAddTokenColor(
                      QuickAddTokenKind.priority,
                      priority: parsed.priority ?? priority ?? 4,
                    ),
                    enabled: canEdit,
                    items: (close) => [
                      for (var number = 1; number <= 4; number++)
                        _PriorityOption(
                          priority: number,
                          selected:
                              number == (parsed.priority ?? priority ?? 4),
                          onPressed: () {
                            close();
                            edit({QuickAddTokenKind.priority}, 'p$number');
                          },
                        ),
                    ],
                  ),
                  if (!inlineEstimate) estimateControl,
                  ?trailing,
                ],
              ),
              if (inlineEstimate)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: estimateControl,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _scheduleOption(
    BuildContext context,
    String label,
    IconData icon,
    String? value,
    VoidCallback action, {
    bool? checked,
  }) => ShadButton.ghost(
    onPressed: action,
    expands: true,
    height: 0,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    foregroundColor: context.appColors.primaryText,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          if (value != null)
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appColors.secondaryText,
                ),
              ),
            ),
          const SizedBox(width: 8),
          if (checked != null)
            Semantics(
              checked: checked,
              child: Icon(
                checked ? LucideIcons.squareCheck : LucideIcons.square,
                size: 20,
              ),
            )
          else
            const Icon(LucideIcons.chevronRight, size: 18),
        ],
      ),
    ),
  );
}

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({
    required this.priority,
    required this.onPressed,
    this.selected = false,
  });

  final int priority;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final number = priority;
    final color = colors
        .quickAddStyle(
          colors.quickAddTokenColor(
            QuickAddTokenKind.priority,
            priority: number,
          ),
        )
        .color!;
    final subtitle = switch (number) {
      1 => l10n.priorityUrgent,
      2 => l10n.priorityHigh,
      3 => l10n.priorityNormal,
      _ => l10n.priorityLow,
    };
    final tint = colors.quickAddBackground(color);
    return Semantics(
      selected: selected,
      child: ShadButton.ghost(
        onPressed: onPressed,
        height: 0,
        expands: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: colors.primaryText,
        hoverForegroundColor: colors.primaryText,
        pressedForegroundColor: colors.primaryText,
        backgroundColor: selected ? tint : Colors.transparent,
        hoverBackgroundColor: colors.quickAddBackground(
          color,
          emphasized: true,
        ),
        pressedBackgroundColor: colors.quickAddBackground(
          color,
          emphasized: true,
        ),
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: selected ? color : Colors.transparent,
            width: 1,
            radius: BorderRadius.circular(8),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.quickAddBorder(color)),
                ),
                child: Icon(LucideIcons.flag, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.priority(number),
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      subtitle,
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.quickAddBackground(color, emphasized: true),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'P$number',
                    style: Theme.of(context).textTheme.labelMedium!
                        .merge(AppTheme.monoTextStyle)
                        .copyWith(color: color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 18,
                child: selected
                    ? Icon(LucideIcons.check, color: color, size: 18)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsMenu extends StatefulWidget {
  const _DetailsMenu({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    this.items,
    this.content,
    this.focusNode,
    this.touchTargets = false,
    this.desktop = false,
    this.iconsOnly = false,
    this.semanticLabel,
  }) : assert((items == null) != (content == null));
  final String label;
  final String? semanticLabel;
  final IconData icon;
  final Color color;
  final FocusNode? focusNode;
  final bool enabled;
  final bool touchTargets;
  final bool desktop;
  final bool iconsOnly;
  final List<Widget> Function(VoidCallback close)? items;
  final Widget Function(VoidCallback close)? content;

  @override
  State<_DetailsMenu> createState() => _DetailsMenuState();
}

class _DetailsMenuState extends State<_DetailsMenu> {
  final _popover = ShadPopoverController();
  final _trigger = GlobalKey();
  final _triggerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _popover.addListener(_onPopoverChanged);
  }

  void _onPopoverChanged() {
    if (!_popover.isOpen && widget.content != null) {
      _triggerFocus.requestFocus();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(_DetailsMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _popover.isOpen) _popover.hide();
  }

  @override
  void dispose() {
    _popover.removeListener(_onPopoverChanged);
    _popover.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final style = colors.quickAddStyle(widget.color);
    final foreground = style.color!;
    final label = widget.semanticLabel ?? widget.label;
    final media = MediaQuery.of(context);
    final box = _trigger.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: media.size.center(Offset.zero),
            width: 1,
            height: 1,
          );
    final space = pickerAvailableSpace(
      anchor,
      media.size,
      viewPadding: media.viewPadding,
      viewInsets: media.viewInsets,
    );
    final width = math.max(1.0, math.min(360.0, space.width - 26));
    final centerX = space.width <= width + 26
        ? space.center.dx
        : anchor.center.dx.clamp(
            space.left + (width + 26) / 2,
            space.right - (width + 26) / 2,
          );
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: ShadPopover(
        controller: _popover,
        padding: widget.content == null ? null : const EdgeInsets.all(12),
        decoration: widget.content == null
            ? null
            : ShadDecoration(
                color: colors.surface,
                border: ShadBorder.all(
                  color: colors.border,
                  radius: BorderRadius.circular(12),
                ),
              ),
        anchor: widget.content == null
            ? null
            : ShadGlobalAnchor(Offset(centerX, space.top)),
        popover: (context) => ConstrainedBox(
          constraints: widget.content == null
              ? const BoxConstraints(maxHeight: 320, maxWidth: 280)
              : BoxConstraints(
                  maxWidth: width,
                  maxHeight: math.max(1.0, math.min(420.0, space.height - 26)),
                ),
          child:
              widget.content?.call(_popover.hide) ??
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: widget.items!(_popover.hide),
                ),
              ),
        ),
        child: MergeSemantics(
          child: Semantics(
            label: widget.iconsOnly ? label : null,
            expanded: _popover.isOpen,
            child: ShadButton.outline(
              key: _trigger,
              focusNode: widget.focusNode ?? _triggerFocus,
              size: ShadButtonSize.sm,
              height: widget.touchTargets ? 48 : 40,
              width: widget.iconsOnly ? 40 : null,
              padding: widget.iconsOnly ? EdgeInsets.zero : null,
              enabled: widget.enabled,
              onPressed: widget.enabled ? _popover.toggle : null,
              foregroundColor: foreground,
              hoverForegroundColor: foreground,
              pressedForegroundColor: foreground,
              backgroundColor: style.backgroundColor,
              hoverBackgroundColor: colors.quickAddBackground(
                foreground,
                emphasized: true,
              ),
              pressedBackgroundColor: colors.quickAddBackground(
                foreground,
                emphasized: true,
              ),
              decoration: ShadDecoration(
                border: ShadBorder.all(
                  color: colors.quickAddBorder(
                    foreground,
                    active: _popover.isOpen,
                  ),
                  radius: BorderRadius.circular(8),
                ),
              ),
              leading: Icon(
                widget.icon,
                size: widget.touchTargets || widget.desktop ? 18 : 14,
              ),
              trailing: widget.desktop && !widget.iconsOnly
                  ? const Icon(LucideIcons.chevronDown, size: 12)
                  : null,
              child: widget.iconsOnly
                  ? null
                  : Flexible(
                      child: Text(
                        widget.label,
                        semanticsLabel: widget.semanticLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
