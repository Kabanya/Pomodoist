import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/app_l10n.dart';

/// Shared geometry for Settings and its existing nested routes.
class SettingsSurface extends StatelessWidget {
  const SettingsSurface({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    required this.control,
    this.subtitle,
    this.onTap,
    this.controlWidth = 280,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget control;
  final double controlWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.appColors.secondaryText,
            ),
          ),
        ],
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 600 && controlWidth > 48;
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Flex(
                  direction: stacked ? Axis.vertical : Axis.horizontal,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: stacked
                          ? constraints.maxWidth
                          : (constraints.maxWidth - controlWidth - 24).clamp(
                              0,
                              double.infinity,
                            ),
                      child: label,
                    ),
                    SizedBox(width: stacked ? 0 : 24, height: stacked ? 12 : 0),
                    SizedBox(
                      width: stacked ? constraints.maxWidth : controlWidth,
                      child: control,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          Divider(height: 1, thickness: 1, color: context.appColors.border),
        children[i],
      ],
    ],
  );
}

/// Report persistence failures without rolling back the controller's session value.
Future<void> saveSetting(BuildContext context, Future<void> saving) async {
  try {
    await saving;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsSaveError)));
    }
  }
}
