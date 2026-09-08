import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/tasks/presentation/task_detail_screen.dart';
import '../task_detail_navigation.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Keeps the background mounted across task selection and responsive changes.
class TaskDetailsHost extends StatefulWidget {
  const TaskDetailsHost({required this.taskId, required this.child, super.key});

  final String? taskId;
  final Widget child;

  @override
  State<TaskDetailsHost> createState() => _TaskDetailsHostState();
}

class _TaskDetailsHostState extends State<TaskDetailsHost> {
  FocusNode? _returnFocus;

  @override
  void didUpdateWidget(covariant TaskDetailsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId == null && widget.taskId != null) {
      _returnFocus = FocusManager.instance.primaryFocus;
    } else if (oldWidget.taskId != null && widget.taskId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _returnFocus?.context != null) {
          _returnFocus?.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final taskId = widget.taskId;
      final open = taskId != null;
      final sideBySide = constraints.maxWidth >= 960;
      final panelWidth = sideBySide ? 440.0 : constraints.maxWidth;
      final duration = AppMotion.duration(context, AppMotion.panel);
      return BackButtonListener(
        onBackButtonPressed: () async {
          if (!open) return false;
          closeTaskDetails(context);
          return true;
        },
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (open &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              closeTaskDetails(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: AppMotion.curve,
                top: 0,
                bottom: 0,
                left: 0,
                right: open && sideBySide ? panelWidth : 0,
                child: ExcludeFocus(
                  excluding: open && !sideBySide,
                  child: ExcludeSemantics(
                    excluding: open && !sideBySide,
                    child: widget.child,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: AppMotion.curve,
                top: 0,
                bottom: 0,
                width: panelWidth,
                right: open ? 0 : -panelWidth,
                child: open
                    ? Material(
                        color: context.appColors.surface,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: context.appColors.border),
                            ),
                          ),
                          child: FocusScope(
                            autofocus: true,
                            child: TaskDetailScreen(
                              key: ValueKey(taskId),
                              taskId: taskId,
                              isPanel: true,
                              onClose: () => closeTaskDetails(context),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
