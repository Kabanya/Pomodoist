import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../domain/achievement_models.dart';
import 'achievement_widgets.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider);
    final l10n = context.l10n;

    return SafeArea(
      child: ListView(
        key: const Key('achievements-catalog'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: l10n.backToReports,
                        onPressed: () => _goBack(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.achievementsTitle,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  achievements.when(
                    data: (items) => _AchievementCatalogContent(items: items),
                    loading: () => const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stackTrace) => Text(
                      l10n.failedToLoadAchievements(error),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _goBack(BuildContext context) async {
    final popped = await Navigator.of(context).maybePop();
    if (!popped && context.mounted) {
      context.go('/reports');
    }
  }
}

class _AchievementCatalogContent extends StatelessWidget {
  const _AchievementCatalogContent({required this.items});

  final List<AchievementItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text(context.l10n.noAchievementsYet)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AchievementGroupSection(
          title: context.l10n.focusAchievements,
          items: achievementsInGroup(items, AchievementGroup.focus),
          sectionKey: const Key('reports-focus-achievements'),
        ),
        const SizedBox(height: 24),
        AchievementGroupSection(
          title: context.l10n.taskAchievements,
          items: achievementsInGroup(items, AchievementGroup.task),
          sectionKey: const Key('reports-task-achievements'),
        ),
        const SizedBox(height: 24),
        AchievementGroupSection(
          title: context.l10n.comboAchievements,
          items: achievementsInGroup(items, AchievementGroup.combo),
          sectionKey: const Key('reports-combo-achievements'),
        ),
      ],
    );
  }
}
