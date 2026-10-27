import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pomodoist/ui/tasks/widgets/task_detail_screen.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

/// Keeps the task route mounted while the shared panel opens and resizes.
class TaskDetailsHost extends StatefulWidget {
  const TaskDetailsHost({required this.taskId, required this.child, super.key});

  final String? taskId;
  final Widget child;

  @override
  State<TaskDetailsHost> createState() => _TaskDetailsHostState();
}

class _TaskDetailsHostState extends State<TaskDetailsHost> {
  bool _expanded = false;
  @override
  void didUpdateWidget(covariant TaskDetailsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) _expanded = false;
  }

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) => DetailsPanelHost(
    expanded: _expanded,
    onCollapse: _toggleExpanded,
    onClose: () => closeTaskDetails(context),
    panel: widget.taskId == null
        ? null
        : TaskDetailScreen(
            key: ValueKey(widget.taskId),
            taskId: widget.taskId!,
            isPanel: true,
            expanded: _expanded,
            onToggleExpanded: _toggleExpanded,
            onClose: () => closeTaskDetails(context),
          ),
    child: widget.child,
  );
}

/// Original background width before a contextual panel reserves its space.
class DetailsPanelViewport extends InheritedWidget {
  const DetailsPanelViewport({
    required this.width,
    required super.child,
    super.key,
  });

  final double width;

  bool get sideBySide => width >= 960;

  double backgroundLayoutWidth(double contentWidth) =>
      sideBySide ? width : contentWidth;

  static DetailsPanelViewport? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailsPanelViewport>();

  @override
  bool updateShouldNotify(DetailsPanelViewport oldWidget) =>
      width != oldWidget.width;
}

/// Full-height contextual panels share layout, motion and focus restoration.
class DetailsPanelHost extends StatefulWidget {
  const DetailsPanelHost({
    required this.panel,
    required this.onClose,
    required this.child,
    this.expanded = false,
    this.onCollapse,
    super.key,
  });

  final bool expanded;
  final VoidCallback? onCollapse;
  final Widget? panel;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<DetailsPanelHost> createState() => _DetailsPanelHostState();
}

class _DetailsPanelHostState extends State<DetailsPanelHost> {
  FocusNode? _returnFocus;

  @override
  void didUpdateWidget(covariant DetailsPanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel == null && widget.panel != null) {
      _returnFocus = FocusManager.instance.primaryFocus;
    } else if (oldWidget.panel != null && widget.panel == null) {
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
      final open = widget.panel != null;
      final viewport = DetailsPanelViewport(
        width: constraints.maxWidth,
        child: widget.child,
      );
      final sideBySide = viewport.sideBySide;
      final expanded = widget.expanded;
      final margin = expanded && constraints.maxWidth >= 820 ? 24.0 : 0.0;
      final panelWidth = expanded
          ? (constraints.maxWidth - margin * 2).clamp(0.0, 1280.0)
          : sideBySide
          ? 440.0
          : constraints.maxWidth;
      final modal = expanded || !sideBySide;
      final duration = AppMotion.duration(context, AppMotion.panel);
      return BackButtonListener(
        onBackButtonPressed: () async {
          if (!open) return false;
          widget.onClose();
          return true;
        },
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (open &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
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
                right: open && sideBySide && !expanded ? panelWidth : 0,
                child: ExcludeFocus(
                  excluding: open && modal,
                  child: ExcludeSemantics(
                    excluding: open && modal,
                    child: viewport,
                  ),
                ),
              ),
              if (open && expanded)
                ModalBarrier(
                  color: Colors.black54,
                  dismissible: true,
                  onDismiss: widget.onCollapse,
                ),
              AnimatedPositioned(
                duration: duration,
                curve: AppMotion.curve,
                top: margin,
                bottom: margin,
                width: panelWidth,
                right: open
                    ? (expanded ? (constraints.maxWidth - panelWidth) / 2 : 0)
                    : -panelWidth,
                child: open
                    ? Material(
                        color: context.appColors.surface,
                        borderRadius: expanded
                            ? BorderRadius.circular(12)
                            : null,
                        clipBehavior: Clip.antiAlias,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: expanded
                                ? Border.all(color: context.appColors.border)
                                : Border(
                                    left: BorderSide(
                                      color: context.appColors.border,
                                    ),
                                  ),
                          ),
                          child: FocusScope(
                            autofocus: true,
                            child: ShortcutHintsScope(
                              modal: true,
                              identity: widget.panel!.key,
                              hints: [
                                ShortcutHint(context.l10n.commonClose, 'Esc'),
                              ],
                              child: Column(
                                children: [
                                  const ShortcutHintsBar(),
                                  Expanded(child: widget.panel!),
                                ],
                              ),
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
