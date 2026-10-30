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
        ShadPopoverController;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_details_view_model.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';
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
            (parsed.dueDate == null ? defaultSchedule : null);
        final canEdit =
            enabled &&
            (value.composing.isCollapsed || !value.composing.isValid);
        var projectName = inheritedProjectName ?? context.l10n.navInbox;
        for (final project in allProjects) {
          if (project.id == projectId && inheritedProjectName == null) {
            projectName = project.displayName(context.l10n);
          }
        }
        if (parsed.project case final name?) {
          projectName = name;
          for (final project in allProjects) {
            if (project.name.toLowerCase() == name.toLowerCase()) {
              projectName = project.displayName(context.l10n);
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
              (current.dueDate == null ? defaultSchedule : null);
        }

        Future<void> changeDate(AppDateTimePickerState picker) async {
          final current = currentSchedule();
          final initial = current?.displayDate ?? viewModel.now();
          final date = await picker.pickDate(
            initialDate: initial,
            firstDate: DateTime(1),
            lastDate: DateTime(9999, 12, 31),
          );
          if (date == null || !context.mounted) return;
          final latest = currentSchedule();
          edit(
            quickAddSchedulingKinds,
            quickAddScheduleToken(
              latest?.moveToDate(date) ?? TaskSchedule.allDay(date),
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

        final material = MaterialLocalizations.of(context);
        final dateLabel = schedule == null
            ? context.l10n.noDate
            : material.formatCompactDate(schedule.displayDate);
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
                      items: (close) => [
                        _option(context.l10n.timelinePickDate, () {
                          close();
                          changeDate(picker);
                        }),
                        _option(context.l10n.quickAddChangeTime, () {
                          close();
                          changeTime(picker);
                        }),
                        _option(context.l10n.allDay, () {
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
                        }),
                        _option(context.l10n.quickAddResetDetails, () {
                          close();
                          edit(quickAddSchedulingKinds, null);
                        }),
                      ],
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
                    items: (close) => [
                      _option(context.l10n.quickAddResetDetails, () {
                        close();
                        edit({QuickAddTokenKind.project}, null);
                      }),
                      for (final project in projects)
                        Tooltip(
                          message: viewModel.projectToken(project.name) == null
                              ? context.l10n.quickAddProjectNameUnsupported
                              : project.displayName(context.l10n),
                          child: _option(
                            project.displayName(context.l10n),
                            viewModel.projectToken(project.name) == null
                                ? null
                                : () {
                                    close();
                                    edit({
                                      QuickAddTokenKind.project,
                                    }, viewModel.projectToken(project.name));
                                  },
                          ),
                        ),
                    ],
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
                        _option(context.l10n.priority(number), () {
                          close();
                          edit({QuickAddTokenKind.priority}, 'p$number');
                        }),
                      _option(context.l10n.quickAddResetDetails, () {
                        close();
                        edit({QuickAddTokenKind.priority}, null);
                      }),
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

  Widget _option(String label, VoidCallback? action) => ShadButton.ghost(
    enabled: action != null,
    onPressed: action,
    size: ShadButtonSize.sm,
    height: touchTargets ? 48 : null,
    child: Text(label, overflow: TextOverflow.ellipsis),
  );
}

class _DetailsMenu extends StatefulWidget {
  const _DetailsMenu({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.items,
    this.focusNode,
    this.touchTargets = false,
    this.desktop = false,
    this.iconsOnly = false,
    this.semanticLabel,
  });
  final String label;
  final String? semanticLabel;
  final IconData icon;
  final Color color;
  final FocusNode? focusNode;
  final bool enabled;
  final bool touchTargets;
  final bool desktop;
  final bool iconsOnly;
  final List<Widget> Function(VoidCallback close) items;

  @override
  State<_DetailsMenu> createState() => _DetailsMenuState();
}

class _DetailsMenuState extends State<_DetailsMenu> {
  final _popover = ShadPopoverController();

  @override
  void initState() {
    super.initState();
    _popover.addListener(_onPopoverChanged);
  }

  void _onPopoverChanged() => setState(() {});

  @override
  void dispose() {
    _popover.removeListener(_onPopoverChanged);
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final style = colors.quickAddStyle(widget.color);
    final foreground = style.color!;
    final label = widget.semanticLabel ?? widget.label;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: ShadPopover(
        controller: _popover,
        popover: (context) => ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 280),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: widget.items(_popover.hide),
            ),
          ),
        ),
        child: MergeSemantics(
          child: Semantics(
            label: widget.iconsOnly ? label : null,
            expanded: _popover.isOpen,
            child: ShadButton.outline(
              focusNode: widget.focusNode,
              size: ShadButtonSize.sm,
              height: widget.touchTargets ? 48 : (widget.desktop ? 40 : null),
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
