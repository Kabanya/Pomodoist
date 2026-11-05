import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/onboarding/view_models/learning_tour_view_model.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart';

enum LearningTourAnchorId {
  addDesktop,
  addMobile,
  focusDesktop,
  focusMobile,
  focusStart,
  projectsDesktop,
  projectsMobile,
  projectsAdd,
}

final _links = {for (final id in LearningTourAnchorId.values) id: LayerLink()};
final _keys = {
  for (final id in LearningTourAnchorId.values)
    id: GlobalKey(debugLabel: 'learning-tour-${id.name}'),
};

class LearningTourAnchor extends ConsumerWidget {
  const LearningTourAnchor({required this.id, required this.child, super.key});

  final LearningTourAnchorId id;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(learningTourProvider).value;
    final highlighted = switch (step) {
      LearningTourStep.addTask =>
        id == LearningTourAnchorId.addDesktop ||
            id == LearningTourAnchorId.addMobile,
      LearningTourStep.focusNavigation =>
        id == LearningTourAnchorId.focusDesktop ||
            id == LearningTourAnchorId.focusMobile,
      LearningTourStep.focusReady => id == LearningTourAnchorId.focusStart,
      LearningTourStep.projectsNavigation =>
        id == LearningTourAnchorId.projectsDesktop ||
            id == LearningTourAnchorId.projectsMobile,
      LearningTourStep.projectsReady => id == LearningTourAnchorId.projectsAdd,
      _ => false,
    };
    return CompositedTransformTarget(
      key: _keys[id],
      link: _links[id]!,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: highlighted
              ? Border.all(color: context.appColors.accent, width: 2)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class LearningTourOverlay extends ConsumerStatefulWidget {
  const LearningTourOverlay({super.key});

  @override
  ConsumerState<LearningTourOverlay> createState() =>
      _LearningTourOverlayState();
}

class _LearningTourOverlayState extends ConsumerState<LearningTourOverlay> {
  bool _saving = false;
  bool _saveFailed = false;

  Future<void> _choose(bool start) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final tour = ref.read(learningTourProvider.notifier);
      if (start) {
        await tour.start();
        if (mounted) GoRouter.maybeOf(context)?.go('/today');
      } else {
        await tour.later();
      }
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAddTask() async {
    await showLearningTourQuickAdd(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(learningTourProvider).value;
    if (step == null || step == LearningTourStep.inactive) {
      return const SizedBox.shrink();
    }
    if (step == LearningTourStep.invitation) {
      return Positioned.fill(
        child: BlockSemantics(
          child: Material(
            color: context.appColors.primaryText.withValues(alpha: 0.35),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Material(
                      color: context.appColors.surface,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.l10n.learningTourInvitationTitle,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(context.l10n.learningTourInvitationBody),
                            if (_saveFailed) ...[
                              const SizedBox(height: 12),
                              Text(
                                context.l10n.settingsSaveError,
                                style: TextStyle(
                                  color: context.appColors.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ShadButton.ghost(
                                  height: 48,
                                  onPressed: _saving
                                      ? null
                                      : () => _choose(false),
                                  child: Text(context.l10n.learningTourLater),
                                ),
                                ShadButton(
                                  height: 48,
                                  onPressed: _saving
                                      ? null
                                      : () => _choose(true),
                                  child: Text(context.l10n.learningTourStart),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (step == LearningTourStep.addTaskOpen) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final anchor = _anchorFor(step, size.width >= 820);
          final rect = _visibleRect(anchor, size);
          final card = _TourCard(
            step: step,
            hasAnchor: rect != null,
            onSkip: () => ref.read(learningTourProvider.notifier).skipStep(),
            onClose: () => ref.read(learningTourProvider.notifier).close(),
            onPrimary: () {
              final tour = ref.read(learningTourProvider.notifier);
              switch (step) {
                case LearningTourStep.addTask:
                  _openAddTask();
                case LearningTourStep.focusNavigation:
                  GoRouter.maybeOf(context)?.go('/focus');
                  tour.focusOpened();
                case LearningTourStep.focusReady:
                  tour.next();
                case LearningTourStep.projectsNavigation:
                  GoRouter.maybeOf(context)?.go('/projects');
                  tour.projectsOpened();
                case LearningTourStep.projectsReady:
                  tour.finish();
                default:
                  break;
              }
            },
          );
          if (rect == null) {
            return SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(padding: const EdgeInsets.all(16), child: card),
              ),
            );
          }
          final side = size.width >= 700 && rect.right < size.width * .45;
          final above = !side && rect.center.dy > size.height * .55;
          final horizontal = rect.center.dx > size.width * .65
              ? Alignment.centerRight
              : rect.center.dx < size.width * .35
              ? Alignment.centerLeft
              : Alignment.center;
          return Align(
            alignment: Alignment.topLeft,
            child: CompositedTransformFollower(
              link: _links[anchor]!,
              showWhenUnlinked: false,
              targetAnchor: side
                  ? Alignment.centerRight
                  : above
                  ? Alignment(horizontal.x, -1)
                  : Alignment(horizontal.x, 1),
              followerAnchor: side
                  ? Alignment.centerLeft
                  : above
                  ? Alignment(horizontal.x, 1)
                  : Alignment(horizontal.x, -1),
              offset: side ? const Offset(12, 0) : Offset(0, above ? -12 : 12),
              child: SizedBox(
                width: size.width.clamp(0, 300).toDouble() - 16,
                child: card,
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> showLearningTourQuickAdd(
  BuildContext context,
  WidgetRef ref, {
  DateTime? defaultDate,
}) async {
  ref.read(learningTourProvider.notifier).quickAddOpened();
  try {
    await showQuickAddDialog(context, defaultDate: defaultDate);
  } finally {
    if (context.mounted) {
      ref.read(learningTourProvider.notifier).quickAddClosed();
    }
  }
}

LearningTourAnchorId _anchorFor(LearningTourStep step, bool wide) =>
    switch (step) {
      LearningTourStep.addTask =>
        wide ? LearningTourAnchorId.addDesktop : LearningTourAnchorId.addMobile,
      LearningTourStep.focusNavigation =>
        wide
            ? LearningTourAnchorId.focusDesktop
            : LearningTourAnchorId.focusMobile,
      LearningTourStep.focusReady => LearningTourAnchorId.focusStart,
      LearningTourStep.projectsNavigation =>
        wide
            ? LearningTourAnchorId.projectsDesktop
            : LearningTourAnchorId.projectsMobile,
      LearningTourStep.projectsReady => LearningTourAnchorId.projectsAdd,
      _ => LearningTourAnchorId.addDesktop,
    };

Rect? _visibleRect(LearningTourAnchorId id, Size viewport) {
  final box = _keys[id]?.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final visible = rect.intersect(Offset.zero & viewport);
  return visible.width >= 24 && visible.height >= 24 ? rect : null;
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.hasAnchor,
    required this.onSkip,
    required this.onClose,
    required this.onPrimary,
  });

  final LearningTourStep step;
  final bool hasAnchor;
  final VoidCallback onSkip;
  final VoidCallback onClose;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chapter = switch (step) {
      LearningTourStep.addTask => 1,
      LearningTourStep.focusNavigation || LearningTourStep.focusReady => 2,
      _ => 3,
    };
    final title = switch (chapter) {
      1 => l10n.addTask,
      2 => l10n.navFocus,
      _ => l10n.navProjects,
    };
    final description = switch (step) {
      LearningTourStep.addTask => l10n.learningTourAddTask,
      LearningTourStep.focusNavigation => l10n.learningTourFocusNavigation,
      LearningTourStep.focusReady => l10n.learningTourFocusReady,
      LearningTourStep.projectsNavigation =>
        l10n.learningTourProjectsNavigation,
      _ => l10n.learningTourProjectsReady,
    };
    final primaryLabel = switch (step) {
      LearningTourStep.addTask => l10n.learningTourOpenAddTask,
      LearningTourStep.focusNavigation => l10n.learningTourOpenFocus,
      LearningTourStep.projectsNavigation => l10n.learningTourOpenProjects,
      LearningTourStep.projectsReady => l10n.onboardingFinish,
      _ => l10n.onboardingContinue,
    };
    final showPrimary =
        !hasAnchor ||
        step == LearningTourStep.focusReady ||
        step == LearningTourStep.projectsReady;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TweenAnimationBuilder<double>(
        key: ValueKey(step),
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.duration(context, AppMotion.popup),
        curve: AppMotion.curve,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 300,
              maxHeight: MediaQuery.sizeOf(context).height * .55,
            ),
            child: Material(
              key: const Key('learning-tour-card'),
              color: context.appColors.surface,
              elevation: 8,
              shadowColor: context.appColors.primaryText.withValues(alpha: .12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: context.appColors.border),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$chapter / 3',
                          style: TextStyle(color: context.appColors.accent),
                        ),
                        const Spacer(),
                        ShadButton.ghost(
                          height: 48,
                          onPressed: onClose,
                          child: Text(l10n.learningTourClose),
                        ),
                      ],
                    ),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(description),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ShadButton.ghost(
                          height: 48,
                          onPressed: onSkip,
                          child: Text(l10n.learningTourSkipStep),
                        ),
                        if (showPrimary)
                          ShadButton(
                            height: 48,
                            onPressed: onPrimary,
                            child: Text(primaryLabel),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
