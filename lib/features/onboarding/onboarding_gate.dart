import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/account_providers.dart';
import '../../app/app_language.dart';
import '../../app/app_l10n.dart';
import '../../app/providers.dart';
import '../../app/runtime_public_config.dart';
import '../../app/theme/app_theme.dart';
import '../billing/billing.dart';
import '../focus/presentation/focus_view_mode.dart';
import '../settings/presentation/pomodoist_account_actions.dart';

const onboardingCompletedPreferenceKey = 'onboarding.completed.v1';
const launchOfferStartedAtPreferenceKey = 'launchOffer.startedAt.v1';
const launchOfferDuration = Duration(hours: 24);
const launchOfferCycleDuration = Duration(days: 7);

enum OnboardingStep { language, timer, paywall, account }

class OnboardingState {
  const OnboardingState({
    this.loading = true,
    this.completed = false,
    this.step = OnboardingStep.language,
    this.launchOfferStartedAt,
  });

  final bool loading;
  final bool completed;
  final OnboardingStep step;
  final DateTime? launchOfferStartedAt;

  OnboardingState copyWith({
    bool? loading,
    bool? completed,
    OnboardingStep? step,
    DateTime? launchOfferStartedAt,
  }) {
    return OnboardingState(
      loading: loading ?? this.loading,
      completed: completed ?? this.completed,
      step: step ?? this.step,
      launchOfferStartedAt: launchOfferStartedAt ?? this.launchOfferStartedAt,
    );
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    unawaited(_load());
    return const OnboardingState();
  }

  void next() {
    if (state.step == OnboardingStep.account) {
      unawaited(complete());
      return;
    }
    state = state.copyWith(step: OnboardingStep.values[state.step.index + 1]);
  }

  void back() {
    if (state.step == OnboardingStep.language) {
      return;
    }
    state = state.copyWith(step: OnboardingStep.values[state.step.index - 1]);
  }

  Future<void> complete() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setBool(onboardingCompletedPreferenceKey, true);
    if (ref.mounted) {
      state = state.copyWith(completed: true);
    }
  }

  Future<void> _load() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    if (!ref.mounted) {
      return;
    }
    final completed = prefs?.getBool(onboardingCompletedPreferenceKey) ?? false;
    final now = ref.read(clockProvider).now().toUtc();
    var startedAt = _parseDateTime(
      prefs?.getString(launchOfferStartedAtPreferenceKey),
    );
    if (startedAt == null) {
      startedAt = now;
      await prefs?.setString(
        launchOfferStartedAtPreferenceKey,
        startedAt.toIso8601String(),
      );
    }
    if (ref.mounted) {
      state = state.copyWith(
        loading: false,
        completed: completed,
        launchOfferStartedAt: startedAt,
      );
    }
  }
}

DateTime? _parseDateTime(String? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

Duration launchOfferRemaining({
  required DateTime now,
  required DateTime? startedAt,
}) {
  if (startedAt == null) {
    return Duration.zero;
  }
  final elapsed = now.toUtc().difference(startedAt.toUtc());
  if (elapsed.isNegative) {
    return Duration.zero;
  }
  final cyclePosition = Duration(
    microseconds:
        elapsed.inMicroseconds % launchOfferCycleDuration.inMicroseconds,
  );
  if (cyclePosition >= launchOfferDuration) {
    return Duration.zero;
  }
  return launchOfferDuration - cyclePosition;
}

int? _launchOfferCycle({required DateTime now, required DateTime? startedAt}) {
  if (startedAt == null) {
    return null;
  }
  final elapsed = now.toUtc().difference(startedAt.toUtc());
  if (elapsed.isNegative) {
    return null;
  }
  return elapsed.inMicroseconds ~/ launchOfferCycleDuration.inMicroseconds;
}

String formatLaunchOfferRemaining(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(billingControllerProvider);
    final state = ref.watch(onboardingControllerProvider);
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
                      step: ref.watch(onboardingControllerProvider).step,
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
    final controller = ref.read(onboardingControllerProvider.notifier);
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
                icon: const Icon(Icons.close),
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
              TextButton.icon(
                key: const Key('onboarding-back-button'),
                onPressed: controller.back,
                icon: const Icon(Icons.arrow_back),
                label: Text(l10n.commonBack),
              )
            else
              const Spacer(),
            const Spacer(),
            FilledButton(
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
    final language = ref.watch(appLanguageProvider);
    return DropdownButtonFormField<AppLanguage>(
      key: const Key('onboarding-language-select'),
      initialValue: language,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.settingsLanguageTitle,
        prefixIcon: const Icon(Icons.language),
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
          ref.read(appLanguageProvider.notifier).setLanguage(value);
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
    final style = ref.watch(focusTimerVisualStyleProvider);
    return SegmentedButton<FocusTimerVisualStyle>(
      key: const Key('onboarding-timer-visual-style-select'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: FocusTimerVisualStyle.bar,
          icon: const Icon(Icons.horizontal_rule),
          label: Text(l10n.settingsTimerVisualBar),
        ),
        ButtonSegment(
          value: FocusTimerVisualStyle.circle,
          icon: const Icon(Icons.circle_outlined),
          label: Text(l10n.settingsTimerVisualCircle),
        ),
      ],
      selected: {style},
      onSelectionChanged: (selection) {
        ref
            .read(focusTimerVisualStyleProvider.notifier)
            .setStyle(selection.single);
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

class _AccountStep extends ConsumerWidget {
  const _AccountStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final accountOverview = ref.watch(accountOverviewProvider);
    final accountConfigured = ref.watch(accountConfiguredProvider);
    ref.watch(accountAuthStateProvider);
    return accountOverview.when(
      data: (overview) => accountConfigured
          ? AccountOverviewPanel(
              overview: overview,
              configured: true,
              actions: _accountActions(context, ref),
            )
          : Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.authServiceUnavailable,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => unawaited(
                          ref.read(accountBootstrapProvider.notifier).retry(),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.commonRetry),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (error, _) => Semantics(
        liveRegion: true,
        child: Text(pomodoistAccountFailureMessage(context, error)),
      ),
    );
  }

  List<Widget> _accountActions(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return pomodoistAccountSignInActions(
      context: context,
      account: ref.read(accountClientProvider),
      redirectTo: pomodoistLoginRedirect,
      config: ref.read(runtimePublicConfigProvider),
      nativeCaptchaCallbacks: ref
          .read(nativeLinkCoordinatorProvider)
          ?.captchaCallbacks,
      appleLabel: l10n.accountApple,
      googleLabel: l10n.accountGoogle,
      emailLabel: l10n.accountEmail,
    );
  }
}

class LaunchOfferPaywall extends ConsumerStatefulWidget {
  const LaunchOfferPaywall({super.key, this.compact = false, this.onClose});

  final bool compact;
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
    final onboarding = ref.watch(onboardingControllerProvider);
    final billing = ref.watch(billingControllerProvider);
    final now = ref.watch(clockProvider).now();
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
    final onboarding = ref.watch(onboardingControllerProvider);
    final billing = ref.watch(billingControllerProvider);
    final now = ref.watch(clockProvider).now();
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
        : _launchOfferCycle(
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
          elevation: 8,
          shadowColor: colors.primaryText.withValues(alpha: 0.16),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showPaywall(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, color: colors.accent, size: 20),
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
                        icon: const Icon(Icons.close),
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
