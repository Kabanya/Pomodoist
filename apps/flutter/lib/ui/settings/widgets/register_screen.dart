import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/ui/auth/widgets/account_auth_feedback.dart';
import 'package:pomodoist/domain/models/account/email_auth.dart';
import 'package:pomodoist/domain/models/account/captcha_security.dart';
import 'package:pomodoist/ui/auth/widgets/captcha_verification.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/settings/widgets/pomodoist_account_actions.dart';
import 'package:pomodoist/ui/settings/widgets/auth_surfaces.dart';
import 'package:pomodoist/ui/settings/view_models/auth_view_model.dart';

class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({this.returnTo = '/today', super.key});

  final String returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final auth = ref.watch(authViewModelProvider);
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
      child: !auth.available && auth.loading
          ? const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            )
          : !auth.available && auth.bootstrapError != null
          ? AccountErrorCard(
              key: const Key('register-account-error'),
              error: auth.bootstrapError!,
              retryKey: const Key('register-account-retry'),
              onRetry: () =>
                  unawaited(ref.read(authViewModelProvider.notifier).retry()),
            )
          : !auth.available
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthUnavailableCard(
                  retryKey: const Key('register-account-retry'),
                  onRetry: () => unawaited(
                    ref.read(authViewModelProvider.notifier).retry(),
                  ),
                ),
                const SizedBox(height: 12),
                _RegisterForm(
                  accountAvailable: false,
                  redirectTo: redirectTo,
                  returnTo: returnTo,
                ),
              ],
            )
          : _RegisterForm(
              accountAvailable: true,
              redirectTo: redirectTo,
              returnTo: returnTo,
            ),
    );
  }
}

class _RegisterForm extends ConsumerStatefulWidget {
  const _RegisterForm({
    required this.accountAvailable,
    required this.redirectTo,
    required this.returnTo,
  });

  final bool accountAvailable;
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
  late final CaptchaTokenController _captcha;
  Timer? _slowTimer;
  bool _takingLonger = false;

  static const _slowThreshold = Duration(seconds: 30);

  bool get _canSubmit => widget.accountAvailable && !_submitting;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authViewModelProvider);
    _captcha = CaptchaTokenController(required: kIsWeb && auth.captchaEnabled);
    _emailController.addListener(_emailChanged);
    _passwordController.addListener(_passwordChanged);
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
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
    final auth = ref.watch(authViewModelProvider);
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
              if (widget.accountAvailable)
                PomodoistSocialSignInButton(
                  provider: PomodoistSocialProvider.apple,
                  redirectTo: widget.redirectTo,
                  label: l10n.accountApple,
                  onSignedIn: () => context.go(widget.returnTo),
                ),
              const SizedBox(height: 8),
              if (widget.accountAvailable)
                PomodoistSocialSignInButton(
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
              if (kIsWeb && auth.captchaEnabled) ...[
                const SizedBox(height: 16),
                CaptchaVerification(
                  siteKey: auth.turnstileSiteKey,
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
    if (!widget.accountAvailable) {
      return;
    }
    final emailFailure = validateAccountEmail(_emailController.text);
    final passwordFailure = validateAccountPassword(_passwordController.text);
    if (emailFailure != null || passwordFailure != null) {
      _showFailure(emailFailure ?? passwordFailure!);
      return;
    }
    final auth = ref.read(authViewModelProvider);
    if (kIsWeb && auth.captchaEnabled && !_captcha.canSubmit) {
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
      } else if (auth.captchaEnabled) {
        token = await ref
            .read(authViewModelProvider.notifier)
            .requestNativeCaptcha(context.l10n.localeName);
      } else {
        token = null;
      }
      final result = await ref
          .read(authViewModelProvider.notifier)
          .submitEmail(
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
          error is AccountAuthFailure
              ? error
              : ref
                    .read(authViewModelProvider.notifier)
                    .classify(error, operation: AccountAuthOperation.signUp),
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
        if (!widget.accountAvailable) return;
        _passwordController.clear();
        setState(() => _feedback = null);
        unawaited(
          showPomodoistEmailAuthDialog(
            context: context,
            redirectTo: widget.redirectTo,
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
