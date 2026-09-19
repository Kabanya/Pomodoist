import 'package:pomodoist/domain/models/tasks/task_time.dart';

const reengagementNotificationsEnabledPreferenceKey =
    'notifications.reengagement.enabled';
const quickAddDefaultTimedBlockMinutesPreferenceKey =
    'quickAdd.defaultTimedBlockMinutes';
const taskTimeDisplayModePreferenceKey = 'tasks.timeDisplayMode';
const taskListStylePreferenceKey = 'tasks.listStyle';
const taskRowSpacingPreferenceKey = 'tasks.rowSpacing';
const timelineVisibleStartMinutesPreferenceKey = 'timeline.visibleStartMinutes';
const timelineVisibleEndMinutesPreferenceKey = 'timeline.visibleEndMinutes';
const timelineHourWidthPreferenceKey = 'timeline.hourWidth';
const timelineCollapsedProjectIdsPreferenceKey = 'timeline.collapsedProjectIds';
const defaultQuickAddTimedBlockMinutes = 30;
const minQuickAddTimedBlockMinutes = 1;
const maxQuickAddTimedBlockMinutes = 480;
const timelineSnapMinutes = 15;
const defaultTimelineVisibleStartMinutes = 0;
const defaultTimelineVisibleEndMinutes = 24 * 60;
const defaultTimelineHourWidth = 192;
const timelineHourWidthLevels = <int>[96, 144, 192, 288, 384];

enum TaskListStyle { modern, classic }

enum TaskRowSpacing { compact, comfortable, spacious }

class TimelineVisibleHours {
  const TimelineVisibleHours({
    required this.startMinutes,
    required this.endMinutes,
  });

  final int startMinutes;
  final int endMinutes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TimelineVisibleHours &&
            other.startMinutes == startMinutes &&
            other.endMinutes == endMinutes;
  }

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);
}

class TaskPreferences {
  const TaskPreferences({
    this.reengagementEnabled = true,
    this.quickAddMinutes = defaultQuickAddTimedBlockMinutes,
    this.timeDisplayMode = TaskTimeDisplayMode.smart,
    this.listStyle = TaskListStyle.modern,
    this.rowSpacing = TaskRowSpacing.comfortable,
    this.visibleHours = const TimelineVisibleHours(
      startMinutes: 0,
      endMinutes: 1440,
    ),
    this.hourWidth = defaultTimelineHourWidth,
    this.collapsedProjectIds = const {},
  });
  final bool reengagementEnabled;
  final int quickAddMinutes;
  final TaskTimeDisplayMode timeDisplayMode;
  final TaskListStyle listStyle;
  final TaskRowSpacing rowSpacing;
  final TimelineVisibleHours visibleHours;
  final int hourWidth;
  final Set<String> collapsedProjectIds;
  TaskPreferences copyWith({
    bool? reengagementEnabled,
    int? quickAddMinutes,
    TaskTimeDisplayMode? timeDisplayMode,
    TaskListStyle? listStyle,
    TaskRowSpacing? rowSpacing,
    TimelineVisibleHours? visibleHours,
    int? hourWidth,
    Set<String>? collapsedProjectIds,
  }) => TaskPreferences(
    reengagementEnabled: reengagementEnabled ?? this.reengagementEnabled,
    quickAddMinutes: quickAddMinutes ?? this.quickAddMinutes,
    timeDisplayMode: timeDisplayMode ?? this.timeDisplayMode,
    listStyle: listStyle ?? this.listStyle,
    rowSpacing: rowSpacing ?? this.rowSpacing,
    visibleHours: visibleHours ?? this.visibleHours,
    hourWidth: hourWidth ?? this.hourWidth,
    collapsedProjectIds: collapsedProjectIds ?? this.collapsedProjectIds,
  );
}
