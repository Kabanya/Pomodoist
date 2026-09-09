import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

class TaskViewState extends StatelessWidget {
  const TaskViewState({
    required this.icon,
    required this.title,
    this.description,
    this.actions,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: context.appColors.secondaryText),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appColors.secondaryText,
                  ),
                ),
              ],
              if (actions != null) ...[const SizedBox(height: 16), actions!],
            ],
          ),
        ),
      ),
    );
  }
}
