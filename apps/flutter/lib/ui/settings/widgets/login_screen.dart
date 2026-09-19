import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/ui/focus/widgets/focus_screen.dart';
import 'package:pomodoist/ui/settings/widgets/pomodoist_account_actions.dart';
import 'package:pomodoist/ui/settings/widgets/auth_surfaces.dart';
import 'package:pomodoist/ui/settings/view_models/auth_view_model.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({
    this.returnTo = '/today',
    this.initialFailure,
    bool? showGuestTimer,
    super.key,
  }) : showGuestTimer = showGuestTimer ?? kIsWeb;

  final String returnTo;
  final AccountAuthFailure? initialFailure;
  final bool showGuestTimer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final auth = ref.watch(authViewModelProvider);
    final redirectTo = loginRedirectFor(returnTo);
    final authPanel = !auth.available && auth.loading
        ? const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                key: Key('login-account-loading'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [LinearProgressIndicator()],
              ),
            ),
          )
        : !auth.available && auth.bootstrapError != null
        ? AccountErrorCard(
            key: const Key('login-account-error'),
            error: auth.bootstrapError!,
            retryKey: const Key('login-account-retry'),
            onRetry: () =>
                unawaited(ref.read(authViewModelProvider.notifier).retry()),
          )
        : !auth.available || !auth.configured
        ? AuthUnavailableCard(
            retryKey: const Key('login-account-retry'),
            onRetry: () =>
                unawaited(ref.read(authViewModelProvider.notifier).retry()),
          )
        : auth.profileLoading
        ? Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                key: const Key('login-account-loading'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.accountChecking, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          )
        : auth.profileError != null
        ? AccountErrorCard(
            key: const Key('login-account-error'),
            error: auth.profileError!,
            retryKey: const Key('login-account-retry'),
            onRetry: () => ref.read(authViewModelProvider.notifier).refresh(),
          )
        : PomodoistAccountOverviewPanel(
            profile: auth.profile,
            onRefresh: () => ref.read(authViewModelProvider.notifier).refresh(),
            actions: pomodoistAccountSignInActions(
              context: context,
              canSignIn: auth.canSignIn,
              redirectTo: redirectTo,
              onSignedIn: () => context.go(returnTo),
              appleLabel: l10n.accountApple,
              googleLabel: l10n.accountGoogle,
              emailLabel: l10n.accountEmail,
            ),
          );

    final footer = AuthRouteLink(
      prompt: l10n.loginCreateAccountPrompt,
      action: l10n.loginCreateAccountAction,
      route: authRoute('/register', returnTo),
      buttonKey: const Key('login-register-link'),
    );
    final authContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (initialFailure case final failure? when !failure.isCancelled) ...[
          AuthFailureNoticeCard(
            failure: failure,
            onSendNewLink: !auth.available
                ? null
                : () => showPomodoistEmailAuthDialog(
                    context: context,
                    redirectTo: redirectTo,
                    onSignedIn: () => context.go(returnTo),
                  ),
          ),
          const SizedBox(height: 12),
        ],
        authPanel,
      ],
    );
    if (!showGuestTimer) {
      return AuthScaffold(
        title: l10n.loginTitle,
        subtitle: l10n.onboardingAccountSubtitle,
        footer: footer,
        child: authContent,
      );
    }
    return _GuestLoginSwitcher(
      title: l10n.loginTitle,
      subtitle: l10n.onboardingAccountSubtitle,
      footer: footer,
      child: authContent,
    );
  }
}

class _GuestLoginSwitcher extends StatefulWidget {
  const _GuestLoginSwitcher({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget footer;

  @override
  State<_GuestLoginSwitcher> createState() => _GuestLoginSwitcherState();
}

class _GuestLoginSwitcherState extends State<_GuestLoginSwitcher>
    with SingleTickerProviderStateMixin {
  static const _duration = AppMotion.panel;
  static const _ctaMotionDuration = Duration(milliseconds: 1200);
  var _timerOpen = false;
  late final AnimationController _ctaMotionController;

  @override
  void initState() {
    super.initState();
    _ctaMotionController = AnimationController(
      vsync: this,
      duration: _ctaMotionDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCtaMotion();
  }

  @override
  void dispose() {
    _ctaMotionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.duration(context, _duration);
    final child = _timerOpen
        ? _GuestTimerScaffold(onClose: () => _setTimerOpen(false))
        : Column(
            children: [
              Expanded(
                child: AuthScaffold(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  footer: widget.footer,
                  child: widget.child,
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: AnimatedBuilder(
                      key: const Key('guest-timer-cta'),
                      animation: _ctaMotionController,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          0,
                          -6 *
                              Curves.easeInOutSine.transform(
                                _ctaMotionController.value,
                              ),
                        ),
                        child: child,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Pomodoro here',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.6,
                                ),
                          ),
                          const SizedBox(height: 6),
                          IconButton.filledTonal(
                            key: const Key('guest-timer-open'),
                            tooltip: context.l10n.focusTitle,
                            onPressed: () => _setTimerOpen(true),
                            icon: const Icon(LucideIcons.chevronDown),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
    return ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: AppMotion.curve,
        switchOutCurve: AppMotion.curve,
        transitionBuilder: (child, animation) {
          final timer = child.key == const ValueKey(true);
          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, timer ? 1 : -1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: KeyedSubtree(key: ValueKey(_timerOpen), child: child),
      ),
    );
  }

  void _setTimerOpen(bool value) {
    if (_timerOpen == value) return;
    setState(() => _timerOpen = value);
    _syncCtaMotion();
  }

  void _syncCtaMotion() {
    if (!mounted || _timerOpen || MediaQuery.disableAnimationsOf(context)) {
      _ctaMotionController
        ..stop()
        ..value = 0;
      return;
    }
    _ctaMotionController.repeat(reverse: true);
  }
}

class _GuestTimerScaffold extends ConsumerWidget {
  const _GuestTimerScaffold({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guestStartup = ref.watch(guestDataStartupViewModelProvider);
    return Scaffold(
      backgroundColor: context.appColors.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: guestStartup.when(
                data: (_) => const SingleChildScrollView(
                  key: Key('guest-timer-scroll'),
                  padding: EdgeInsets.only(top: 52),
                  child: FocusScreen(
                    embedded: true,
                    fixedViewMode: FocusViewMode.full,
                  ),
                ),
                loading: () => const _GuestTimerLoading(),
                error: (error, _) => Center(
                  child: _GuestTimerError(
                    error: error,
                    onRetry: ref
                        .read(guestDataStartupViewModelProvider.notifier)
                        .retry,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: IconButton.filledTonal(
                  key: const Key('guest-timer-close'),
                  tooltip: context.l10n.loginTitle,
                  onPressed: onClose,
                  icon: const Icon(LucideIcons.chevronUp),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestTimerLoading extends StatelessWidget {
  const _GuestTimerLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: SizedBox.square(
          key: Key('guest-timer-loading'),
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _GuestTimerError extends StatelessWidget {
  const _GuestTimerError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        key: const Key('guest-timer-error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ShadButton.outline(
            key: const Key('guest-timer-retry'),
            onPressed: onRetry,
            child: Text(context.l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}
