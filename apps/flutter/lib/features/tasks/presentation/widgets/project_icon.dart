import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../../app/app_l10n.dart';
import '../../domain/project_colors.dart';
import '../../domain/task_models.dart';
import 'project_color_picker.dart';

IconData projectIconData(String? name) => switch (name) {
  'folder' => LucideIcons.folder,
  'briefcase' => LucideIcons.briefcase,
  'house' => LucideIcons.house,
  'bookOpen' => LucideIcons.bookOpen,
  'code' => LucideIcons.code,
  'heart' => LucideIcons.heart,
  'star' => LucideIcons.star,
  'target' => LucideIcons.target,
  'plane' => LucideIcons.plane,
  'music' => LucideIcons.music,
  'coffee' => LucideIcons.coffee,
  _ => LucideIcons.hash,
};

class ProjectIconView extends StatelessWidget {
  const ProjectIconView({required this.project, this.size = 20, super.key});

  final ProjectItem project;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
    projectIconData(project.icon),
    color: projectColorValue(effectiveProjectColor(project)),
    size: size,
  );
}

Future<String?> showProjectIconPicker(
  BuildContext context, {
  required ProjectItem project,
}) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.projectIcon),
    content: SizedBox(
      width: 280,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final icon in ProjectIcon.values)
              Semantics(
                selected: icon.name == (project.icon ?? 'hash'),
                child: IconButton.outlined(
                  tooltip: context.l10n.projectIconOption(icon.index + 1),
                  isSelected: icon.name == (project.icon ?? 'hash'),
                  onPressed: () => Navigator.of(context).pop(icon.name),
                  icon: Icon(projectIconData(icon.name)),
                  color: projectColorValue(effectiveProjectColor(project)),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      ShadButton.ghost(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.commonCancel),
      ),
    ],
  ),
);
