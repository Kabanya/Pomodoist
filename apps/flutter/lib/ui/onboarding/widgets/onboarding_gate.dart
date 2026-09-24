import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/onboarding/widgets/onboarding_illustration.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/billing/view_models/billing_view_model.dart';
import 'package:pomodoist/ui/billing/widgets/billing_paywall.dart';
import 'package:pomodoist/ui/onboarding/view_models/onboarding_view_model.dart';
export 'package:pomodoist/ui/onboarding/view_models/onboarding_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/pomodoist_account_actions.dart';

class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(billingAccessProvider);
    final state = ref.watch(onboardingViewModelProvider);
    return Stack(
      children: [
        ExcludeFocus(
          excluding: !state.loading && !state.completed,
          child: child,
        ),
        if (!state.loading && !state.completed) const _OnboardingOverlay(),
        if (!state.loading && state.completed) const _LaunchOfferMiniWindow(),
      ],
    );
  }
}

class _OnboardingOverlay extends ConsumerStatefulWidget {
  const _OnboardingOverlay();

  @override
  ConsumerState<_OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<_OnboardingOverlay> {
  final _scroll = ScrollController();
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingViewModelProvider);
    final controller = ref.read(onboardingViewModelProvider.notifier);
    final colors = context.appColors;
    final l10n = context.l10n;
    ref.listen(onboardingViewModelProvider.select((value) => value.step), (
      _,
      _,
    ) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    return Positioned.fill(
      child: BlockSemantics(
        child: Material(
          color: colors.primaryText.withValues(alpha: 0.35),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fullScreen = constraints.maxWidth < 600;
                return Padding(
                  padding: EdgeInsets.all(fullScreen ? 0 : 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: fullScreen ? constraints.maxWidth : 540,
                        maxHeight: fullScreen ? constraints.maxHeight : 760,
                      ),
                      child: Material(
                        color: colors.surface,
                        elevation: fullScreen ? 0 : 12,
                        shadowColor: colors.primaryText.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            fullScreen ? 0 : 12,
                          ),
                          side: fullScreen
                              ? BorderSide.none
                              : BorderSide(color: colors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FocusScope(
                          autofocus: true,
                          child: Column(
                            mainAxisSize: fullScreen
                                ? MainAxisSize.max
                                : MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  24,
                                  12,
                                  12,
                                  0,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: colors.accentFill,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        LucideIcons.check,
                                        color: colors.onAccent,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'pomodoist',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      '${state.step.index + 1} / 4',
                                      style: AppTheme.monoTextStyle.copyWith(
                                        fontSize: 11,
                                        color: colors.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      key: const Key('onboarding-close-button'),
                                      tooltip: l10n.commonClose,
                                      onPressed: _saving
                                          ? null
                                          : () => unawaited(
                                              _save(controller.complete),
                                            ),
                                      icon: const Icon(LucideIcons.x, size: 20),
                                    ),
                                  ],
                                ),
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  controller: _scroll,
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    8,
                                    24,
                                    24,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: AppMotion.duration(
                                      context,
                                      AppMotion.state,
                                    ),
                                    switchInCurve: AppMotion.curve,
                                    switchOutCurve: AppMotion.curve,
                                    layoutBuilder: (current, previous) => Stack(
                                      alignment: Alignment.topCenter,
                                      children: [
                                        for (final child in previous)
                                          ExcludeFocus(
                                            child: ExcludeSemantics(
                                              child: IgnorePointer(
                                                child: child,
                                              ),
                                            ),
                                          ),
                                        ?current,
                                      ],
                                    ),
                                    child: Column(
                                      key: ValueKey(
                                        'onboarding-step-${state.step.name}',
                                      ),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        GestureDetector(
                                          onHorizontalDragEnd: (details) {
                                            if (_saving) return;
                                            controller.swipe(
                                              details.primaryVelocity ?? 0,
                                              rightToLeft:
                                                  Directionality.of(context) ==
                                                  TextDirection.rtl,
                                            );
                                          },
                                          child: OnboardingIllustration(
                                            step: state.step,
                                            timerStyle: state.timerStyle,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        if (state.step !=
                                            OnboardingStep.paywall) ...[
                                          _StepHeader(step: state.step),
                                          const SizedBox(height: 24),
                                        ],
                                        switch (state.step) {
                                          OnboardingStep.language =>
                                            _LanguageStep(
                                              enabled: !_saving,
                                              onSelected: (value) => unawaited(
                                                _save(
                                                  () => controller.setLanguage(
                                                    value,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          OnboardingStep.timer => _TimerStep(
                                            enabled: !_saving,
                                            onSelected: (value) => unawaited(
                                              _save(
                                                () => controller.setTimerStyle(
                                                  value,
                                                ),
                                              ),
                                            ),
                                          ),
                                          OnboardingStep.paywall =>
                                            const LaunchOfferPaywall(
                                              compact: true,
                                            ),
                                          OnboardingStep.account =>
                                            const PomodoistAccountAccessPanel(
                                              compact: true,
                                            ),
                                        },
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (_saveFailed)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 8,
                                  ),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      l10n.settingsSaveError,
                                      style: TextStyle(color: colors.error),
                                    ),
                                  ),
                                ),
                              _OnboardingFooter(
                                step: state.step,
                                enabled: !_saving,
                                onBack: controller.back,
                                onSelect: controller.selectStep,
                                onNext: () {
                                  if (state.step == OnboardingStep.account) {
                                    unawaited(_save(controller.complete));
                                  } else {
                                    controller.next();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _stepTitle(BuildContext context, OnboardingStep step) => switch (step) {
  OnboardingStep.language => context.l10n.onboardingLanguageTitle,
  OnboardingStep.timer => context.l10n.onboardingTimerTitle,
  OnboardingStep.paywall => context.l10n.billingTitle,
  OnboardingStep.account => context.l10n.onboardingAccountTitle,
};

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});
  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            _stepTitle(context, step),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          switch (step) {
            OnboardingStep.language => l10n.onboardingLanguageSubtitle,
            OnboardingStep.timer => l10n.onboardingTimerSubtitle,
            OnboardingStep.paywall => l10n.onboardingPaywallSubtitle,
            OnboardingStep.account => l10n.onboardingAccountSubtitle,
          },
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.appColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter({
    required this.step,
    required this.enabled,
    required this.onBack,
    required this.onNext,
    required this.onSelect,
  });
  final OnboardingStep step;
  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final ValueChanged<OnboardingStep> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final progress = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in OnboardingStep.values)
          Semantics(
            selected: item == step,
            child: IconButton(
              tooltip: _stepTitle(context, item),
              onPressed: enabled ? () => onSelect(item) : null,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              icon: Container(
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  color: item == step ? colors.accent : colors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final back = ShadButton.ghost(
            key: const Key('onboarding-back-button'),
            height: 0,
            expands: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            enabled: enabled && step != OnboardingStep.language,
            onPressed: onBack,
            child: Text(l10n.commonBack),
          );
          final next = ShadButton(
            key: const Key('onboarding-next-button'),
            height: 0,
            expands: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            enabled: enabled,
            onPressed: onNext,
            child: Text(switch (step) {
              OnboardingStep.account => l10n.onboardingFinish,
              OnboardingStep.paywall => l10n.onboardingMaybeLater,
              _ => l10n.onboardingContinue,
            }, textAlign: TextAlign.center),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stacked) progress,
              Row(
                children: [
                  Flexible(child: back),
                  if (!stacked) progress else const SizedBox(width: 12),
                  Flexible(child: next),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

ButtonStyle _choiceStyle(BuildContext context, bool selected) =>
    OutlinedButton.styleFrom(
      foregroundColor: context.appColors.primaryText,
      backgroundColor: selected
          ? context.appColors.accentTint
          : context.appColors.surface,
      side: BorderSide(
        color: selected ? context.appColors.accent : context.appColors.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

class _LanguageStep extends ConsumerWidget {
  const _LanguageStep({required this.enabled, required this.onSelected});
  final bool enabled;
  final ValueChanged<AppLanguage> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingViewModelProvider).language;
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        return Wrap(
          key: const Key('onboarding-language-select'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final language in AppLanguage.values)
              SizedBox(
                width: singleColumn || language == AppLanguage.system
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 8) / 2,
                child: Semantics(
                  selected: language == selected,
                  child: OutlinedButton(
                    key: ValueKey('onboarding-language-${language.name}'),
                    style: _choiceStyle(context, language == selected),
                    onPressed: enabled ? () => onSelected(language) : null,
                    child: Row(
                      children: [
                        if (language == AppLanguage.system) ...[
                          const Icon(LucideIcons.languages, size: 16),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            language == AppLanguage.system
                                ? context.l10n.settingsLanguageSystem
                                : language.nativeName,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (language == selected) ...[
                          const SizedBox(width: 4),
                          Icon(
                            LucideIcons.check,
                            size: 16,
                            color: context.appColors.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TimerStep extends ConsumerWidget {
  const _TimerStep({required this.enabled, required this.onSelected});
  final bool enabled;
  final ValueChanged<FocusTimerVisualStyle> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingViewModelProvider).timerStyle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        return Wrap(
          key: const Key('onboarding-timer-visual-style-select'),
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final style in FocusTimerVisualStyle.values)
              SizedBox(
                width: singleColumn
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2,
                child: Semantics(
                  selected: style == selected,
                  child: OutlinedButton(
                    style: _choiceStyle(context, style == selected),
                    onPressed: enabled ? () => onSelected(style) : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: OnboardingTimerPreview(style: style),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                style == FocusTimerVisualStyle.bar
                                    ? context.l10n.settingsTimerVisualBar
                                    : context.l10n.settingsTimerVisualCircle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              style == selected
                                  ? LucideIcons.circleCheck
                                  : LucideIcons.circle,
                              size: 16,
                              color: style == selected
                                  ? context.appColors.accent
                                  : context.appColors.secondaryText,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class LaunchOfferPaywall extends ConsumerStatefulWidget {
  const LaunchOfferPaywall({
    super.key,
    this.compact = false,
    this.onClose,
    this.showPlansWhenActive = false,
  });

  final bool compact;
  final bool showPlansWhenActive;
  final VoidCallback? onClose;

  @override
  ConsumerState<LaunchOfferPaywall> createState() => _LaunchOfferPaywallState();
}

class _LaunchOfferPaywallState extends ConsumerState<LaunchOfferPaywall> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingViewModelProvider);
    final billing = ref.watch(billingViewModelProvider);
    final now = ref.read(onboardingViewModelProvider.notifier).now();
    final serverOwned =
        ref.watch(billingChannelProvider) == BillingChannel.stripe &&
        ref.watch(billingSignedInProvider);
    final remaining = serverOwned
        ? stripeLaunchOfferRemaining(
            now: now,
            endsAt: billing.stripeLaunchOfferEndsAt,
          )
        : launchOfferRemaining(
            now: now,
            startedAt: onboarding.launchOfferStartedAt,
          );
    final offerActive =
        remaining > Duration.zero &&
        (!serverOwned || billing.stripeLaunchOfferEligible);
    return BillingPaywall(
      compact: widget.compact,
      showPlansWhenActive: widget.showPlansWhenActive,
      onClose: widget.onClose,
      launchOfferMode: offerActive,
      launchOfferTimerLabel: offerActive
          ? formatLaunchOfferRemaining(remaining)
          : null,
    );
  }
}

class _LaunchOfferMiniWindow extends ConsumerStatefulWidget {
  const _LaunchOfferMiniWindow();

  @override
  ConsumerState<_LaunchOfferMiniWindow> createState() =>
      _LaunchOfferMiniWindowState();
}

class _LaunchOfferMiniWindowState
    extends ConsumerState<_LaunchOfferMiniWindow> {
  Timer? _timer;
  int? _dismissedCycle;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingViewModelProvider);
    final billing = ref.watch(billingViewModelProvider);
    final access = ref.watch(billingAccessProvider).value;
    final now = ref.read(onboardingViewModelProvider.notifier).now();
    final serverOwned =
        ref.watch(billingChannelProvider) == BillingChannel.stripe &&
        ref.watch(billingSignedInProvider);
    final remaining = serverOwned
        ? stripeLaunchOfferRemaining(
            now: now,
            endsAt: billing.stripeLaunchOfferEndsAt,
          )
        : launchOfferRemaining(
            now: now,
            startedAt: onboarding.launchOfferStartedAt,
          );
    final cycle = serverOwned
        ? billing.stripeLaunchOfferEndsAt?.millisecondsSinceEpoch
        : launchOfferCycle(
            now: now,
            startedAt: onboarding.launchOfferStartedAt,
          );
    if (_dismissedCycle == cycle ||
        remaining == Duration.zero ||
        (serverOwned && !billing.stripeLaunchOfferEligible) ||
        (access?.hasActiveEntitlement ?? false)) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final colors = context.appColors;
    return PositionedDirectional(
      top: 12,
      end: 12,
      child: SafeArea(
        child: Card(
          key: const Key('launch-offer-mini-window'),
          elevation: 2,
          shadowColor: colors.primaryText.withValues(alpha: 0.08),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showPaywall(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.timer, color: colors.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.launchOfferEndsIn(
                          formatLaunchOfferRemaining(remaining),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Semantics(
                      label: l10n.commonClose,
                      button: true,
                      child: IconButton(
                        key: const Key('launch-offer-mini-close'),
                        onPressed: () => setState(() {
                          _dismissedCycle = cycle;
                        }),
                        icon: const Icon(LucideIcons.x),
                      ),
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

  Future<void> _showPaywall(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: LaunchOfferPaywall(
          compact: true,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
