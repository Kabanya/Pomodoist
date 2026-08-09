import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../domain/achievement_models.dart';

const _achievementAnnouncementDuration = Duration(seconds: 4);

class AchievementAnnouncementBridge extends ConsumerWidget {
  const AchievementAnnouncementBridge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<List<AchievementItem>>>(achievementsProvider, (
      previous,
      next,
    ) {
      final items = next.value;
      if (items == null) {
        return;
      }
      unawaited(_queuePending(ref, items));
    });

    return const SizedBox.shrink();
  }

  Future<void> _queuePending(WidgetRef ref, List<AchievementItem> items) async {
    final pending = await ref
        .read(achievementRepositoryProvider)
        .takePendingAnnouncements(items);
    if (pending.isEmpty) {
      return;
    }
    ref
        .read(achievementAnnouncementControllerProvider.notifier)
        .enqueue(pending);
  }
}

class AchievementAnnouncementSlot extends ConsumerStatefulWidget {
  const AchievementAnnouncementSlot({required this.presentation, super.key});

  final AchievementPresentation presentation;

  @override
  ConsumerState<AchievementAnnouncementSlot> createState() =>
      _AchievementAnnouncementSlotState();
}

class _AchievementAnnouncementSlotState
    extends ConsumerState<AchievementAnnouncementSlot> {
  Timer? _timer;
  String? _timerAchievementId;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(achievementAnnouncementControllerProvider).current;
    final visible = item != null && item.presentation == widget.presentation;
    if (!visible) {
      _cancelTimer();
      return const SizedBox.shrink();
    }

    _scheduleDismiss(item);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: widget.presentation == AchievementPresentation.globalBanner
          ? _GlobalAchievementBanner(
              key: ValueKey('achievement-global-${item.id}'),
              item: item,
              onDismiss: _dismissCurrent,
            )
          : _BottomAchievementPlaque(
              key: ValueKey('achievement-bottom-${item.id}'),
              item: item,
              onDismiss: _dismissCurrent,
            ),
    );
  }

  void _scheduleDismiss(AchievementItem item) {
    if (_timerAchievementId == item.id) {
      return;
    }
    _timer?.cancel();
    _timerAchievementId = item.id;
    _timer = Timer(_achievementAnnouncementDuration, () {
      if (!mounted) {
        return;
      }
      final current = ref
          .read(achievementAnnouncementControllerProvider)
          .current;
      if (current?.id == item.id) {
        _dismissCurrent();
      }
    });
  }

  void _dismissCurrent() {
    _cancelTimer();
    ref
        .read(achievementAnnouncementControllerProvider.notifier)
        .dismissCurrent();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _timerAchievementId = null;
  }
}

class _GlobalAchievementBanner extends StatelessWidget {
  const _GlobalAchievementBanner({
    required this.item,
    required this.onDismiss,
    super.key,
  });

  final AchievementItem item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('achievement-global-banner'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: _AchievementAnnouncementSurface(
        item: item,
        onDismiss: onDismiss,
        icon: Icons.emoji_events_outlined,
        dense: false,
      ),
    );
  }
}

class _BottomAchievementPlaque extends StatelessWidget {
  const _BottomAchievementPlaque({
    required this.item,
    required this.onDismiss,
    super.key,
  });

  final AchievementItem item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('achievement-bottom-plaque'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: _AchievementAnnouncementSurface(
        item: item,
        onDismiss: onDismiss,
        icon: Icons.auto_awesome_outlined,
        dense: true,
      ),
    );
  }
}

class _AchievementAnnouncementSurface extends StatelessWidget {
  const _AchievementAnnouncementSurface({
    required this.item,
    required this.onDismiss,
    required this.icon,
    required this.dense,
  });

  final AchievementItem item;
  final VoidCallback onDismiss;
  final IconData icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(dense ? 16 : 10);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: dense ? colors.surface : colors.accentTint,
        border: Border.all(color: colors.border),
        borderRadius: radius,
        boxShadow: dense
            ? [
                BoxShadow(
                  color: colors.primaryText.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, dense ? 10 : 12, 6, dense ? 10 : 12),
          child: Row(
            children: [
              Container(
                width: dense ? 32 : 36,
                height: dense ? 32 : 36,
                decoration: BoxDecoration(
                  color: dense ? colors.accentTint : colors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: colors.accent, size: dense ? 19 : 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.unlocked}: ${item.titleFor(l10n.localeName)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (dense ? textTheme.titleSmall : textTheme.titleMedium)
                              ?.copyWith(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitleFor(l10n.localeName),
                      maxLines: dense ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
