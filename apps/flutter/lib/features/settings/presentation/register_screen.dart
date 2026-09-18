import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/auth/account_auth_feedback.dart';
import '../../../app/auth/email_auth.dart';
import '../../../app/config/account_providers.dart';
import '../../../app/auth/captcha_security.dart';
import '../../../app/auth/captcha_verification.dart';
import '../../../app/platform/native_captcha_broker.dart';
import '../../../app/config/runtime_public_config.dart';
import '../../../app/config/app_l10n.dart';
import 'pomodoist_account_actions.dart';
import 'auth_surfaces.dart';

class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({this.returnTo = '/today', super.key});

  final String returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final account = ref.watch(accountClientProvider);
    final accountBootstrap = ref.watch(accountBootstrapProvider);
    final redirectTo = loginRedirectFor(returnTo);

    return AuthScaffold(
      title: l10n.registerTitle,
      subtitle: l10n.registerSubtitle,
      footer: AuthRouteLink(
        prompt: l10n.registerSignInPrompt,
        action: l10n.registerSignInAction,
        route: authRoute('/login', returnTo),
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
          ? AccountErrorCard(
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
                AuthUnavailableCard(
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
    if (!_canSubmit || _emailSent) return;
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
        token = await broker.requestToken(locale: context.l10n.localeName);
      } else {
        token = null;
      }
      final result = await ref
          .read(emailAuthProvider)
          .submit(
            action: EmailAuthAction.signUp,
            email: _emailController.text,
            password: _passwordController.text,
            redirectTo: widget.redirectTo,
            captchaToken: token,
          );
      if (result == null) return;
      TextInput.finishAutofillContext(shouldSave: true);
      if (!mounted) {
        return;
      }
      if (result == EmailAuthResult.signedIn) {
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
      case AccountAuthRecovery.resendConfirmation:
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
