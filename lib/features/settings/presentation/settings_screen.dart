import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadSwitch, ShadSelect, ShadOption;

import '../../../app/account_auth_feedback.dart';
import '../../../app/account_providers.dart';
import '../../../app/captcha_security.dart';
import '../../../app/captcha_verification.dart';
import '../../../app/native_captcha_broker.dart';
import '../../../app/runtime_public_config.dart';
import '../../../app/app_language.dart';
import '../../../app/app_l10n.dart';
import '../../../app/formatters.dart';
import '../../../app/task_time.dart';
import '../../../app/legal_urls.dart';
import '../../../app/providers.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../focus/presentation/focus_view_mode.dart';
import '../../focus/presentation/focus_screen.dart';
import '../../integrations/google_calendar/presentation/google_calendar_settings_screen.dart';
import '../../voice/data/voice_transcription_mode.dart';
import 'settings_components.dart';
import 'settings_navigation.dart';
import 'settings_subscription.dart';
import 'account_sign_out_button.dart';
import 'app_info_card.dart';
import 'csv_task_import_card.dart';
import 'theme_settings_card.dart';
import 'voice_transcription_settings_card.dart';
import 'pomodoist_account_actions.dart';

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
    ref.watch(accountAuthStateProvider);
    final accountOverview = ref.watch(accountOverviewProvider);
    final accountBootstrap = ref.watch(accountBootstrapProvider);
    final account = ref.watch(accountClientProvider);
    final accountConfigured = ref.watch(accountConfiguredProvider);
    final redirectTo = _loginRedirectFor(returnTo);
    final authPanel = account == null && accountBootstrap.isLoading
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
        : account == null && accountBootstrap.hasError
        ? _AccountErrorCard(
            key: const Key('login-account-error'),
            error: accountBootstrap.error!,
            retryKey: const Key('login-account-retry'),
            onRetry: () =>
                unawaited(ref.read(accountBootstrapProvider.notifier).retry()),
          )
        : account == null || !accountConfigured
        ? _AuthUnavailableCard(
            retryKey: const Key('login-account-retry'),
            onRetry: () =>
                unawaited(ref.read(accountBootstrapProvider.notifier).retry()),
          )
        : accountOverview.when(
            data: (overview) => AccountOverviewPanel(
              overview: overview,
              configured: true,
              onRefresh: () => ref.invalidate(accountOverviewProvider),
              actions: pomodoistAccountSignInActions(
                context: context,
                account: account,
                redirectTo: redirectTo,
                config: ref.read(runtimePublicConfigProvider),
                nativeCaptchaCallbacks: ref
                    .read(nativeLinkCoordinatorProvider)
                    ?.captchaCallbacks,
                onSignedIn: () => context.go(returnTo),
                appleLabel: l10n.accountApple,
                googleLabel: l10n.accountGoogle,
                emailLabel: l10n.accountEmail,
              ),
            ),
            loading: () => Card(
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
            ),
            error: (error, _) => _AccountErrorCard(
              key: const Key('login-account-error'),
              error: error,
              retryKey: const Key('login-account-retry'),
              onRetry: () => ref.invalidate(accountOverviewProvider),
            ),
          );

    final footer = _AuthRouteLink(
      prompt: l10n.loginCreateAccountPrompt,
      action: l10n.loginCreateAccountAction,
      route: _authRoute('/register', returnTo),
      buttonKey: const Key('login-register-link'),
    );
    final authContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (initialFailure case final failure? when !failure.isCancelled) ...[
          _AuthFailureNoticeCard(
            failure: failure,
            onSendNewLink: account == null
                ? null
                : () => showPomodoistEmailAuthDialog(
                    context: context,
                    account: account,
                    redirectTo: redirectTo,
                    config: ref.read(runtimePublicConfigProvider),
                    nativeCaptchaCallbacks: ref
                        .read(nativeLinkCoordinatorProvider)
                        ?.captchaCallbacks,
                    onSignedIn: () => context.go(returnTo),
                  ),
          ),
          const SizedBox(height: 12),
        ],
        authPanel,
      ],
    );
    if (!showGuestTimer) {
      return _StandaloneAuthScaffold(
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
                child: _StandaloneAuthScaffold(
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
    final guestStartup = ref.watch(guestDataStartupProvider);
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
                    onRetry: () => ref.invalidate(guestDataStartupProvider),
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

class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({this.returnTo = '/today', super.key});

  final String returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final account = ref.watch(accountClientProvider);
    final accountBootstrap = ref.watch(accountBootstrapProvider);
    final redirectTo = _loginRedirectFor(returnTo);

    return _StandaloneAuthScaffold(
      title: l10n.registerTitle,
      subtitle: l10n.registerSubtitle,
      footer: _AuthRouteLink(
        prompt: l10n.registerSignInPrompt,
        action: l10n.registerSignInAction,
        route: _authRoute('/login', returnTo),
        buttonKey: const Key('register-login-link'),
      ),
      child: account == null && accountBootstrap.isLoading
          ? const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            )
          : account == null && accountBootstrap.hasError
          ? _AccountErrorCard(
              key: const Key('register-account-error'),
              error: accountBootstrap.error!,
              retryKey: const Key('register-account-retry'),
              onRetry: () => unawaited(
                ref.read(accountBootstrapProvider.notifier).retry(),
              ),
            )
          : account == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthUnavailableCard(
                  retryKey: const Key('register-account-retry'),
                  onRetry: () => unawaited(
                    ref.read(accountBootstrapProvider.notifier).retry(),
                  ),
                ),
                const SizedBox(height: 12),
                _RegisterForm(
                  account: null,
                  redirectTo: redirectTo,
                  returnTo: returnTo,
                ),
              ],
            )
          : _RegisterForm(
              account: account,
              redirectTo: redirectTo,
              returnTo: returnTo,
            ),
    );
  }
}

class _StandaloneAuthScaffold extends StatelessWidget {
  const _StandaloneAuthScaffold({
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  child,
                  const SizedBox(height: 12),
                  footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthRouteLink extends StatelessWidget {
  const _AuthRouteLink({
    required this.prompt,
    required this.action,
    required this.route,
    required this.buttonKey,
  });

  final String prompt;
  final String action;
  final String route;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text(prompt),
        ShadButton.outline(
          key: buttonKey,
          onPressed: () => context.go(route),
          child: Text(action),
        ),
      ],
    );
  }
}

class _RegisterForm extends ConsumerStatefulWidget {
  const _RegisterForm({
    required this.account,
    required this.redirectTo,
    required this.returnTo,
  });

  final AccountClient? account;
  final String redirectTo;
  final String returnTo;

  @override
  ConsumerState<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<_RegisterForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _submitting = false;
  bool _emailSent = false;
  AccountAuthFeedback? _feedback;
  late final RuntimePublicConfig _config;
  late final CaptchaTokenController _captcha;
  NativeCaptchaBroker? _nativeBroker;
  Timer? _slowTimer;
  bool _takingLonger = false;

  static const _slowThreshold = Duration(seconds: 30);

  bool get _canSubmit => widget.account != null && !_submitting;

  @override
  void initState() {
    super.initState();
    _config = ref.read(runtimePublicConfigProvider);
    _captcha = CaptchaTokenController(
      required: kIsWeb && _config.turnstileSiteKey.isNotEmpty,
    );
    if (!kIsWeb && _config.turnstileSiteKey.isNotEmpty) {
      final callbacks = ref
          .read(nativeLinkCoordinatorProvider)
          ?.captchaCallbacks;
      if (callbacks != null) {
        _nativeBroker = NativeCaptchaBroker(uriStream: callbacks);
      }
    }
    _emailController.addListener(_emailChanged);
    _passwordController.addListener(_passwordChanged);
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _nativeBroker?.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _emailChanged() {
    if (_feedback?.field == AccountAuthField.email) _feedback = null;
    if (!mounted) return;
    setState(() {});
  }

  void _passwordChanged() {
    if (_feedback?.field == AccountAuthField.password) _feedback = null;
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = widget.account;
    final feedback = _feedback;

    if (_emailSent) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(LucideIcons.mailCheck, size: 40),
              const SizedBox(height: 12),
              Text(
                l10n.registerCheckEmailTitle,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(l10n.registerCheckEmailMessage, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (account != null)
                PomodoistSocialSignInButton(
                  account: account,
                  provider: PomodoistSocialProvider.apple,
                  redirectTo: widget.redirectTo,
                  label: l10n.accountApple,
                  onSignedIn: () => context.go(widget.returnTo),
                ),
              const SizedBox(height: 8),
              if (account != null)
                PomodoistSocialSignInButton(
                  account: account,
                  provider: PomodoistSocialProvider.google,
                  redirectTo: widget.redirectTo,
                  label: l10n.accountGoogle,
                  onSignedIn: () => context.go(widget.returnTo),
                ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: feedback?.field == AccountAuthField.email,
                child: TextField(
                  key: const Key('register-email-field'),
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.accountEmail,
                    errorText: feedback?.field == AccountAuthField.email
                        ? feedback?.message
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Semantics(
                liveRegion: feedback?.field == AccountAuthField.password,
                child: TextField(
                  key: const Key('register-password-field'),
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: l10n.registerPassword,
                    errorText: feedback?.field == AccountAuthField.password
                        ? feedback?.message
                        : null,
                  ),
                  obscureText: true,
                ),
              ),
              if (kIsWeb && _config.turnstileSiteKey.isNotEmpty) ...[
                const SizedBox(height: 16),
                CaptchaVerification(
                  siteKey: _config.turnstileSiteKey,
                  controller: _captcha,
                  onChanged: () {
                    if (_feedback?.field == AccountAuthField.captcha) {
                      _feedback = null;
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ],
              if (feedback != null &&
                  (feedback.field == AccountAuthField.form ||
                      feedback.field == AccountAuthField.captcha)) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    feedback.message,
                    key: const Key('register-auth-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (feedback != null &&
                  feedback.recovery != AccountAuthRecovery.none &&
                  feedback.recovery != AccountAuthRecovery.editEmail &&
                  feedback.recovery != AccountAuthRecovery.editPassword &&
                  feedback.recovery !=
                      AccountAuthRecovery.chooseAnotherProvider) ...[
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ShadButton.ghost(
                    key: const Key('register-auth-recovery'),
                    enabled: !_submitting,
                    onPressed: _submitting
                        ? null
                        : () => _recover(feedback.recovery),
                    child: Text(
                      accountAuthRecoveryLabel(l10n, feedback.recovery),
                    ),
                  ),
                ),
              ],
              if (_takingLonger) ...[
                const SizedBox(height: 10),
                Semantics(
                  key: const Key('register-auth-slow'),
                  liveRegion: true,
                  child: Row(
                    children: [
                      const Icon(LucideIcons.hourglass, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l10n.operationTakingLonger)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ShadButton(
                key: const Key('register-submit-button'),
                enabled: _canSubmit,
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? _takingLonger
                          ? const Icon(LucideIcons.hourglass, size: 18)
                          : SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                    : Text(l10n.registerSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final account = widget.account;
    if (account == null) {
      return;
    }
    final emailFailure = validateAccountEmail(_emailController.text);
    final passwordFailure = validateAccountPassword(_passwordController.text);
    if (emailFailure != null || passwordFailure != null) {
      _showFailure(emailFailure ?? passwordFailure!);
      return;
    }
    if (kIsWeb && _config.turnstileSiteKey.isNotEmpty && !_captcha.canSubmit) {
      _showFailure(
        const AccountAuthFailure(
          AccountAuthFailureKind.captchaRequired,
          field: AccountAuthField.captcha,
          recovery: AccountAuthRecovery.retryCaptcha,
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _takingLonger = false;
      _feedback = null;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(_slowThreshold, () {
      if (mounted && _submitting) setState(() => _takingLonger = true);
    });
    var webRequestStarted = false;
    try {
      final String? token;
      if (kIsWeb) {
        token = _captcha.beginRequest();
        webRequestStarted = true;
      } else if (_config.turnstileSiteKey.isNotEmpty) {
        final broker = _nativeBroker;
        if (broker == null) {
          throw const NativeCaptchaException(
            NativeCaptchaFailureCode.unavailable,
          );
        }
        token = await broker.requestToken();
      } else {
        token = null;
      }
      await account.signUpWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        redirectTo: widget.redirectTo,
        captchaToken: token,
      );
      TextInput.finishAutofillContext(shouldSave: true);
      if (!mounted) {
        return;
      }
      if (account.currentUserId != null) {
        context.go(widget.returnTo);
        return;
      }
      setState(() => _emailSent = true);
    } on Object catch (error) {
      if (mounted) {
        _showFailure(
          classifyAccountAuthFailure(
            error,
            operation: AccountAuthOperation.signUp,
          ),
        );
      }
    } finally {
      _slowTimer?.cancel();
      if (webRequestStarted) _captcha.finishRequest();
      if (mounted) {
        setState(() {
          _submitting = false;
          _takingLonger = false;
        });
      }
    }
  }

  void _showFailure(AccountAuthFailure failure) {
    if (!mounted || failure.isCancelled) return;
    final feedback = presentAccountAuthFailure(
      context.l10n,
      failure,
      operation: AccountAuthOperation.signUp,
    );
    setState(() => _feedback = feedback);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (feedback.field) {
        case AccountAuthField.email:
          _emailFocus.requestFocus();
        case AccountAuthField.password:
          _passwordFocus.requestFocus();
        case AccountAuthField.captcha:
        case AccountAuthField.form:
          break;
      }
    });
  }

  void _recover(AccountAuthRecovery recovery) {
    switch (recovery) {
      case AccountAuthRecovery.retry:
        unawaited(_submit());
      case AccountAuthRecovery.retryCaptcha:
        if (kIsWeb) {
          _captcha.reset();
          setState(() => _feedback = null);
        } else {
          unawaited(_submit());
        }
      case AccountAuthRecovery.switchToSignIn:
      case AccountAuthRecovery.sendNewLink:
        final account = widget.account;
        if (account == null) return;
        _passwordController.clear();
        setState(() => _feedback = null);
        unawaited(
          showPomodoistEmailAuthDialog(
            context: context,
            account: account,
            redirectTo: widget.redirectTo,
            config: _config,
            nativeCaptchaCallbacks: ref
                .read(nativeLinkCoordinatorProvider)
                ?.captchaCallbacks,
            initialEmail: _emailController.text,
            onSignedIn: () => context.go(widget.returnTo),
          ),
        );
      case AccountAuthRecovery.editEmail:
        _emailFocus.requestFocus();
      case AccountAuthRecovery.editPassword:
        _passwordFocus.requestFocus();
      case AccountAuthRecovery.none:
      case AccountAuthRecovery.chooseAnotherProvider:
        break;
    }
  }
}

String _loginRedirectFor(String returnTo) {
  final uri = Uri.parse(pomodoistLoginRedirect);
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'returnTo': returnTo})
      .toString();
}

String _authRoute(String path, String returnTo) {
  if (returnTo == '/today') {
    return path;
  }
  return Uri(path: path, queryParameters: {'returnTo': returnTo}).toString();
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({this.location, this.signOutOverride, super.key});

  final Uri? location;
  final Future<void> Function()? signOutOverride;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final _navigation = SettingsNavigation(
    widget.location ?? Uri(path: '/settings'),
  );
  final _visited = <SettingsSection>{};
  late final _fade = AnimationController(vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
    // The controller owns the first request; later visits refresh quietly.
    if (!ref.read(connectedAgentsProvider).isLoading) {
      unawaited(
        Future<void>.microtask(() {
          if (mounted) {
            return ref.read(connectedAgentsProvider.notifier).refresh();
          }
        }),
      );
    }
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _navigation.selected;
    _navigation.syncLocation(widget.location ?? Uri(path: '/settings'));
    if (_navigation.selected != previous) {
      FocusManager.instance.primaryFocus?.unfocus();
      _fade.duration = AppMotion.duration(context, AppMotion.state);
      _fade.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _fade.value = 1;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  String _title(SettingsSection section) {
    final l10n = context.l10n;
    return switch (section) {
      SettingsSection.general => l10n.settingsSectionGeneral,
      SettingsSection.appearance => l10n.settingsSectionAppearance,
      SettingsSection.tasksFocus => l10n.settingsSectionTasksFocus,
      SettingsSection.integrations => l10n.settingsSectionIntegrations,
      SettingsSection.account => l10n.settingsSectionAccount,
      SettingsSection.about => l10n.settingsAboutTitle,
    };
  }

  IconData _icon(SettingsSection section) => switch (section) {
    SettingsSection.general => LucideIcons.slidersHorizontal,
    SettingsSection.appearance => LucideIcons.palette,
    SettingsSection.tasksFocus => LucideIcons.timer,
    SettingsSection.integrations => LucideIcons.plug,
    SettingsSection.account => LucideIcons.userRound,
    SettingsSection.about => LucideIcons.info,
  };

  Widget _menu({required bool wide}) => ListView(
    padding: EdgeInsets.zero,
    children: [
      for (final section in SettingsSection.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Semantics(
            selected: wide && _navigation.selected == section,
            child: ShadButton.ghost(
              height: 48,
              mainAxisAlignment: MainAxisAlignment.start,
              backgroundColor: wide && _navigation.selected == section
                  ? context.appColors.accent.withValues(alpha: 0.10)
                  : null,
              foregroundColor: wide && _navigation.selected == section
                  ? context.appColors.accent
                  : context.appColors.primaryText,
              onPressed: () => context.go(settingsLocation(section).toString()),
              child: Expanded(
                child: Row(
                  children: [
                    Icon(_icon(section), size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_title(section))),
                    if (!wide) const Icon(LucideIcons.chevronRight, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => SettingsSurface(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        _navigation.resolveLayout(wide: wide);
        final selected = _navigation.selected;
        if (selected != null) _visited.add(selected);
        return PopScope(
          canPop: wide || selected == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !wide && selected != null) {
              context.go(settingsLocation(null).toString());
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (!wide && selected != null) ...[
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () =>
                          context.go(settingsLocation(null).toString()),
                      icon: const Icon(LucideIcons.arrowLeft),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      context.l10n.settingsTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Offstage(
                      offstage: !wide,
                      child: ExcludeFocus(
                        excluding: !wide,
                        child: SizedBox(width: 216, child: _menu(wide: true)),
                      ),
                    ),
                    SizedBox(width: wide ? 32 : 0),
                    Expanded(
                      child: FadeTransition(
                        opacity: _fade.drive(
                          CurveTween(curve: AppMotion.curve),
                        ),
                        child: IndexedStack(
                          index: selected == null ? 0 : selected.index + 1,
                          children: [
                            ExcludeFocus(
                              excluding: selected != null,
                              child: _menu(wide: false),
                            ),
                            for (final section in SettingsSection.values)
                              TickerMode(
                                enabled: selected == section,
                                child: ExcludeFocus(
                                  excluding: selected != section,
                                  child: _visited.contains(section)
                                      ? ListView(
                                          key: PageStorageKey(
                                            'settings-${section.name}',
                                          ),
                                          padding: EdgeInsets.zero,
                                          children: [
                                            Text(
                                              _title(section),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                            ),
                                            const SizedBox(height: 12),
                                            Consumer(
                                              builder: (context, ref, _) =>
                                                  _content(section, ref),
                                            ),
                                            const SizedBox(height: 24),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _content(SettingsSection section, WidgetRef ref) {
    final l10n = context.l10n;
    switch (section) {
      case SettingsSection.general:
        ref.watch(accountAuthStateProvider);
        final language = ref.watch(appLanguageProvider);
        return SettingsGroup(
          children: [
            SettingsRow(
              title: l10n.settingsLanguageTitle,
              subtitle: l10n.settingsLanguageSubtitle,
              control: ShadSelect<AppLanguage>(
                key: ValueKey(language),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                initialValue: language,
                options: [
                  for (final item in AppLanguage.values)
                    ShadOption(
                      value: item,
                      child: Text(
                        item == AppLanguage.system
                            ? l10n.settingsLanguageSystem
                            : item.nativeName,
                      ),
                    ),
                ],
                selectedOptionBuilder: (context, item) => Text(
                  item == AppLanguage.system
                      ? l10n.settingsLanguageSystem
                      : item.nativeName,
                ),
                onChanged: (value) {
                  if (value != null) {
                    saveSetting(
                      context,
                      ref.read(appLanguageProvider.notifier).setLanguage(value),
                    );
                  }
                },
              ),
            ),
            if (supportsVoiceTranscriptionModeSelection(
              isWeb: kIsWeb,
              platform: defaultTargetPlatform,
            ))
              VoiceTranscriptionSettingsCard(
                signedIn:
                    ref.watch(accountClientProvider)?.currentUserId != null,
              ),
            SettingsRow(
              title: l10n.settingsReturnRemindersTitle,
              subtitle: l10n.settingsReturnRemindersSubtitle,
              onTap: () => saveSetting(
                context,
                ref
                    .read(reengagementNotificationsEnabledProvider.notifier)
                    .setEnabled(
                      !ref.read(reengagementNotificationsEnabledProvider),
                    ),
              ),
              controlWidth: 48,
              control: ShadSwitch(
                key: const Key('settings-reengagement-notifications-switch'),
                value: ref.watch(reengagementNotificationsEnabledProvider),
                onChanged: (value) => saveSetting(
                  context,
                  ref
                      .read(reengagementNotificationsEnabledProvider.notifier)
                      .setEnabled(value),
                ),
              ),
            ),
            ListTile(
              key: const Key('settings-shortcuts-button'),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              leading: const Icon(LucideIcons.keyboard, size: 20),
              title: Text(l10n.settingsShortcutsTitle),
              subtitle: Text(l10n.settingsShortcutsSubtitle),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => context.push('/settings/shortcuts'),
            ),
          ],
        );
      case SettingsSection.appearance:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ThemeSettingsCard(),
            SizedBox(height: 24),
            _TaskListStyleSettings(),
          ],
        );
      case SettingsSection.tasksFocus:
        final style = ref.watch(focusTimerVisualStyleProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DefaultTimedBlockDurationSettings(),
            const SizedBox(height: 24),
            SettingsGroup(
              children: [
                SettingsRow(
                  title: l10n.settingsTimerVisualTitle,
                  subtitle: l10n.settingsTimerVisualSubtitle,
                  control: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in FocusTimerVisualStyle.values)
                        ChoiceChip(
                          label: Text(
                            option == FocusTimerVisualStyle.bar
                                ? l10n.settingsTimerVisualBar
                                : l10n.settingsTimerVisualCircle,
                          ),
                          selected: option == style,
                          onSelected: (_) => saveSetting(
                            context,
                            ref
                                .read(focusTimerVisualStyleProvider.notifier)
                                .setStyle(option),
                          ),
                        ),
                    ],
                  ),
                ),
                SettingsRow(
                  title: l10n.settingsFocusCompletionCelebrationTitle,
                  subtitle: l10n.settingsFocusCompletionCelebrationSubtitle,
                  onTap: () => saveSetting(
                    context,
                    ref
                        .read(
                          focusCompletionCelebrationEnabledProvider.notifier,
                        )
                        .setEnabled(
                          !ref.read(focusCompletionCelebrationEnabledProvider),
                        ),
                  ),
                  controlWidth: 48,
                  control: ShadSwitch(
                    key: const Key(
                      'settings-focus-completion-celebration-switch',
                    ),
                    value: ref.watch(focusCompletionCelebrationEnabledProvider),
                    onChanged: (value) => saveSetting(
                      context,
                      ref
                          .read(
                            focusCompletionCelebrationEnabledProvider.notifier,
                          )
                          .setEnabled(value),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case SettingsSection.integrations:
        ref.watch(accountAuthStateProvider);
        final account = ref.watch(accountClientProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!kIsWeb) ...[
              const GoogleCalendarSettingsScreen(embedded: true),
              const SizedBox(height: 24),
            ],
            if (ref.watch(accountConfiguredProvider) &&
                account?.currentUserId != null) ...[
              _ConnectedAgentsSection(
                key: ValueKey(account!.currentUserId),
                account: account,
              ),
              const SizedBox(height: 24),
            ],
            if (isCsvTaskImportSupported()) const CsvTaskImportCard(),
          ],
        );
      case SettingsSection.account:
        return _account(ref);
      case SettingsSection.about:
        return const SettingsAppInfoCard(key: Key('settings-app-info-section'));
    }
  }

  Widget _account(WidgetRef ref) {
    final l10n = context.l10n;
    ref.watch(accountAuthStateProvider);
    final account = ref.watch(accountClientProvider);
    final bootstrap = ref.watch(accountBootstrapProvider);
    final overview = ref.watch(accountOverviewProvider);
    final configured = ref.watch(accountConfiguredProvider);
    final signedIn = account?.currentUserId != null;
    final profile = overview.value?.profile;
    final returnTo = settingsLocation(SettingsSection.account).toString();
    void retryBootstrap() => unawaited(
      ref
          .read(accountBootstrapProvider.notifier)
          .retry()
          .whenComplete(() => ref.invalidate(accountOverviewProvider)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (account == null && bootstrap.hasError)
          _AccountErrorCard(
            key: const Key('account-bootstrap-error'),
            error: bootstrap.error!,
            retryKey: const Key('account-bootstrap-retry'),
            onRetry: retryBootstrap,
          )
        else if (account == null && bootstrap.isLoading)
          const LinearProgressIndicator()
        else if (!configured)
          _AuthUnavailableCard(
            retryKey: const Key('account-unavailable-retry'),
            onRetry: retryBootstrap,
          )
        else ...[
          if (overview.isLoading) const LinearProgressIndicator(minHeight: 2),
          if (profile != null || signedIn)
            SettingsRow(
              title: profile?.displayName ?? profile?.email ?? l10n.account,
              subtitle: profile?.email,
              controlWidth: 48,
              control: IconButton(
                tooltip: l10n.settingsRefreshAccount,
                onPressed: overview.isLoading
                    ? null
                    : () => ref.invalidate(accountOverviewProvider),
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
            )
          else if (!overview.isLoading && !overview.hasError) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.loginTitle),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pomodoistAccountSignInActions(
                context: context,
                account: account,
                redirectTo: _loginRedirectFor(returnTo),
                onSignedIn: () => context.go(returnTo),
                config: ref.read(runtimePublicConfigProvider),
                nativeCaptchaCallbacks: ref
                    .read(nativeLinkCoordinatorProvider)
                    ?.captchaCallbacks,
                appleLabel: l10n.accountApple,
                googleLabel: l10n.accountGoogle,
                emailLabel: l10n.accountEmail,
              ),
            ),
          ],
          if (overview.hasError)
            _AccountErrorCard(
              key: const Key('account-overview-error'),
              error: overview.error!,
              retryKey: const Key('account-overview-retry'),
              onRetry: () => ref.invalidate(accountOverviewProvider),
            ),
        ],
        const SizedBox(height: 24),
        const SettingsSubscription(),
        if (signedIn) ...[
          const SizedBox(height: 24),
          Divider(height: 1, thickness: 1, color: context.appColors.border),
          Padding(
            key: const Key('account-delete-section'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AccountSignOutButton(
                  key: const Key('account-sign-out-button'),
                  onSignOut:
                      widget.signOutOverride ??
                      () async {
                        await account?.signOut();
                      },
                  label: l10n.signOut,
                ),
                ShadButton.ghost(
                  height: 48,
                  key: const Key('account-delete-button'),
                  foregroundColor: context.appColors.error,
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    animationStyle: AnimationStyle(
                      duration: AppMotion.duration(context, AppMotion.popup),
                      reverseDuration: AppMotion.duration(
                        context,
                        AppMotion.popup,
                      ),
                      curve: AppMotion.curve,
                    ),
                    builder: (_) => _AccountDeleteDialog(account: account!),
                  ),
                  leading: const Icon(LucideIcons.trash2, size: 18),
                  child: Text(l10n.deleteAccount),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectedAgentsSection extends ConsumerStatefulWidget {
  const _ConnectedAgentsSection({required this.account, super.key});

  final AccountClient account;

  @override
  ConsumerState<_ConnectedAgentsSection> createState() =>
      _ConnectedAgentsSectionState();
}

class _ConnectedAgentsSectionState
    extends ConsumerState<_ConnectedAgentsSection> {
  Object? _revokeError;
  String? _revokingClientId;
  BuildContext? _confirmationContext;
  late AccountClient _account;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _userId = widget.account.currentUserId;
  }

  @override
  void didUpdateWidget(_ConnectedAgentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userId = widget.account.currentUserId;
    if (!identical(_account, widget.account) || _userId != userId) {
      _dismissConfirmation();
      _account = widget.account;
      _userId = userId;
      _revokeError = null;
      _revokingClientId = null;
    }
  }

  @override
  void dispose() {
    _dismissConfirmation();
    super.dispose();
  }

  bool _isCurrent(AccountClient account, String? userId) {
    return mounted &&
        userId != null &&
        identical(_account, account) &&
        identical(widget.account, account) &&
        _userId == userId &&
        account.currentUserId == userId;
  }

  void _dismissConfirmation() {
    final dialogContext = _confirmationContext;
    _confirmationContext = null;
    if (dialogContext == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop(false);
    });
  }

  Future<void> _load() => ref.read(connectedAgentsProvider.notifier).refresh();

  Future<void> _confirmRevoke(AccountOAuthGrant grant) async {
    if (_revokingClientId != null) return;
    final account = widget.account;
    final userId = account.currentUserId;
    if (!_isCurrent(account, userId)) return;
    final l10n = context.l10n;
    final clientName = grant.clientName?.trim().isNotEmpty == true
        ? grant.clientName!.trim()
        : l10n.settingsConnectedAgentsUnknownClient;
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          animationStyle: AnimationStyle(
            duration: AppMotion.duration(context, AppMotion.popup),
            reverseDuration: AppMotion.duration(context, AppMotion.popup),
            curve: AppMotion.curve,
          ),
          builder: (dialogContext) {
            _confirmationContext = dialogContext;
            return AlertDialog(
              key: const Key('connected-agent-revoke-dialog'),
              title: Text(l10n.settingsConnectedAgentsRevokeConfirmTitle),
              content: Text(
                l10n.settingsConnectedAgentsRevokeConfirmMessage(clientName),
              ),
              actions: [
                ShadButton.ghost(
                  height: 48,
                  key: const Key('connected-agent-revoke-cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.commonCancel),
                ),
                ShadButton(
                  height: 48,
                  key: const Key('connected-agent-revoke-confirm'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.settingsConnectedAgentsRevoke),
                ),
              ],
            );
          },
        ) ??
        false;
    _confirmationContext = null;
    if (!confirmed || !_isCurrent(account, userId)) return;
    await _revoke(grant.clientId, account, userId);
  }

  Future<void> _revoke(
    String clientId,
    AccountClient account,
    String? userId,
  ) async {
    if (_revokingClientId != null || !_isCurrent(account, userId)) return;
    setState(() {
      _revokingClientId = clientId;
      _revokeError = null;
    });
    try {
      await ref.read(connectedAgentsProvider.notifier).revoke(clientId);
    } on Object catch (error) {
      if (_isCurrent(account, userId)) {
        setState(() => _revokeError = error);
      }
    } finally {
      if (_isCurrent(account, userId)) {
        setState(() => _revokingClientId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    final agents = ref.watch(connectedAgentsProvider);
    final grants = ref.read(connectedAgentsProvider.notifier).grants;
    return Column(
      key: const Key('connected-agents-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsConnectedAgentsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (agents.isLoading && grants == null)
          Semantics(
            key: const Key('connected-agents-loading'),
            liveRegion: true,
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.settingsConnectedAgentsLoading)),
              ],
            ),
          )
        else if (agents.hasError && grants == null)
          _ConnectedAgentsError(
            retryKey: const Key('connected-agents-retry'),
            onRetry: _load,
          )
        else if (grants?.isEmpty ?? true)
          Text(
            key: const Key('connected-agents-empty'),
            l10n.settingsConnectedAgentsEmpty,
          )
        else ...[
          for (final grant in grants!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.bot),
              title: Text(
                grant.clientName?.trim().isNotEmpty == true
                    ? grant.clientName!.trim()
                    : l10n.settingsConnectedAgentsUnknownClient,
              ),
              subtitle: Text(
                l10n.settingsConnectedAgentsConnectedOn(
                  formatLocalDate(context, grant.connectedAt.toLocal()),
                ),
              ),
              trailing: IconButton(
                key: Key('connected-agent-revoke-${grant.clientId}'),
                tooltip: l10n.settingsConnectedAgentsRevoke,
                onPressed: _revokingClientId == null
                    ? () => _confirmRevoke(grant)
                    : null,
                icon: _revokingClientId == grant.clientId
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.unlink),
              ),
            ),
        ],
        if (agents.hasError && grants != null) ...[
          const SizedBox(height: 8),
          _ConnectedAgentsError(
            retryKey: const Key('connected-agents-retry'),
            onRetry: _load,
          ),
        ],
        if (_revokeError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('connected-agent-revoke-error'),
            liveRegion: true,
            child: Text(
              l10n.settingsConnectedAgentsRevokeError,
              style: TextStyle(color: errorColor),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectedAgentsError extends StatelessWidget {
  const _ConnectedAgentsError({required this.retryKey, required this.onRetry});

  final Key retryKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      key: const Key('connected-agents-error'),
      liveRegion: true,
      child: Row(
        children: [
          Expanded(child: Text(l10n.settingsConnectedAgentsLoadError)),
          ShadButton.ghost(
            height: 48,
            key: retryKey,
            onPressed: onRetry,
            leading: const Icon(LucideIcons.refreshCw),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}

class _AccountDeleteDialog extends ConsumerStatefulWidget {
  const _AccountDeleteDialog({required this.account});

  final AccountClient account;

  @override
  ConsumerState<_AccountDeleteDialog> createState() =>
      _AccountDeleteDialogState();
}

class _AccountDeleteDialogState extends ConsumerState<_AccountDeleteDialog> {
  var _submitting = false;
  Object? _error;

  Future<void> _deleteAccount() async {
    if (_submitting || !await _confirmAccountDeletion() || !mounted) return;
    final db = ref.read(appDatabaseProvider);
    final requestTimeout = ref.read(accountRequestTimeoutProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final response = await widget.account
          .invokeFunction('account-delete', body: const {'confirm': true})
          .timeout(requestTimeout);
      final data = response.data;
      if (data is! Map || data['deleted'] != true) {
        throw StateError('Account deletion was not confirmed by the server.');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error;
        });
      }
      return;
    }

    Object? cleanupError;
    try {
      await db.resetAccountData();
    } on Object catch (error) {
      cleanupError = error;
    }
    try {
      await widget.account.signOut();
    } on Object catch (error) {
      cleanupError ??= error;
    }

    if (!mounted) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          cleanupError == null
              ? l10n.accountDeleted
              : l10n.accountDeletedLocalCleanupError,
        ),
      ),
    );
  }

  Future<bool> _confirmAccountDeletion() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          animationStyle: AnimationStyle(
            duration: AppMotion.duration(context, AppMotion.popup),
            reverseDuration: AppMotion.duration(context, AppMotion.popup),
            curve: AppMotion.curve,
          ),
          builder: (dialogContext) {
            final colors = Theme.of(dialogContext).colorScheme;
            final l10n = dialogContext.l10n;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                scrollable: true,
                constraints: const BoxConstraints(maxWidth: 560),
                key: const Key('account-delete-final-dialog'),
                title: Text(l10n.deleteAccount),
                content: Text(l10n.deleteAccountFinalConfirmation),
                actions: [
                  ShadButton.ghost(
                    height: 48,
                    key: const Key('account-delete-final-cancel-button'),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                  ShadButton.destructive(
                    height: 48,
                    key: const Key('account-delete-final-confirm-button'),
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    leading: const Icon(LucideIcons.trash2),
                    child: Text(l10n.deleteAccount),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('account-delete-dialog'),
        scrollable: true,
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(l10n.deleteAccount),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAccountConfirmation),
            const SizedBox(height: 8),
            ShadButton.ghost(
              key: const Key('account-delete-manage-apple-button'),
              height: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              enabled: !_submitting,
              onPressed: _submitting
                  ? null
                  : () =>
                        unawaited(launchPomodoistExternalUrl(appleAccountUrl)),
              leading: const Icon(LucideIcons.externalLink),
              child: Flexible(child: Text(l10n.manageSignInWithApple)),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                key: const Key('account-delete-error'),
                liveRegion: true,
                child: Text(
                  l10n.deleteAccountError(error),
                  style: TextStyle(color: colors.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          ShadButton.ghost(
            height: 48,
            key: const Key('account-delete-cancel-button'),
            enabled: !_submitting,
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          ShadButton.destructive(
            height: 48,
            key: const Key('account-delete-confirm-button'),
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
            enabled: !_submitting,
            onPressed: _submitting ? null : _deleteAccount,
            leading: _submitting
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onError,
                    ),
                  )
                : const Icon(LucideIcons.trash2),
            child: Text(l10n.deleteAccount),
          ),
        ],
      ),
    );
  }
}

class _AccountErrorCard extends StatelessWidget {
  const _AccountErrorCard({
    required this.error,
    required this.retryKey,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final Key retryKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final feedback = presentAccountAuthFailure(
      l10n,
      classifyAccountAuthFailure(
        error,
        operation: AccountAuthOperation.bootstrap,
      ),
      operation: AccountAuthOperation.bootstrap,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(liveRegion: true, child: Text(feedback.message)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ShadButton.ghost(
                key: retryKey,
                onPressed: onRetry,
                leading: const Icon(LucideIcons.refreshCw),
                child: Text(l10n.commonRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthUnavailableCard extends StatelessWidget {
  const _AuthUnavailableCard({required this.retryKey, required this.onRetry});

  final Key retryKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.authServiceUnavailable,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ShadButton.ghost(
                key: retryKey,
                onPressed: onRetry,
                leading: const Icon(LucideIcons.refreshCw),
                child: Text(context.l10n.commonRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthFailureNoticeCard extends StatelessWidget {
  const _AuthFailureNoticeCard({
    required this.failure,
    required this.onSendNewLink,
  });

  final AccountAuthFailure failure;
  final VoidCallback? onSendNewLink;

  @override
  Widget build(BuildContext context) {
    final feedback = presentAccountAuthFailure(
      context.l10n,
      failure,
      operation: AccountAuthOperation.callback,
    );
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              key: const Key('login-auth-callback-error'),
              liveRegion: true,
              child: Text(
                feedback.message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            if (feedback.recovery == AccountAuthRecovery.sendNewLink &&
                onSendNewLink != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ShadButton.ghost(
                  key: const Key('login-auth-send-new-link'),
                  enabled: onSendNewLink != null,
                  onPressed: onSendNewLink,
                  child: Text(context.l10n.authSendLink),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskListStyleSettings extends ConsumerWidget {
  const _TaskListStyleSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final style = ref.watch(taskListStyleProvider);
    final spacing = ref.watch(taskRowSpacingProvider);
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l10n.settingsTaskListStyle,
          subtitle: l10n.settingsTaskListStyleDescription,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in TaskListStyle.values)
                ChoiceChip(
                  label: Text(
                    option == TaskListStyle.modern
                        ? l10n.settingsTaskListModern
                        : l10n.settingsTaskListClassic,
                  ),
                  selected: style == option,
                  onSelected: (_) async {
                    try {
                      await ref
                          .read(taskListStyleProvider.notifier)
                          .setStyle(option);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.settingsSaveError)),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
        SettingsRow(
          title: l10n.settingsTaskRowSpacing,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in TaskRowSpacing.values)
                ChoiceChip(
                  label: Text(switch (option) {
                    TaskRowSpacing.compact =>
                      l10n.settingsTaskRowSpacingCompact,
                    TaskRowSpacing.comfortable =>
                      l10n.settingsTaskRowSpacingComfortable,
                    TaskRowSpacing.spacious =>
                      l10n.settingsTaskRowSpacingSpacious,
                  }),
                  selected: spacing == option,
                  onSelected: (_) async {
                    try {
                      await ref
                          .read(taskRowSpacingProvider.notifier)
                          .setSpacing(option);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.settingsSaveError)),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DefaultTimedBlockDurationSettings extends ConsumerStatefulWidget {
  const _DefaultTimedBlockDurationSettings();

  @override
  ConsumerState<_DefaultTimedBlockDurationSettings> createState() =>
      _DefaultTimedBlockDurationSettingsState();
}

class _DefaultTimedBlockDurationSettingsState
    extends ConsumerState<_DefaultTimedBlockDurationSettings> {
  static const _presets = [15, 30, 45, 60, 90, 120];

  final _controller = TextEditingController();
  int? _shownMinutes;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _showMinutes(
      ref.read(quickAddDefaultTimedBlockMinutesProvider),
      notify: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.listen<int>(
      quickAddDefaultTimedBlockMinutesProvider,
      (_, next) => _showMinutes(next),
    );
    final minutes = ref.watch(quickAddDefaultTimedBlockMinutesProvider);
    final timeDisplayMode = ref.watch(taskTimeDisplayModeProvider);
    return SettingsGroup(
      children: [
        SettingsRow(
          title: l10n.settingsDefaultTimedBlockTitle,
          subtitle: l10n.settingsDefaultTimedBlockSubtitle,
          controlWidth: 320,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _presets)
                    ChoiceChip(
                      key: ValueKey('settings-default-block-$preset'),
                      label: Text(l10n.durationMinutes(preset)),
                      selected: minutes == preset,
                      onSelected: (_) => _setMinutes(preset),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('settings-default-timed-block-minutes-input'),
                controller: _controller,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l10n.settingsDefaultTimedBlockCustomLabel,
                  suffixText: l10n.minutesSuffix,
                  errorText: _errorText,
                  prefixIcon: const Icon(LucideIcons.clock),
                ),
                onChanged: _saveCustomMinutes,
              ),
            ],
          ),
        ),
        SettingsRow(
          title: l10n.settingsTaskTimeDisplayTitle,
          subtitle: l10n.settingsTaskTimeDisplaySubtitle,
          controlWidth: 320,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('settings-task-time-display-smart'),
                label: Text(l10n.settingsTaskTimeDisplaySmart),
                selected: timeDisplayMode == TaskTimeDisplayMode.smart,
                onSelected: (_) =>
                    _setTimeDisplayMode(TaskTimeDisplayMode.smart),
              ),
              ChoiceChip(
                key: const ValueKey('settings-task-time-display-range'),
                label: Text(l10n.settingsTaskTimeDisplayRange),
                selected: timeDisplayMode == TaskTimeDisplayMode.range,
                onSelected: (_) =>
                    _setTimeDisplayMode(TaskTimeDisplayMode.range),
              ),
              ChoiceChip(
                key: const ValueKey('settings-task-time-display-start-only'),
                label: Text(l10n.settingsTaskTimeDisplayStartOnly),
                selected: timeDisplayMode == TaskTimeDisplayMode.startOnly,
                onSelected: (_) =>
                    _setTimeDisplayMode(TaskTimeDisplayMode.startOnly),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMinutes(int minutes, {bool notify = true}) {
    if (_shownMinutes == minutes) {
      return;
    }
    void update() {
      _shownMinutes = minutes;
      _errorText = null;
      _controller.value = TextEditingValue(
        text: '$minutes',
        selection: TextSelection.collapsed(offset: '$minutes'.length),
      );
    }

    if (notify) {
      setState(update);
    } else {
      update();
    }
  }

  void _setMinutes(int minutes) {
    setState(() => _errorText = null);
    saveSetting(
      context,
      ref
          .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
          .setMinutes(minutes),
    );
  }

  void _saveCustomMinutes(String raw) {
    final minutes = int.tryParse(raw);
    if (minutes == null ||
        minutes < minQuickAddTimedBlockMinutes ||
        minutes > maxQuickAddTimedBlockMinutes) {
      setState(() => _errorText = context.l10n.settingsDefaultTimedBlockError);
      return;
    }
    setState(() => _errorText = null);
    saveSetting(
      context,
      ref
          .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
          .setMinutes(minutes),
    );
  }

  void _setTimeDisplayMode(TaskTimeDisplayMode mode) {
    saveSetting(
      context,
      ref.read(taskTimeDisplayModeProvider.notifier).setMode(mode),
    );
  }
}
