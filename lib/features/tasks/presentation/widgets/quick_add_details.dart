import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        LucideIcons,
        ShadButton,
        ShadButtonSize,
        ShadPopover,
        ShadPopoverController;

import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../planning/domain/quick_add_parser.dart';
import '../../domain/task_models.dart';
import 'quick_add_metadata_edit.dart';
import 'quick_add_text_controller.dart';

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
  });

  final QuickAddTextController controller;
  final DateTime? defaultDate;
  final TaskSchedule? defaultSchedule;
  final String? projectId;
  final String? inheritedProjectName;
  final int? priority;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parser = ref.watch(quickAddParserProvider);
    final clock = ref.watch(clockProvider);
    ref.watch(
      focusTickerProvider.select((tick) {
        final date = (tick.value ?? clock.now()).toLocal();
        return DateTime(date.year, date.month, date.day);
      }),
    );
    final projects =
        (ref.watch(projectsProvider).value ?? const <ProjectItem>[])
            .where((project) => !project.isArchived && !project.isDeleted)
            .toList();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.trim().isEmpty) return const SizedBox.shrink();
        final now = clock.now();
        final analysis = parser.analyze(
          value.text,
          now: now,
          defaultDate: defaultDate,
        );
        final parsed = analysis.parsed;
        final schedule =
            parsed.schedule ??
            (parsed.dueDate == null ? defaultSchedule : null);
        final canEdit =
            enabled &&
            (value.composing.isCollapsed || !value.composing.isValid);
        var projectName = inheritedProjectName ?? context.l10n.navInbox;
        for (final project in projects) {
          if (project.id == projectId && inheritedProjectName == null) {
            projectName = project.name;
          }
        }
        projectName = parsed.project ?? projectName;
        void edit(Set<QuickAddTokenKind> kinds, String? token) {
          if (!enabled) return;
          final current = controller.value;
          final next = rewriteQuickAddMetadata(
            current,
            parser.analyze(
              current.text,
              now: clock.now(),
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
          final current = parser
              .analyze(
                controller.text,
                now: clock.now(),
                defaultDate: defaultDate,
                includeInvalidScheduling: true,
              )
              .parsed;
          return current.schedule ??
              (current.dueDate == null ? defaultSchedule : null);
        }

        Future<void> changeDate() async {
          final current = currentSchedule();
          final initial = current?.displayDate ?? clock.now();
          final date = await showDatePicker(
            context: context,
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

        Future<void> changeTime() async {
          final current = currentSchedule();
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(
              current?.start?.toLocal() ?? clock.now(),
            ),
          );
          if (time == null || !context.mounted) return;
          final latest = currentSchedule();
          final date = latest?.displayDate ?? clock.now();
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
                  latest?.duration ?? parser.defaultTimedBlockDuration,
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
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parsed.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    parsed.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.secondaryText,
                    ),
                  ),
                ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _DetailsMenu(
                    label: timeLabel == null
                        ? dateLabel
                        : '$dateLabel · $timeLabel',
                    icon: LucideIcons.calendar,
                    enabled: canEdit,
                    items: (close) => [
                      _option(context.l10n.timelinePickDate, () {
                        close();
                        changeDate();
                      }),
                      _option(context.l10n.quickAddChangeTime, () {
                        close();
                        changeTime();
                      }),
                      _option(context.l10n.allDay, () {
                        close();
                        edit(
                          quickAddSchedulingKinds,
                          quickAddScheduleToken(
                            TaskSchedule.allDay(
                              currentSchedule()?.displayDate ?? clock.now(),
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
                  _DetailsMenu(
                    label: projectName,
                    icon: LucideIcons.hash,
                    enabled: canEdit,
                    items: (close) => [
                      _option(context.l10n.quickAddResetDetails, () {
                        close();
                        edit({QuickAddTokenKind.project}, null);
                      }),
                      for (final project in projects)
                        Tooltip(
                          message:
                              quickAddProjectToken(
                                    project.name,
                                    parser,
                                    now: now,
                                  ) ==
                                  null
                              ? context.l10n.quickAddProjectNameUnsupported
                              : project.name,
                          child: _option(
                            project.name,
                            quickAddProjectToken(
                                      project.name,
                                      parser,
                                      now: now,
                                    ) ==
                                    null
                                ? null
                                : () {
                                    close();
                                    edit(
                                      {QuickAddTokenKind.project},
                                      quickAddProjectToken(
                                        project.name,
                                        parser,
                                        now: clock.now(),
                                      ),
                                    );
                                  },
                          ),
                        ),
                    ],
                  ),
                  _DetailsMenu(
                    label: context.l10n.priority(
                      parsed.priority ?? priority ?? 4,
                    ),
                    icon: LucideIcons.flag,
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
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _option(String label, VoidCallback? action) => ShadButton.ghost(
  enabled: action != null,
  onPressed: action,
  size: ShadButtonSize.sm,
  child: Text(label, overflow: TextOverflow.ellipsis),
);

class _DetailsMenu extends StatefulWidget {
  const _DetailsMenu({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.items,
  });
  final String label;
  final IconData icon;
  final bool enabled;
  final List<Widget> Function(VoidCallback close) items;

  @override
  State<_DetailsMenu> createState() => _DetailsMenuState();
}

class _DetailsMenuState extends State<_DetailsMenu> {
  final _popover = ShadPopoverController();
  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShadPopover(
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
    child: ShadButton.outline(
      size: ShadButtonSize.sm,
      enabled: widget.enabled,
      onPressed: widget.enabled ? _popover.toggle : null,
      leading: Icon(widget.icon, size: 14),
      child: Flexible(
        child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}
