import 'package:flutter/material.dart';

import '../../../../app/app_l10n.dart';
import '../../domain/project_colors.dart';

Color projectColorValue(String hex) {
  final normalized = normalizeProjectColor(hex) ?? inboxProjectColorHex;
  return Color(0xFF000000 | int.parse(normalized.substring(1), radix: 16));
}

Future<String?> showProjectColorPicker(
  BuildContext context, {
  required String selectedColor,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.projectColor),
      content: ProjectColorPalettePicker(
        selectedColor: selectedColor,
        onSelected: (color) => Navigator.of(context).pop(color),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
      ],
    ),
  );
}

class ProjectColorPalettePicker extends StatelessWidget {
  const ProjectColorPalettePicker({
    required this.selectedColor,
    required this.onSelected,
    super.key,
  });

  final String selectedColor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeProjectColor(selectedColor);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var index = 0; index < projectColorPalette.length; index++)
          _ColorOption(
            key: Key('project-color-option-$index'),
            color: projectColorPalette[index],
            index: index,
            selected: normalized == projectColorPalette[index],
            onPressed: () => onSelected(projectColorPalette[index]),
          ),
      ],
    );
  }
}

class ProjectColorSwatch extends StatelessWidget {
  const ProjectColorSwatch({
    required this.color,
    this.onPressed,
    this.size = 28,
    super.key,
  });

  final String color;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final swatch = DecoratedBox(
      decoration: BoxDecoration(
        color: projectColorValue(color),
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
      child: SizedBox.square(dimension: size),
    );
    if (onPressed == null) {
      return swatch;
    }
    return Tooltip(
      message: context.l10n.projectColor,
      child: InkResponse(
        onTap: onPressed,
        radius: size,
        child: Padding(padding: const EdgeInsets.all(6), child: swatch),
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.color,
    required this.index,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String color;
  final int index;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.projectColorOption(index + 1),
      child: InkResponse(
        onTap: onPressed,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: projectColorValue(color),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 20, color: scheme.surface)
              : null,
        ),
      ),
    );
  }
}
