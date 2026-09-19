part of 'timeline_screen.dart';

class _TimelineGrid extends ConsumerStatefulWidget {
  const _TimelineGrid({
    required this.day,
    required this.projectRows,
    required this.tasksByProject,
    required this.projects,
    required this.tasksById,
    required this.visibleHours,
    required this.hourWidth,
  });

  final DateTime day;
  final List<TimelineProjectRow> projectRows;
  final Map<String, List<TaskItem>> tasksByProject;
  final List<ProjectItem> projects;
  final Map<String, TaskItem> tasksById;
  final TimelineVisibleHours visibleHours;
  final int hourWidth;

  @override
  ConsumerState<_TimelineGrid> createState() => _TimelineGridState();
}

class _TimelineGridState extends ConsumerState<_TimelineGrid> {
  final _gridKey = GlobalKey();
  final _gridFocusNode = FocusNode(debugLabel: 'Timeline grid');
  final _horizontalScrollController = ScrollController();
  final _touchZoomPointers = <int, Offset>{};
  int? _addingAtMinutes;
  String? _addingProjectId;
  String? _resizingTaskId;
  int? _resizeStartEndMinutes;
  double _resizeDelta = 0;
  double? _touchZoomStartDistance;
  double? _touchZoomAnchorMinutes;
  int? _touchZoomStartHourWidth;
  int? _trackpadZoomStartHourWidth;
  (int, double, double)? _pendingGestureZoom;
  Timer? _clockTimer;

  double get _pixelsPerMinute => widget.hourWidth / 60;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _gridFocusNode.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hourWidth == widget.hourWidth ||
        !_horizontalScrollController.hasClients) {
      return;
    }
    final position = _horizontalScrollController.position;
    final oldOffset = position.pixels;
    final pendingGestureZoom = _pendingGestureZoom;
    _pendingGestureZoom = null;
    final gestureAnchor = pendingGestureZoom?.$1 == widget.hourWidth
        ? pendingGestureZoom?.$2
        : null;
    final gestureAnchorMinutes = pendingGestureZoom?.$1 == widget.hourWidth
        ? pendingGestureZoom?.$3
        : null;
    if (oldOffset <= 0.5 && gestureAnchor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(0);
        }
      });
      return;
    }
    final anchor = (gestureAnchor ?? position.viewportDimension / 2).clamp(
      0.0,
      position.viewportDimension,
    );
    final centerMinutes =
        gestureAnchorMinutes ??
        oldWidget.visibleHours.startMinutes +
            (oldOffset + anchor) / (oldWidget.hourWidth / 60);
    final target =
        (centerMinutes - widget.visibleHours.startMinutes) * _pixelsPerMinute -
        anchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_horizontalScrollController.hasClients) {
        return;
      }
      final nextPosition = _horizontalScrollController.position;
      _horizontalScrollController.jumpTo(
        target.clamp(
          nextPosition.minScrollExtent,
          nextPosition.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.visibleHours.startMinutes;
    final end = widget.visibleHours.endMinutes;
    final visibleMinutes = math.max(timelineSnapMinutes, end - start);
    final trackWidth = visibleMinutes * _pixelsPerMinute;
    final projectLayouts = _projectLayouts();
    final totalHeight = projectLayouts.isEmpty
        ? _timeRulerHeight + _laneHeight
        : projectLayouts.last.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final projectColumnWidth = constraints.maxWidth < 600 ? 112.0 : 200.0;
        return AnimatedBuilder(
          animation: _gridFocusNode,
          builder: (context, _) => Container(
            key: const Key('timeline-grid-frame'),
            decoration: BoxDecoration(
              color: context.appColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: _gridFocusNode.hasPrimaryFocus
                    ? context.appColors.accent.withValues(alpha: 0.35)
                    : context.appColors.border,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    key: const Key('timeline-project-column'),
                    width: projectColumnWidth,
                    height: totalHeight,
                    child: Column(
                      children: [
                        _ProjectColumnHeader(
                          projects: widget.projects,
                          visibleProjectIds: widget.projectRows
                              .map((row) => row.project.id)
                              .toSet(),
                        ),
                        for (final layout in projectLayouts)
                          _TimelineProjectHeader(
                            layout: layout,
                            onColor: () => _changeProjectColor(
                              context,
                              layout.row.project,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        _gridFocusNode.requestFocus();
                        _handleTouchZoomDown(event);
                      },
                      onPointerMove: _handleTouchZoomMove,
                      onPointerUp: _handleTouchZoomEnd,
                      onPointerCancel: _handleTouchZoomEnd,
                      onPointerSignal: _handlePointerSignal,
                      onPointerPanZoomStart: (event) {
                        _trackpadZoomStartHourWidth = widget.hourWidth;
                      },
                      onPointerPanZoomUpdate: (event) {
                        final startWidth = _trackpadZoomStartHourWidth;
                        if (startWidth != null && event.scale != 1) {
                          _applyGestureZoom(
                            startWidth,
                            event.scale,
                            event.localPosition.dx,
                          );
                        }
                      },
                      onPointerPanZoomEnd: (_) {
                        _trackpadZoomStartHourWidth = null;
                      },
                      child: SingleChildScrollView(
                        key: const Key('timeline-horizontal-scroll'),
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Focus(
                          focusNode: _gridFocusNode,
                          onKeyEvent: _handleGridKeyEvent,
                          child: _timelineSurface(
                            context,
                            start,
                            end,
                            trackWidth,
                            totalHeight,
                            projectLayouts,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        event.scrollDelta.dy == 0 ||
        event.scrollDelta.dx != 0 ||
        !_horizontalScrollController.hasClients) {
      return;
    }
    final position = _horizontalScrollController.position;
    final delta = axisDirectionIsReversed(position.axisDirection)
        ? -event.scrollDelta.dy
        : event.scrollDelta.dy;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      position.pointerScroll(delta);
      resolvedEvent.respond(allowPlatformDefault: false);
    });
  }

  KeyEventResult _handleGridKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => AxisDirection.left,
      LogicalKeyboardKey.arrowRight => AxisDirection.right,
      _ => null,
    };
    if (direction == null || node.context == null) {
      return KeyEventResult.ignored;
    }
    ScrollAction().invoke(ScrollIntent(direction: direction), node.context!);
    return KeyEventResult.handled;
  }

  void _handleTouchZoomDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    _touchZoomPointers[event.pointer] = event.localPosition;
    _resetTouchZoomStart();
  }

  void _handleTouchZoomMove(PointerMoveEvent event) {
    if (!_touchZoomPointers.containsKey(event.pointer)) {
      return;
    }
    _touchZoomPointers[event.pointer] = event.localPosition;
    if (_touchZoomPointers.length != 2 || _touchZoomStartDistance == null) {
      return;
    }
    final positions = _touchZoomPointers.values.toList(growable: false);
    final focalPoint = (positions[0] + positions[1]) / 2;
    _applyGestureZoom(
      _touchZoomStartHourWidth!,
      (positions[0] - positions[1]).distance / _touchZoomStartDistance!,
      focalPoint.dx,
      anchorMinutes: _touchZoomAnchorMinutes,
    );
  }

  void _handleTouchZoomEnd(PointerEvent event) {
    if (_touchZoomPointers.remove(event.pointer) != null) {
      _resetTouchZoomStart();
    }
  }

  void _resetTouchZoomStart() {
    _touchZoomStartDistance = null;
    _touchZoomAnchorMinutes = null;
    _touchZoomStartHourWidth = null;
    if (_touchZoomPointers.length != 2) {
      return;
    }
    final positions = _touchZoomPointers.values.toList(growable: false);
    _touchZoomStartDistance = (positions[0] - positions[1]).distance;
    _touchZoomStartHourWidth = widget.hourWidth;
    final focalPoint = (positions[0] + positions[1]) / 2;
    _touchZoomAnchorMinutes =
        widget.visibleHours.startMinutes +
        (_horizontalScrollController.offset + focalPoint.dx) / _pixelsPerMinute;
  }

  void _applyGestureZoom(
    int startWidth,
    double scale,
    double anchor, {
    double? anchorMinutes,
  }) {
    if (!scale.isFinite || scale <= 0) {
      return;
    }
    final currentWidth = ref.read(timelineViewModelProvider).hourWidth;
    final scaledWidth = startWidth * scale;
    var targetWidth = currentWidth;
    var targetDistance = (currentWidth - scaledWidth).abs();
    for (final width in timelineHourWidthLevels) {
      final distance = (width - scaledWidth).abs();
      if (distance < targetDistance) {
        targetWidth = width;
        targetDistance = distance;
      }
    }
    if (targetWidth == currentWidth) {
      return;
    }
    _pendingGestureZoom = (
      targetWidth,
      anchor,
      anchorMinutes ??
          widget.visibleHours.startMinutes +
              (_horizontalScrollController.offset + anchor) / _pixelsPerMinute,
    );
    unawaited(
      ref.read(timelineViewModelProvider.notifier).setHourWidth(targetWidth),
    );
  }

  List<_ProjectTimelineLayout> _projectLayouts() {
    var top = _timeRulerHeight;
    return [
      for (final row in widget.projectRows)
        (() {
          final taskLayouts = _layoutTimedTasks(
            widget.tasksByProject[row.project.id] ?? const <TaskItem>[],
          );
          final laneCount = taskLayouts.fold<int>(
            1,
            (count, layout) => math.max(count, layout.laneCount),
          );
          final layout = _ProjectTimelineLayout(
            row: row,
            tasks: taskLayouts,
            top: top,
            height: laneCount * _laneHeight,
          );
          top = layout.bottom;
          return layout;
        })(),
    ];
  }

  Widget _timelineSurface(
    BuildContext context,
    int start,
    int end,
    double width,
    double height,
    List<_ProjectTimelineLayout> projectLayouts,
  ) {
    final colors = context.appColors;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          widget.tasksById.containsKey(details.data),
      onAcceptWithDetails: (details) {
        final task = widget.tasksById[details.data];
        final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
        if (task == null || box == null) {
          return;
        }
        final local = box.globalToLocal(details.offset);
        final projectLayout = _projectLayoutAt(projectLayouts, local.dy);
        if (projectLayout == null) {
          return;
        }
        final targetMinutes = _floorSnapMinutes(
          start + (local.dx / _pixelsPerMinute).floor(),
        );
        unawaited(
          _moveTaskToMinutes(
            context,
            ref,
            task,
            targetMinutes,
            projectLayout.row.project.id,
          ),
        );
      },
      builder: (context, candidateData, rejectedData) => SizedBox(
        key: _gridKey,
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: ColoredBox(color: colors.surface)),
            for (var minute = start; minute <= end; minute += 60)
              Positioned(
                key: Key('timeline-hour-line-$minute'),
                left: (minute - start) * _pixelsPerMinute,
                top: _timeRulerHeight,
                bottom: 0,
                width: 1,
                child: ColoredBox(color: colors.border),
              ),
            for (
              var minute = start;
              minute < end;
              minute += timelineSnapMinutes
            )
              if (minute % 60 != 0)
                Positioned(
                  key: Key('timeline-quarter-tick-$minute'),
                  left: (minute - start) * _pixelsPerMinute,
                  top: _timeRulerHeight - 8,
                  width: 1,
                  height: 8,
                  child: ColoredBox(
                    color: colors.border.withValues(alpha: 0.55),
                  ),
                ),
            for (final layout in projectLayouts)
              Positioned(
                top: layout.top,
                left: 0,
                right: 0,
                height: 1,
                child: ColoredBox(color: colors.border.withValues(alpha: 0.55)),
              ),
            for (final layout in projectLayouts)
              for (
                var minute = start;
                minute < end;
                minute += timelineSnapMinutes
              )
                Positioned(
                  key: Key('timeline-slot-${layout.row.project.id}-$minute'),
                  left: (minute - start) * _pixelsPerMinute,
                  top: layout.top,
                  width: timelineSnapMinutes * _pixelsPerMinute,
                  height: layout.height,
                  child: DragTarget<String>(
                    onWillAcceptWithDetails: (details) =>
                        widget.tasksById.containsKey(details.data),
                    onAcceptWithDetails: (details) {
                      final task = widget.tasksById[details.data];
                      if (task != null) {
                        unawaited(
                          _moveTaskToMinutes(
                            context,
                            ref,
                            task,
                            minute,
                            layout.row.project.id,
                          ),
                        );
                      }
                    },
                    builder: (context, candidates, rejectedData) =>
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            _addingAtMinutes = minute;
                            _addingProjectId = layout.row.project.id;
                          }),
                          child: ColoredBox(
                            color: candidates.isEmpty
                                ? Colors.transparent
                                : colors.accentTint,
                          ),
                        ),
                  ),
                ),
            for (var minute = start; minute <= end; minute += 60)
              Positioned(
                top: 7,
                left: math.max(0, (minute - start) * _pixelsPerMinute + 6),
                width: 64,
                child: Text(
                  _formatMinutes(minute),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.mutedText),
                ),
              ),
            if (_addingAtMinutes != null && _addingProjectId != null)
              _positionedInlineAdd(context, start, width, projectLayouts),
            for (final projectLayout in projectLayouts)
              for (final taskLayout in projectLayout.tasks)
                _positionedTimedBlock(
                  context,
                  projectLayout,
                  taskLayout,
                  start,
                  end,
                ),
            ..._currentTimeIndicator(context, start, end),
          ],
        ),
      ),
    );
  }

  _ProjectTimelineLayout? _projectLayoutAt(
    List<_ProjectTimelineLayout> layouts,
    double y,
  ) {
    for (final layout in layouts) {
      if (y >= layout.top && y < layout.bottom) {
        return layout;
      }
    }
    return null;
  }

  Widget _positionedInlineAdd(
    BuildContext context,
    int visibleStart,
    double trackWidth,
    List<_ProjectTimelineLayout> layouts,
  ) {
    final projectLayout = layouts.where(
      (layout) => layout.row.project.id == _addingProjectId,
    );
    if (projectLayout.isEmpty) {
      return const SizedBox.shrink();
    }
    final rawLeft =
        (_addingAtMinutes! - visibleStart) * _pixelsPerMinute + _blockGap;
    final fieldWidth = math.min(
      _inlineAddWidth,
      math.max(120.0, trackWidth - 16),
    );
    final maxLeft = math.max(8.0, trackWidth - fieldWidth - 8);
    final left = rawLeft.clamp(8.0, maxLeft).toDouble();
    return Positioned(
      top: projectLayout.first.top + 8,
      left: left,
      width: fieldWidth,
      child: _InlineAddField(
        key: const Key('timeline-inline-add-timed'),
        hintText: context.l10n.timelineAddTimedHint(
          _formatMinutes(_addingAtMinutes!),
        ),
        onCancel: () => setState(() {
          _addingAtMinutes = null;
          _addingProjectId = null;
        }),
        onSubmit: (input) async {
          final schedule = _timedScheduleFor(
            widget.day,
            _addingAtMinutes!,
            _defaultTimedTaskDuration,
          );
          final taskId = await ref
              .read(timelineViewModelProvider.notifier)
              .create(input, projectId: _addingProjectId, schedule: schedule);
          if (mounted) {
            TaskMotionScope.maybeOf(this.context)?.created({taskId});
            await playHaptic(AppHapticCue.light);
            setState(() {
              _addingAtMinutes = null;
              _addingProjectId = null;
            });
          }
        },
      ),
    );
  }

  Widget _positionedTimedBlock(
    BuildContext context,
    _ProjectTimelineLayout projectLayout,
    _TimedTaskLayout layout,
    int visibleStart,
    int visibleEnd,
  ) {
    final task = layout.task;
    final schedule = task.schedule!;
    final startMinutes = _startMinutes(schedule);
    final realEndMinutes = _endMinutes(schedule);
    final previewEnd = _resizingTaskId == task.id
        ? _previewResizeEnd(task, realEndMinutes)
        : realEndMinutes;
    final left = (startMinutes - visibleStart) * _pixelsPerMinute + _blockGap;
    final visibleDuration = math.max(
      timelineSnapMinutes,
      math.min(previewEnd, visibleEnd) - startMinutes,
    );
    final maxVisibleWidth = math.max(
      36.0,
      (visibleEnd - startMinutes) * _pixelsPerMinute - _blockGap,
    );
    final width = math.min(
      math.max(36.0, visibleDuration * _pixelsPerMinute - _blockGap),
      maxVisibleWidth,
    );
    final top = projectLayout.top + layout.lane * _laneHeight + _blockGap;
    final height = _laneHeight - _blockGap * 2;
    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      child: _TimelineCompactTaskBlock(
        task: task,
        project: projectLayout.row.project,
        fillHeight: true,
        onResizeStart: () {
          setState(() {
            _resizingTaskId = task.id;
            _resizeStartEndMinutes = realEndMinutes;
            _resizeDelta = 0;
          });
        },
        onResizeUpdate: (delta) {
          setState(() => _resizeDelta += delta);
        },
        onResizeEnd: () {
          final endMinutes = _previewResizeEnd(task, realEndMinutes);
          setState(() {
            _resizingTaskId = null;
            _resizeStartEndMinutes = null;
            _resizeDelta = 0;
          });
          unawaited(_resizeTask(context, ref, task, endMinutes));
        },
      ),
    );
  }

  int _previewResizeEnd(TaskItem task, int fallbackEndMinutes) {
    final startMinutes = _startMinutes(task.schedule!);
    final base = _resizeStartEndMinutes ?? fallbackEndMinutes;
    return _snapMinutes(
      base + (_resizeDelta / _pixelsPerMinute).round(),
    ).clamp(startMinutes + timelineSnapMinutes, _minutesPerDay);
  }

  Future<void> _moveTaskToMinutes(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
    int targetMinutes,
    String targetProjectId,
  ) async {
    try {
      await ref
          .read(timelineViewModelProvider.notifier)
          .move(task, widget.day, targetMinutes, targetProjectId);
      if (context.mounted) {
        TaskMotionScope.maybeOf(context)?.landed({task.id});
        await playHaptic(AppHapticCue.light);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.taskActionFailedCount(1))),
        );
      }
    }
  }

  Future<void> _resizeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
    int endMinutes,
  ) async {
    final startMinutes = _startMinutes(task.schedule!);
    final duration = Duration(minutes: endMinutes - startMinutes);
    await _updateSchedule(
      context,
      ref,
      task,
      _timedScheduleFor(widget.day, startMinutes, duration),
    );
  }

  List<Widget> _currentTimeIndicator(
    BuildContext context,
    int visibleStart,
    int visibleEnd,
  ) {
    final now = ref.read(timelineViewModelProvider).now;
    final minute = now.hour * 60 + now.minute;
    if (!_isSameDay(widget.day, now) ||
        minute < visibleStart ||
        minute >= visibleEnd) {
      return const [];
    }
    return [
      Positioned(
        key: const Key('timeline-current-time-indicator'),
        left: (minute - visibleStart) * _pixelsPerMinute,
        top: _timeRulerHeight,
        bottom: 0,
        width: 1,
        child: Semantics(
          label: context.l10n.timelineCurrentTime,
          child: ColoredBox(color: context.appColors.accent),
        ),
      ),
    ];
  }

  Future<void> _changeProjectColor(
    BuildContext context,
    ProjectItem project,
  ) async {
    if (project.id == inboxProjectId) {
      return;
    }
    final color = await showProjectColorPicker(
      context,
      selectedColor: effectiveProjectColor(project),
    );
    if (color == null || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(timelineViewModelProvider.notifier)
          .updateProject(project.id, UpdateProjectPatch(color: color));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotUpdateProject(error))),
        );
      }
    }
  }
}
