import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
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
    ref.watch(billingViewModelProvider);
    final state = ref.watch(onboardingViewModelProvider);
    return Stack(
      children: [
        child,
        if (!state.loading && !state.completed) const _OnboardingOverlay(),
        if (!state.loading && state.completed) const _LaunchOfferMiniWindow(),
      ],
    );
  }
}

class _OnboardingOverlay extends ConsumerWidget {
  const _OnboardingOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return Positioned.fill(
      child: Material(
        color: colors.primaryText.withValues(alpha: 0.35),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                margin: const EdgeInsets.all(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: _OnboardingStepBody(
                      step: ref.watch(onboardingViewModelProvider).step,
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
}

class _OnboardingStepBody extends ConsumerWidget {
  const _OnboardingStepBody({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingViewModelProvider.notifier);
    return Column(
      key: ValueKey('onboarding-step-${step.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _StepHeader(step: step)),
            const SizedBox(width: 8),
            Semantics(
              label: l10n.commonClose,
              button: true,
              child: IconButton(
                key: const Key('onboarding-close-button'),
                onPressed: () => unawaited(controller.complete()),
                icon: const Icon(LucideIcons.x),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        switch (step) {
          OnboardingStep.language => const _LanguageStep(),
          OnboardingStep.timer => const _TimerStep(),
          OnboardingStep.paywall => const _PaywallStep(),
          OnboardingStep.account => const _AccountStep(),
        },
        const SizedBox(height: 18),
        Row(
          children: [
            if (step != OnboardingStep.language)
              ShadButton.ghost(
                key: const Key('onboarding-back-button'),
                onPressed: controller.back,
                leading: const Icon(LucideIcons.arrowLeft),
                child: Text(l10n.commonBack),
              )
            else
              const Spacer(),
            const Spacer(),
            ShadButton(
              key: const Key('onboarding-next-button'),
              onPressed: step == OnboardingStep.account
                  ? () => unawaited(controller.complete())
                  : controller.next,
              child: Text(
                step == OnboardingStep.paywall
                    ? l10n.onboardingMaybeLater
                    : step == OnboardingStep.account
                    ? l10n.onboardingFinish
                    : l10n.onboardingContinue,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = switch (step) {
      OnboardingStep.language => l10n.onboardingLanguageTitle,
      OnboardingStep.timer => l10n.onboardingTimerTitle,
      OnboardingStep.paywall => l10n.onboardingPaywallTitle,
      OnboardingStep.account => l10n.onboardingAccountTitle,
    };
    final subtitle = switch (step) {
      OnboardingStep.language => l10n.onboardingLanguageSubtitle,
      OnboardingStep.timer => l10n.onboardingTimerSubtitle,
      OnboardingStep.paywall => l10n.onboardingPaywallSubtitle,
      OnboardingStep.account => l10n.onboardingAccountSubtitle,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _LanguageStep extends ConsumerWidget {
  const _LanguageStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = ref.watch(onboardingViewModelProvider).language;
    return DropdownButtonFormField<AppLanguage>(
      key: const Key('onboarding-language-select'),
      initialValue: language,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.settingsLanguageTitle,
        prefixIcon: const Icon(LucideIcons.languages),
      ),
      items: [
        for (final item in AppLanguage.values)
          DropdownMenuItem(
            value: item,
            child: Text(
              item == AppLanguage.system
                  ? l10n.settingsLanguageSystem
                  : item.nativeName,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          unawaited(
            ref.read(onboardingViewModelProvider.notifier).setLanguage(value),
          );
        }
      },
    );
  }
}

class _TimerStep extends ConsumerWidget {
  const _TimerStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final style = ref.watch(onboardingViewModelProvider).timerStyle;
    return SegmentedButton<FocusTimerVisualStyle>(
      key: const Key('onboarding-timer-visual-style-select'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: FocusTimerVisualStyle.bar,
          icon: const Icon(LucideIcons.minus),
          label: Text(l10n.settingsTimerVisualBar),
        ),
        ButtonSegment(
          value: FocusTimerVisualStyle.circle,
          icon: const Icon(LucideIcons.circle),
          label: Text(l10n.settingsTimerVisualCircle),
        ),
      ],
      selected: {style},
      onSelectionChanged: (selection) {
        unawaited(
          ref
              .read(onboardingViewModelProvider.notifier)
              .setTimerStyle(selection.single),
        );
      },
    );
  }
}

class _PaywallStep extends ConsumerWidget {
  const _PaywallStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const LaunchOfferPaywall(compact: true);
  }
}

class _AccountStep extends StatelessWidget {
  const _AccountStep();

  @override
  Widget build(BuildContext context) => const PomodoistAccountAccessPanel();
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
        billing.hasActiveEntitlement) {
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
