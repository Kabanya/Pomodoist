import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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
import '../../../app/app_theme_mode.dart';
import '../../../app/theme/app_theme.dart';
import '../../focus/presentation/focus_view_mode.dart';
import '../../focus/presentation/focus_screen.dart';
import '../../integrations/google_calendar/presentation/google_calendar_settings_screen.dart';
import '../../onboarding/onboarding_gate.dart';
import 'account_sign_out_button.dart';
import 'app_info_card.dart';
import 'csv_task_import_card.dart';
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
    final guestStartup = ref.watch(guestDataStartupProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('guest-login-scroll'),
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.loginTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.onboardingAccountSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    authContent,
                    const SizedBox(height: 12),
                    footer,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            guestStartup.when(
              data: (_) => const FocusScreen(
                embedded: true,
                fixedViewMode: FocusViewMode.full,
              ),
              loading: () => const _GuestTimerLoading(),
              error: (error, _) => _GuestTimerError(
                error: error,
                onRetry: () => ref.invalidate(guestDataStartupProvider),
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
          OutlinedButton(
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
      children: [
        Text(prompt),
        OutlinedButton(
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
              const Icon(Icons.mark_email_read_outlined, size: 40),
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
                  child: TextButton(
                    key: const Key('register-auth-recovery'),
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
                      const Icon(Icons.hourglass_top, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l10n.operationTakingLonger)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('register-submit-button'),
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? _takingLonger
                          ? const Icon(Icons.hourglass_top, size: 18)
                          : const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
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

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({this.signOutOverride, super.key});

  final Future<void> Function()? signOutOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final timerVisualStyle = ref.watch(focusTimerVisualStyleProvider);
    ref.watch(accountAuthStateProvider);
    final account = ref.watch(accountClientProvider);
    final accountBootstrap = ref.watch(accountBootstrapProvider);
    final accountOverview = ref.watch(accountOverviewProvider);
    final accountConfigured = ref.watch(accountConfiguredProvider);
    final signedInAccount = account?.currentUserId == null ? null : account;
    final hasAccountOverview = accountOverview.asData?.value != null;
    final reengagementEnabled = ref.watch(
      reengagementNotificationsEnabledProvider,
    );
    final focusCompletionCelebrationEnabled = ref.watch(
      focusCompletionCelebrationEnabledProvider,
    );
    final colors = context.appColors;
    return SafeArea(
      child: ListView(
        key: const Key('settings-list'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l10n.settingsTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (account == null && accountBootstrap.hasError)
            _AccountErrorCard(
              key: const Key('account-bootstrap-error'),
              error: accountBootstrap.error!,
              retryKey: const Key('account-bootstrap-retry'),
              onRetry: () {
                unawaited(
                  ref
                      .read(accountBootstrapProvider.notifier)
                      .retry()
                      .whenComplete(
                        () => ref.invalidate(accountOverviewProvider),
                      ),
                );
              },
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!accountConfigured)
                  _AuthUnavailableCard(
                    retryKey: const Key('account-unavailable-retry'),
                    onRetry: () => unawaited(
                      ref
                          .read(accountBootstrapProvider.notifier)
                          .retry()
                          .whenComplete(
                            () => ref.invalidate(accountOverviewProvider),
                          ),
                    ),
                  )
                else
                  accountOverview.when(
                    data: (overview) => AccountOverviewPanel(
                      overview: overview,
                      configured: true,
                      onRefresh: () => ref.invalidate(accountOverviewProvider),
                      actions: pomodoistAccountSignInActions(
                        context: context,
                        account: account,
                        redirectTo: pomodoistLoginRedirect,
                        config: ref.read(runtimePublicConfigProvider),
                        nativeCaptchaCallbacks: ref
                            .read(nativeLinkCoordinatorProvider)
                            ?.captchaCallbacks,
                      ),
                    ),
                    loading: () => const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator(),
                      ),
                    ),
                    error: (error, _) => _AccountErrorCard(
                      key: const Key('account-overview-error'),
                      error: error,
                      retryKey: const Key('account-overview-retry'),
                      onRetry: () => ref.invalidate(accountOverviewProvider),
                    ),
                  ),
                if (hasAccountOverview || signedInAccount != null)
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      AccountSignOutButton(
                        key: const Key('account-sign-out-button'),
                        onSignOut:
                            signOutOverride ??
                            () async {
                              await account?.signOut();
                            },
                        label: l10n.signOut,
                      ),
                    ],
                  ),
              ],
            ),
          if (accountConfigured && signedInAccount != null) ...[
            const SizedBox(height: 12),
            _ConnectedAgentsSection(
              key: ValueKey(signedInAccount.currentUserId),
              account: signedInAccount,
            ),
          ],
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LaunchOfferPaywall(),
            ),
          ),
          const SizedBox(height: 12),
          if (isCsvTaskImportSupported()) ...[
            const CsvTaskImportCard(),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsLanguageTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsLanguageSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<AppLanguage>(
                    key: const Key('settings-language-select'),
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
                        ref
                            .read(appLanguageProvider.notifier)
                            .setLanguage(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              key: const Key('settings-reengagement-notifications-switch'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(l10n.settingsReturnRemindersTitle),
              subtitle: Text(l10n.settingsReturnRemindersSubtitle),
              value: reengagementEnabled,
              onChanged: (value) {
                ref
                    .read(reengagementNotificationsEnabledProvider.notifier)
                    .setEnabled(value);
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsThemeTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsThemeSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<AppThemeMode>(
                    key: const Key('settings-theme-mode-select'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AppThemeMode.system,
                        icon: const Icon(Icons.brightness_auto_outlined),
                        label: Text(l10n.settingsThemeSystem),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.light,
                        icon: const Icon(Icons.light_mode_outlined),
                        label: Text(l10n.settingsThemeLight),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_outlined),
                        label: Text(l10n.settingsThemeDark),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) {
                      ref
                          .read(appThemeModeProvider.notifier)
                          .setThemeMode(selection.single);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _DefaultTimedBlockDurationSettings(),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsTimerVisualTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsTimerVisualSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<FocusTimerVisualStyle>(
                    key: const Key('settings-timer-visual-style-select'),
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
                    selected: {timerVisualStyle},
                    onSelectionChanged: (selection) {
                      ref
                          .read(focusTimerVisualStyleProvider.notifier)
                          .setStyle(selection.single);
                    },
                  ),
                ],
              ),
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.navIntegrations,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    const GoogleCalendarSettingsScreen(embedded: true),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            key: const Key('settings-shortcuts-button'),
            child: ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(l10n.settingsShortcutsTitle),
              subtitle: Text(l10n.settingsShortcutsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/shortcuts'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              key: const Key('settings-focus-completion-celebration-switch'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              secondary: const Icon(Icons.celebration_outlined),
              title: Text(l10n.settingsFocusCompletionCelebrationTitle),
              subtitle: Text(l10n.settingsFocusCompletionCelebrationSubtitle),
              value: focusCompletionCelebrationEnabled,
              onChanged: (value) {
                ref
                    .read(focusCompletionCelebrationEnabledProvider.notifier)
                    .setEnabled(value);
              },
            ),
          ),
          const SizedBox(height: 12),
          const SettingsAppInfoCard(key: Key('settings-app-info-section')),
          if (signedInAccount != null) ...[
            const SizedBox(height: 12),
            Align(
              key: const Key('account-delete-section'),
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('account-delete-button'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      _AccountDeleteDialog(account: signedInAccount),
                ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(l10n.deleteAccount),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectedAgentsSection extends StatefulWidget {
  const _ConnectedAgentsSection({required this.account, super.key});

  final AccountClient account;

  @override
  State<_ConnectedAgentsSection> createState() =>
      _ConnectedAgentsSectionState();
}

class _ConnectedAgentsSectionState extends State<_ConnectedAgentsSection> {
  List<AccountOAuthGrant>? _grants;
  Object? _loadError;
  Object? _revokeError;
  String? _revokingClientId;
  BuildContext? _confirmationContext;
  late AccountClient _account;
  String? _userId;
  var _loading = true;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _userId = widget.account.currentUserId;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_ConnectedAgentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userId = widget.account.currentUserId;
    if (!identical(_account, widget.account) || _userId != userId) {
      _dismissConfirmation();
      _account = widget.account;
      _userId = userId;
      _loadGeneration += 1;
      _grants = null;
      _loadError = null;
      _revokeError = null;
      _revokingClientId = null;
      unawaited(_load());
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

  Future<void> _load() async {
    final account = widget.account;
    final userId = account.currentUserId;
    if (!_isCurrent(account, userId)) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final grants = await account.listOAuthGrants();
      if (!_isCurrent(account, userId) || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _grants = grants;
        _loading = false;
      });
    } on Object catch (error) {
      if (!_isCurrent(account, userId) || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

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
          builder: (dialogContext) {
            _confirmationContext = dialogContext;
            return AlertDialog(
              key: const Key('connected-agent-revoke-dialog'),
              title: Text(l10n.settingsConnectedAgentsRevokeConfirmTitle),
              content: Text(
                l10n.settingsConnectedAgentsRevokeConfirmMessage(clientName),
              ),
              actions: [
                TextButton(
                  key: const Key('connected-agent-revoke-cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
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
      await account.revokeOAuthGrant(clientId);
      if (!_isCurrent(account, userId)) return;
      await _load();
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
    final grants = _grants;
    return Card(
      key: const Key('connected-agents-section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settingsConnectedAgentsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_loading && grants == null)
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
            else if (_loadError != null && grants == null)
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
              if (_loading) const LinearProgressIndicator(),
              for (final grant in grants!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smart_toy_outlined),
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
                        : const Icon(Icons.link_off_outlined),
                  ),
                ),
            ],
            if (_loadError != null && grants != null) ...[
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
        ),
      ),
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
          TextButton.icon(
            key: retryKey,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.commonRetry),
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
          builder: (dialogContext) {
            final colors = Theme.of(dialogContext).colorScheme;
            final l10n = dialogContext.l10n;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                key: const Key('account-delete-final-dialog'),
                title: Text(l10n.deleteAccount),
                content: Text(l10n.deleteAccountFinalConfirmation),
                actions: [
                  TextButton(
                    key: const Key('account-delete-final-cancel-button'),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton.icon(
                    key: const Key('account-delete-final-confirm-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text(l10n.deleteAccount),
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
        title: Text(l10n.deleteAccount),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAccountConfirmation),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('account-delete-manage-apple-button'),
              onPressed: _submitting
                  ? null
                  : () =>
                        unawaited(launchPomodoistExternalUrl(appleAccountUrl)),
              icon: const Icon(Icons.open_in_new),
              label: Text(l10n.manageSignInWithApple),
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
          TextButton(
            key: const Key('account-delete-cancel-button'),
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton.icon(
            key: const Key('account-delete-confirm-button'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: _submitting ? null : _deleteAccount,
            icon: _submitting
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onError,
                    ),
                  )
                : const Icon(Icons.delete_forever_outlined),
            label: Text(l10n.deleteAccount),
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
              child: TextButton.icon(
                key: retryKey,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.commonRetry),
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
              child: TextButton.icon(
                key: retryKey,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.commonRetry),
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
                child: TextButton(
                  key: const Key('login-auth-send-new-link'),
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
    final colors = context.appColors;
    ref.listen<int>(
      quickAddDefaultTimedBlockMinutesProvider,
      (_, next) => _showMinutes(next),
    );
    final minutes = ref.watch(quickAddDefaultTimedBlockMinutesProvider);
    final timeDisplayMode = ref.watch(taskTimeDisplayModeProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsDefaultTimedBlockTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsDefaultTimedBlockSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
            ),
            const SizedBox(height: 14),
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
                prefixIcon: const Icon(Icons.schedule_outlined),
              ),
              onChanged: _saveCustomMinutes,
            ),
            const SizedBox(height: 18),
            Text(
              l10n.settingsTaskTimeDisplayTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsTaskTimeDisplaySubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
            ),
            const SizedBox(height: 10),
            Wrap(
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
          ],
        ),
      ),
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
    ref
        .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
        .setMinutes(minutes);
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
    ref
        .read(quickAddDefaultTimedBlockMinutesProvider.notifier)
        .setMinutes(minutes);
  }

  void _setTimeDisplayMode(TaskTimeDisplayMode mode) {
    ref.read(taskTimeDisplayModeProvider.notifier).setMode(mode);
  }
}
