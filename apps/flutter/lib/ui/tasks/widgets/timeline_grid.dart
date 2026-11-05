part of 'timeline_screen.dart';

class _TimelineGrid extends ConsumerStatefulWidget {
  const _TimelineGrid({
    required this.day,
    required this.projectRows,
    required this.tasksByProject,
    required this.compact,
    required this.baseHourExtent,
    required this.tasksById,
    required this.visibleHours,
    required this.hourWidth,
  });

  final DateTime day;
  final List<TimelineProjectRow> projectRows;
  final Map<String, List<TaskItem>> tasksByProject;
  final bool compact;
  final double baseHourExtent;
  final Map<String, TaskItem> tasksById;
  final TimelineVisibleHours visibleHours;
  final int hourWidth;

  @override
  ConsumerState<_TimelineGrid> createState() => _TimelineGridState();
}

class _TimelineGridState extends ConsumerState<_TimelineGrid> {
  final _gridKey = GlobalKey();
  final _verticalKey = GlobalKey();
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
  double get _pixelsPerMinute => _timelinePixelsPerMinute(widget);

  double _timelinePixelsPerMinute(_TimelineGrid grid) =>
      grid.baseHourExtent * grid.hourWidth / defaultTimelineHourWidth / 60;

  ScrollPosition? get _timeScrollPosition => widget.compact
      ? Scrollable.maybeOf(context, axis: Axis.vertical)?.position
      : _horizontalScrollController.hasClients
      ? _horizontalScrollController.position
      : null;

  double _verticalStart() {
    final render = _verticalKey.currentContext?.findRenderObject();
    if (render == null || !render.attached) return 0;
    return RenderAbstractViewport.of(
      render,
    ).getOffsetToReveal(render, 0).offset;
  }

  double _timeCoordinate(Offset position) => widget.compact
      ? position.dy
      : Directionality.of(context) == TextDirection.rtl
      ? (_timeScrollPosition?.viewportDimension ?? 0) - position.dx
      : position.dx;

  @override
  void dispose() {
    _gridFocusNode.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact) {
      _touchZoomPointers.clear();
      _resetTouchZoomStart();
      _pendingGestureZoom = null;
      _resizingTaskId = null;
      _resizeStartEndMinutes = null;
      _resizeDelta = 0;
      _addingAtMinutes = null;
      _addingProjectId = null;
      return;
    }
    if (oldWidget.hourWidth == widget.hourWidth) return;
    final position = _timeScrollPosition;
    final pending = _pendingGestureZoom;
    _pendingGestureZoom = null;
    if (position == null || !position.hasContentDimensions) return;
    final origin = widget.compact ? _verticalStart() : 0.0;
    final oldOffset = position.pixels - origin;
    final gesture = pending?.$1 == widget.hourWidth ? pending : null;
    if (oldOffset <= 0.5 && gesture == null) return;
    final anchor = gesture?.$2 ?? position.viewportDimension / 2;
    final minutes =
        gesture?.$3 ??
        oldWidget.visibleHours.startMinutes +
            (oldOffset + anchor) / _timelinePixelsPerMinute(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_timeScrollPosition, position)) return;
      final nextOrigin = widget.compact ? _verticalStart() : 0.0;
      final target =
          nextOrigin +
          (minutes - widget.visibleHours.startMinutes) * _pixelsPerMinute -
          anchor;
      position.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.visibleHours.startMinutes;
    final end = widget.visibleHours.endMinutes;
    if (widget.compact) return _verticalSurface(context, start, end);
    final visibleMinutes = math.max(timelineSnapMinutes, end - start);
    final trackWidth = visibleMinutes * _pixelsPerMinute;
    final projectLayouts = _projectLayouts();
    final contentWidth = projectLayouts
        .expand((layout) => layout.tasks)
        .fold(
          trackWidth + _timelineRulerTail(context),
          (extent, task) => math.max(
            extent,
            (timelineStartMinutes(task.task.schedule!) - start) *
                    _pixelsPerMinute +
                _desktopMinimumCardWidth +
                _blockGap,
          ),
        );
    final width = _addingAtMinutes == null
        ? contentWidth
        : math.max(contentWidth, _inlineAddWidth + 16);
    final totalHeight = projectLayouts.isEmpty
        ? _timeRulerHeight + _laneHeight
        : projectLayouts.last.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final projectColumnWidth = _timelineProjectColumnWidth(
          context,
          constraints.maxWidth,
        );
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
                        const SizedBox(height: _timeRulerHeight),
                        for (final layout in projectLayouts)
                          _TimelineProjectHeader(
                            layout: layout,
                            onColor: () => _changeTimelineProjectColor(
                              context,
                              ref,
                              layout.row.project,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _gestureSurface(
                      horizontal: true,
                      child: SingleChildScrollView(
                        key: const Key('timeline-horizontal-scroll'),
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: ShortcutHintsScope(
                          hints: [
                            ShortcutHint(
                              context.l10n.shortcutHintsNavigate,
                              '← →',
                            ),
                          ],
                          child: Focus(
                            focusNode: _gridFocusNode,
                            onKeyEvent: _handleGridKeyEvent,
                            child: _timelineSurface(
                              context,
                              start,
                              end,
                              width,
                              totalHeight,
                              projectLayouts,
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
        );
      },
    );
  }

  Widget _verticalSurface(BuildContext context, int start, int end) {
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final largeText = textScaler.scale(16) > 20;
    final minimumHeight = largeText ? textScaler.scale(37) * 1.25 + 10 : 44.0;
    final projectsById = {
      for (final row in widget.projectRows) row.project.id: row.project,
    };
    final layouts = _layoutTimedTasks([
      for (final id in projectsById.keys)
        ...widget.tasksByProject[id] ?? const <TaskItem>[],
    ], minimumMinutes: ((minimumHeight + _blockGap) / _pixelsPerMinute).ceil());
    final lanes = layouts.fold(
      1,
      (count, layout) => math.max(count, layout.laneCount),
    );
    final trackHeight = (end - start) * _pixelsPerMinute;
    final height = layouts.fold(
      math.max(56.0, trackHeight + 24),
      (height, layout) => math.max(
        height,
        (timelineStartMinutes(layout.task.schedule!) - start) *
                _pixelsPerMinute +
            minimumHeight +
            _blockGap,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = math.max(_mobileGutter, textScaler.scale(48));
        final viewport = math.max(1.0, constraints.maxWidth - gutter);
        final minimumLaneWidth = math.max(144.0, textScaler.scale(104) + 44);
        final trackWidth = math.max(viewport, lanes * minimumLaneWidth);
        final minutes = _addingAtMinutes;
        final now = _visibleCurrentMinute(start, end);
        final track = DragTarget<String>(
          onWillAcceptWithDetails: (details) =>
              widget.tasksById.containsKey(details.data),
          onAcceptWithDetails: (details) {
            final task = widget.tasksById[details.data];
            final box =
                _verticalKey.currentContext?.findRenderObject() as RenderBox?;
            if (task == null || box == null) return;
            final y = box.globalToLocal(details.offset).dy;
            if (y < 0 || y >= trackHeight) return;
            final minute = _floorSnapMinutes(
              start + (y / _pixelsPerMinute).floor(),
            );
            unawaited(
              _moveTaskToMinutes(context, ref, task, minute, task.projectId),
            );
          },
          builder: (context, candidates, _) => SizedBox(
            key: const Key('timeline-vertical-track'),
            width: trackWidth,
            height: height,
            child: Stack(
              children: [
                for (
                  var minute = start;
                  minute < end;
                  minute += timelineSnapMinutes
                )
                  PositionedDirectional(
                    key: Key('timeline-slot-$inboxProjectId-$minute'),
                    top: (minute - start) * _pixelsPerMinute,
                    start: 0,
                    end: 0,
                    height: timelineSnapMinutes * _pixelsPerMinute,
                    child: _slot(minute, inboxProjectId, keepProject: true),
                  ),
                for (var minute = start; minute <= end; minute += 60)
                  PositionedDirectional(
                    key: Key('timeline-hour-line-$minute'),
                    top: (minute - start) * _pixelsPerMinute,
                    start: 0,
                    end: 0,
                    height: 1,
                    child: IgnorePointer(
                      child: ColoredBox(color: colors.border),
                    ),
                  ),
                for (final layout in layouts)
                  _verticalTask(
                    layout,
                    projectsById[layout.task.projectId],
                    start,
                    end,
                    trackWidth,
                    minimumHeight,
                  ),
                if (now != null)
                  PositionedDirectional(
                    key: const Key('timeline-current-time-indicator'),
                    top: (now - start) * _pixelsPerMinute,
                    start: 0,
                    end: 0,
                    height: 1,
                    child: IgnorePointer(
                      child: Semantics(
                        label: context.l10n.timelineCurrentTime,
                        child: ColoredBox(color: colors.accent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        return _gestureSurface(
          horizontal: false,
          child: SizedBox(
            key: _verticalKey,
            height: height,
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: gutter,
                      height: height,
                      child: Stack(
                        children: [
                          PositionedDirectional(
                            end: 0,
                            top: 0,
                            bottom: 0,
                            width: 1,
                            child: ColoredBox(color: colors.border),
                          ),
                          for (var minute = start; minute <= end; minute += 60)
                            PositionedDirectional(
                              top: (minute - start) * _pixelsPerMinute,
                              start: 0,
                              end: 6,
                              child: Text(
                                _formatMinutes(minute),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.mutedText,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: trackWidth > viewport
                          ? SingleChildScrollView(
                              key: const Key('timeline-overlap-scroll'),
                              scrollDirection: Axis.horizontal,
                              child: track,
                            )
                          : track,
                    ),
                  ],
                ),
                if (minutes != null && minutes >= start && minutes < end)
                  PositionedDirectional(
                    start: gutter + _blockGap,
                    end: 4,
                    top: math.min(
                      (minutes - start) * _pixelsPerMinute,
                      height - 52,
                    ),
                    child: _inlineTimedField(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _verticalTask(
    _TimedTaskLayout layout,
    ProjectItem? project,
    int start,
    int end,
    double trackWidth,
    double minimumHeight,
  ) {
    final task = layout.task;
    final startMinutes = timelineStartMinutes(task.schedule!);
    final endMinutes = timelineEndMinutes(task.schedule!);
    final previewEnd = _resizingTaskId == task.id
        ? _previewResizeEnd(task, endMinutes)
        : endMinutes;
    final laneWidth = trackWidth / layout.laneCount;
    final height =
        (math.min(previewEnd, end) - startMinutes) * _pixelsPerMinute;
    return PositionedDirectional(
      start: layout.lane * laneWidth + _blockGap,
      top: (startMinutes - start) * _pixelsPerMinute + _blockGap / 2,
      width: laneWidth - 2 * _blockGap,
      height: math.max(minimumHeight, height - _blockGap),
      child: _timedBlock(task, project, endMinutes),
    );
  }

  Widget _slot(int minute, String projectId, {bool keepProject = false}) {
    return DragTarget<String>(
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
              keepProject ? task.projectId : projectId,
            ),
          );
        }
      },
      builder: (context, candidates, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _addingAtMinutes = minute;
          _addingProjectId = projectId;
        }),
        child: ColoredBox(
          color: candidates.isEmpty
              ? Colors.transparent
              : context.appColors.accentTint,
        ),
      ),
    );
  }

  Widget _gestureSurface({required bool horizontal, required Widget child}) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (horizontal) _gridFocusNode.requestFocus();
        _handleTouchZoomDown(event);
      },
      onPointerMove: _handleTouchZoomMove,
      onPointerUp: _handleTouchZoomEnd,
      onPointerCancel: _handleTouchZoomEnd,
      onPointerSignal: horizontal ? _handlePointerSignal : null,
      onPointerPanZoomStart: (_) {
        _trackpadZoomStartHourWidth = widget.hourWidth;
      },
      onPointerPanZoomUpdate: (event) {
        final startWidth = _trackpadZoomStartHourWidth;
        if (startWidth != null && event.scale != 1) {
          _applyGestureZoom(
            startWidth,
            event.scale,
            _timeCoordinate(event.localPosition),
          );
        }
      },
      onPointerPanZoomEnd: (_) => _trackpadZoomStartHourWidth = null,
      child: child,
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
      _timeCoordinate(focalPoint),
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
        _contentTimeOffset(_timeCoordinate(focalPoint)) / _pixelsPerMinute;
  }

  double _contentTimeOffset(double anchor) =>
      widget.compact ? anchor : (_timeScrollPosition?.pixels ?? 0) + anchor;

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
    final viewportAnchor = widget.compact
        ? anchor + _verticalStart() - (_timeScrollPosition?.pixels ?? 0)
        : anchor;
    _pendingGestureZoom = (
      targetWidth,
      viewportAnchor,
      anchorMinutes ??
          widget.visibleHours.startMinutes +
              _contentTimeOffset(anchor) / _pixelsPerMinute,
    );
    unawaited(
      ref.read(timelineViewModelProvider.notifier).setHourWidth(targetWidth),
    );
  }

  double get _desktopMinimumCardWidth =>
      math.max(148, MediaQuery.textScalerOf(context).scale(104) + 44);

  double _desktopCardHeight(BuildContext context) =>
      math.max(66, MediaQuery.textScalerOf(context).scale(42) * 1.25 + 8);

  double _desktopLaneHeight(BuildContext context) =>
      math.max(_laneHeight, _desktopCardHeight(context) + 32);

  List<_ProjectTimelineLayout> _projectLayouts() {
    var top = _timeRulerHeight;
    return [
      for (final row in widget.projectRows)
        (() {
          final taskLayouts = _layoutTimedTasks(
            widget.tasksByProject[row.project.id] ?? const <TaskItem>[],
            minimumMinutes:
                ((_desktopMinimumCardWidth + _blockGap) / _pixelsPerMinute)
                    .ceil(),
          );
          final laneCount = taskLayouts.fold<int>(
            1,
            (count, layout) => math.max(count, layout.laneCount),
          );
          final layout = _ProjectTimelineLayout(
            row: row,
            tasks: taskLayouts,
            top: top,
            height: laneCount * _desktopLaneHeight(context),
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
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final timeOffset = rtl ? width - local.dx : local.dx;
        if (timeOffset < 0 || timeOffset >= (end - start) * _pixelsPerMinute) {
          return;
        }
        final targetMinutes = _floorSnapMinutes(
          start + (timeOffset / _pixelsPerMinute).floor(),
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
              PositionedDirectional(
                key: Key('timeline-hour-line-$minute'),
                start: (minute - start) * _pixelsPerMinute,
                top: _timeRulerHeight,
                bottom: 0,
                width: 1,
                child: IgnorePointer(child: ColoredBox(color: colors.border)),
              ),
            for (
              var minute = start;
              minute < end;
              minute += timelineSnapMinutes
            )
              if (minute % 60 != 0)
                PositionedDirectional(
                  key: Key('timeline-quarter-tick-$minute'),
                  start: (minute - start) * _pixelsPerMinute,
                  top: _timeRulerHeight - 8,
                  width: 1,
                  height: 8,
                  child: ColoredBox(
                    color: colors.border.withValues(alpha: 0.55),
                  ),
                ),
            for (final layout in projectLayouts)
              PositionedDirectional(
                top: layout.top,
                start: 0,
                end: 0,
                height: 1,
                child: ColoredBox(color: colors.border.withValues(alpha: 0.55)),
              ),
            for (final layout in projectLayouts)
              for (
                var minute = start;
                minute < end;
                minute += timelineSnapMinutes
              )
                PositionedDirectional(
                  key: Key('timeline-slot-${layout.row.project.id}-$minute'),
                  start: (minute - start) * _pixelsPerMinute,
                  top: layout.top,
                  width: timelineSnapMinutes * _pixelsPerMinute,
                  height: layout.height,
                  child: _slot(minute, layout.row.project.id),
                ),
            for (var minute = start; minute <= end; minute += 60)
              PositionedDirectional(
                top: 7,
                start: math.max(0, (minute - start) * _pixelsPerMinute + 6),
                width: _timelineRulerTail(context) - 6,
                child: Text(
                  _formatMinutes(minute),
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.mutedText),
                ),
              ),
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
            if (_addingAtMinutes != null &&
                _addingAtMinutes! >= start &&
                _addingAtMinutes! < end &&
                _addingProjectId != null)
              _positionedInlineAdd(context, start, width, projectLayouts),
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
    return PositionedDirectional(
      top: projectLayout.first.top + 8,
      start: left,
      width: fieldWidth,
      child: _inlineTimedField(),
    );
  }

  Widget _inlineTimedField() {
    return _InlineAddField(
      key: const Key('timeline-inline-add-timed'),
      hintText: context.l10n.timelineAddTimedHint(
        _formatMinutes(_addingAtMinutes!),
      ),
      onCancel: _clearInlineAdd,
      onSubmit: (input) async {
        final schedule = _timedScheduleFor(
          widget.day,
          _addingAtMinutes!,
          _defaultTimedTaskDuration,
        );
        final taskId = await ref
            .read(timelineViewModelProvider.notifier)
            .create(input, projectId: _addingProjectId, schedule: schedule);
        if (!mounted) return;
        TaskMotionScope.maybeOf(context)?.created({taskId});
        _clearInlineAdd();
        await playHaptic(AppHapticCue.light);
      },
    );
  }

  void _clearInlineAdd() => setState(() {
    _addingAtMinutes = null;
    _addingProjectId = null;
  });

  Widget _positionedTimedBlock(
    BuildContext context,
    _ProjectTimelineLayout projectLayout,
    _TimedTaskLayout layout,
    int visibleStart,
    int visibleEnd,
  ) {
    final task = layout.task;
    final schedule = task.schedule!;
    final startMinutes = timelineStartMinutes(schedule);
    final realEndMinutes = timelineEndMinutes(schedule);
    final previewEnd = _resizingTaskId == task.id
        ? _previewResizeEnd(task, realEndMinutes)
        : realEndMinutes;
    final left = (startMinutes - visibleStart) * _pixelsPerMinute + _blockGap;
    final visibleDuration = math.max(
      timelineSnapMinutes,
      math.min(previewEnd, visibleEnd) - startMinutes,
    );
    final width = math.max(
      _desktopMinimumCardWidth,
      visibleDuration * _pixelsPerMinute - _blockGap,
    );
    final top =
        projectLayout.top + layout.lane * _desktopLaneHeight(context) + 16;
    final height = _desktopCardHeight(context);
    return PositionedDirectional(
      top: top,
      start: left,
      width: width,
      height: height,
      child: _timedBlock(task, projectLayout.row.project, realEndMinutes),
    );
  }

  Widget _timedBlock(TaskItem task, ProjectItem? project, int realEndMinutes) {
    return _TimelineCompactTaskBlock(
      task: task,
      project: project,
      fillHeight: true,
      showProjectName: widget.compact,
      vertical: widget.compact,
      onResizeStart: () => setState(() {
        _resizingTaskId = task.id;
        _resizeStartEndMinutes = realEndMinutes;
        _resizeDelta = 0;
      }),
      onResizeUpdate: (delta) => setState(() => _resizeDelta += delta),
      onResizeCancel: _clearResize,
      onResizeEnd: () {
        final endMinutes = _previewResizeEnd(task, realEndMinutes);
        _clearResize();
        unawaited(_resizeTask(context, ref, task, endMinutes));
      },
    );
  }

  void _clearResize() => setState(() {
    _resizingTaskId = null;
    _resizeStartEndMinutes = null;
    _resizeDelta = 0;
  });

  int _previewResizeEnd(TaskItem task, int fallbackEndMinutes) {
    final startMinutes = timelineStartMinutes(task.schedule!);
    final base = _resizeStartEndMinutes ?? fallbackEndMinutes;
    return _snapMinutes(
      base + (_resizeDelta / _pixelsPerMinute).round(),
    ).clamp(startMinutes + timelineSnapMinutes, timelineMinutesPerDay);
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
    final startMinutes = timelineStartMinutes(task.schedule!);
    final duration = Duration(minutes: endMinutes - startMinutes);
    await _updateSchedule(
      context,
      ref,
      task,
      _timedScheduleFor(widget.day, startMinutes, duration),
    );
  }

  int? _visibleCurrentMinute(int start, int end) {
    final now = ref.read(timelineViewModelProvider).now;
    final minute = now.hour * 60 + now.minute;
    return isSameLocalDay(widget.day, now) && minute >= start && minute < end
        ? minute
        : null;
  }

  List<Widget> _currentTimeIndicator(
    BuildContext context,
    int visibleStart,
    int visibleEnd,
  ) {
    final minute = _visibleCurrentMinute(visibleStart, visibleEnd);
    if (minute == null) return const [];
    return [
      PositionedDirectional(
        key: const Key('timeline-current-time-indicator'),
        start: (minute - visibleStart) * _pixelsPerMinute,
        top: _timeRulerHeight,
        bottom: 0,
        width: 1,
        child: IgnorePointer(
          child: Semantics(
            label: context.l10n.timelineCurrentTime,
            child: ColoredBox(color: context.appColors.accent),
          ),
        ),
      ),
    ];
  }
}

Future<void> _changeTimelineProjectColor(
  BuildContext context,
  WidgetRef ref,
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
