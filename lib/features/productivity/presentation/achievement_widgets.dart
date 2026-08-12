import 'package:flutter/material.dart';

import '../../../app/app_l10n.dart';
import '../../../app/theme/app_theme.dart';
import '../domain/achievement_models.dart';

class AchievementGroupSection extends StatelessWidget {
  const AchievementGroupSection({
    required this.title,
    required this.items,
    required this.sectionKey,
    super.key,
  });

  final String title;
  final List<AchievementItem> items;
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        AchievementGrid(items: items),
      ],
    );
  }
}

class AchievementGrid extends StatelessWidget {
  const AchievementGrid({required this.items, super.key});

  final List<AchievementItem> items;

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 560 ? 1 : (width < 900 ? 2 : 3);
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              AchievementTile(item: item, width: cardWidth),
          ],
        );
      },
    );
  }
}

class AchievementTile extends StatelessWidget {
  const AchievementTile({required this.item, required this.width, super.key});

  final AchievementItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final unlocked = item.unlocked;
    final accent = unlocked ? colors.accent : colors.mutedText;
    final surface = unlocked ? colors.surface : colors.surfaceTint;
    final progressLabel = '${item.progress}/${item.target}';

    return Semantics(
      label:
          '${item.titleFor(l10n.localeName)}, '
          '${item.subtitleFor(l10n.localeName)}, '
          '${unlocked ? l10n.unlocked : l10n.locked}, '
          '${l10n.progressLabel}: $progressLabel',
      readOnly: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: 154,
          child: Card(
            color: surface,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: unlocked ? colors.accentTint : colors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          achievementGroupIcon(item.group),
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.titleFor(l10n.localeName),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        unlocked ? l10n.unlocked : l10n.locked,
                        style: textTheme.labelSmall?.copyWith(color: accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Text(
                      item.subtitleFor(l10n.localeName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        l10n.progressLabel,
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.mutedText,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        progressLabel,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: item.progressRatio,
                      color: accent,
                      backgroundColor: colors.border,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<AchievementItem> achievementsInGroup(
  List<AchievementItem> items,
  AchievementGroup group,
) {
  return [
    for (final item in items)
      if (item.group == group) item,
  ];
}

IconData achievementGroupIcon(AchievementGroup group) {
  return switch (group) {
    AchievementGroup.focus => Icons.timer_outlined,
    AchievementGroup.task => Icons.check_circle_outline,
    AchievementGroup.combo => Icons.auto_awesome_outlined,
  };
}
