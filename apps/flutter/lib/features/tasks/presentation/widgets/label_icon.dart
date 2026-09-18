import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../../app/config/app_l10n.dart';
import '../../../../app/config/providers.dart';
import '../../domain/task_models.dart';

IconData labelIconData(String? name) => switch (name) {
  'bookmark' => LucideIcons.bookmark,
  'flag' => LucideIcons.flag,
  'bolt' => LucideIcons.bolt,
  'lightbulb' => LucideIcons.lightbulb,
  'clock' => LucideIcons.clock,
  'bell' => LucideIcons.bell,
  'pin' => LucideIcons.pin,
  'phone' => LucideIcons.phone,
  'mail' => LucideIcons.mail,
  'link' => LucideIcons.link,
  'wrench' => LucideIcons.wrench,
  _ => LucideIcons.tag,
};

Future<String?> showLabelIconPicker(
  BuildContext context, {
  String? selectedIcon,
}) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.labelIcon),
    content: SizedBox(
      width: 280,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final icon in LabelIcon.values)
              Semantics(
                selected: icon.name == (selectedIcon ?? 'tag'),
                child: IconButton.outlined(
                  tooltip: context.l10n.labelIconOption(icon.name),
                  isSelected: icon.name == (selectedIcon ?? 'tag'),
                  onPressed: () => Navigator.of(context).pop(icon.name),
                  icon: Icon(labelIconData(icon.name)),
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

Future<void> editLabelIcon(
  BuildContext context,
  WidgetRef ref,
  LabelItem label,
) async {
  final icon = await showLabelIconPicker(context, selectedIcon: label.icon);
  if (icon == null || icon == label.icon || !context.mounted) return;
  try {
    await ref.read(labelRepositoryProvider).updateLabelIcon(label.id, icon);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.labelUpdateFailed)));
    }
  }
}
