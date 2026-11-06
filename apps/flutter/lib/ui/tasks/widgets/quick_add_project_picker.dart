import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_details_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/project_icon.dart';
import 'package:pomodoist/ui/tasks/widgets/project_localizations.dart';

class QuickAddProjectPicker extends StatefulWidget {
  const QuickAddProjectPicker({
    super.key,
    required this.projects,
    required this.selectedProjectId,
    required this.projectToken,
    required this.onSelected,
    required this.onClose,
    this.touchTargets = false,
  });

  final List<ProjectItem> projects;
  final String? selectedProjectId;
  final String? Function(String name) projectToken;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;
  final bool touchTargets;

  @override
  State<QuickAddProjectPicker> createState() => _QuickAddProjectPickerState();
}

class _QuickAddProjectPickerState extends State<QuickAddProjectPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _choose(ProjectItem project) {
    if (!_search.value.composing.isCollapsed) return;
    final token = widget.projectToken(project.name);
    if (token != null) widget.onSelected(token);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_search.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      node.enclosingScope?.nextFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      node.enclosingScope?.previousFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final projects = quickAddProjectOptions(
      widget.projects,
      _search.text,
      displayName: (project) => project.displayName(l10n),
    );
    final projectColor = colors.quickAddTokenColor(QuickAddTokenKind.project);
    final rowHeight = math.max(
      widget.touchTargets ? 48.0 : 44.0,
      MediaQuery.textScalerOf(context).scale(16) + 24,
    );
    return FocusScope(
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Focus(
          onKeyEvent: _onKey,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ShadInput(
                    controller: _search,
                    autofocus: !widget.touchTargets,
                    leading: Icon(
                      LucideIcons.search,
                      size: 20,
                      color: colors.secondaryText,
                    ),
                    placeholder: Text(l10n.searchProjects),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      for (final project in projects) {
                        if (widget.projectToken(project.name) != null) {
                          _choose(project);
                          break;
                        }
                      }
                    },
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (projects.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              l10n.noProjects,
                              style: TextStyle(color: colors.secondaryText),
                            ),
                          ),
                        for (final project in projects)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Semantics(
                              selected: project.id == widget.selectedProjectId,
                              child: Tooltip(
                                message:
                                    widget.projectToken(project.name) == null
                                    ? l10n.quickAddProjectNameUnsupported
                                    : project.displayName(l10n),
                                child: ShadButton.ghost(
                                  height: rowHeight,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  enabled:
                                      widget.projectToken(project.name) != null,
                                  foregroundColor: colors.primaryText,
                                  hoverForegroundColor: colors.primaryText,
                                  pressedForegroundColor: colors.primaryText,
                                  backgroundColor:
                                      project.id == widget.selectedProjectId
                                      ? colors.quickAddBackground(projectColor)
                                      : colors.surface,
                                  hoverBackgroundColor: colors.surfaceHover,
                                  pressedBackgroundColor: colors.surfaceHover,
                                  decoration: ShadDecoration(
                                    border: ShadBorder.all(
                                      color:
                                          project.id == widget.selectedProjectId
                                          ? colors.quickAddBorder(projectColor)
                                          : Colors.transparent,
                                      radius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => _choose(project),
                                  leading: project.id == inboxProjectId
                                      ? Icon(
                                          LucideIcons.inbox,
                                          size: 20,
                                          color: projectColor,
                                        )
                                      : ProjectIconView(project: project),
                                  child: Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            project.displayName(l10n),
                                            textAlign: TextAlign.start,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (project.id ==
                                            widget.selectedProjectId)
                                          Icon(
                                            LucideIcons.check,
                                            size: 18,
                                            color: projectColor,
                                          ),
                                      ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
