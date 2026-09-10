import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadButton, ShadInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/account_auth_feedback.dart';
import '../../../app/account_providers.dart';
import '../../../app/email_auth.dart';
import '../../../app/password_recovery.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/app_l10n.dart';
import '../../../app/captcha_security.dart';
import '../../../app/captcha_verification.dart';
import '../../../app/native_captcha_broker.dart';
import '../../../app/runtime_public_config.dart';

List<Widget> pomodoistAccountSignInActions({
  required BuildContext context,
  required AccountClient? account,
  required String redirectTo,
  required RuntimePublicConfig config,
  required Stream<Uri>? nativeCaptchaCallbacks,
  VoidCallback? onSignedIn,
  String appleLabel = 'Apple',
  String googleLabel = 'Google',
  String emailLabel = 'Email',
}) {
  if (account == null || account.currentUserId != null) return const [];
  return [
    PomodoistSocialSignInButton(
      account: account,
      provider: PomodoistSocialProvider.apple,
      redirectTo: redirectTo,
      onSignedIn: onSignedIn,
      label: appleLabel,
    ),
    PomodoistSocialSignInButton(
      account: account,
      provider: PomodoistSocialProvider.google,
      redirectTo: redirectTo,
      onSignedIn: onSignedIn,
      label: googleLabel,
    ),
    ShadButton.outline(
      onPressed: () => showPomodoistEmailAuthDialog(
        context: context,
        account: account,
        redirectTo: redirectTo,
        onSignedIn: onSignedIn,
        config: config,
        nativeCaptchaCallbacks: nativeCaptchaCallbacks,
      ),
      leading: const Icon(LucideIcons.mail),
      child: Text(emailLabel),
    ),
  ];
}

String pomodoistAccountFailureMessage(BuildContext context, Object error) {
  return presentAccountAuthFailure(
    context.l10n,
    classifyAccountAuthFailure(
      error,
      operation: AccountAuthOperation.bootstrap,
    ),
    operation: AccountAuthOperation.bootstrap,
  ).message;
}

Future<void> showPomodoistEmailAuthDialog({
  required BuildContext context,
  required AccountClient account,
  required String redirectTo,
  required RuntimePublicConfig config,
  required Stream<Uri>? nativeCaptchaCallbacks,
  String initialEmail = '',
  bool resetPassword = false,
  VoidCallback? onSignedIn,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
      reverseDuration: AppMotion.duration(context, AppMotion.popup),
      curve: AppMotion.curve,
    ),
    builder: (_) => _PomodoistEmailAuthDialog(
      account: account,
      redirectTo: redirectTo,
      onSignedIn: onSignedIn,
      config: config,
      nativeCaptchaCallbacks: nativeCaptchaCallbacks,
      initialEmail: initialEmail,
      resetPassword: resetPassword,
    ),
  );
}

enum PomodoistSocialProvider { apple, google }

class PomodoistSocialSignInButton extends StatefulWidget {
  const PomodoistSocialSignInButton({
    required this.account,
    required this.provider,
    required this.redirectTo,
    required this.label,
    this.onSignedIn,
    super.key,
  });

  final AccountClient account;
  final PomodoistSocialProvider provider;
  final String redirectTo;
  final String label;
  final VoidCallback? onSignedIn;

  @override
  State<PomodoistSocialSignInButton> createState() =>
      _PomodoistSocialSignInButtonState();
}

class _PomodoistSocialSignInButtonState
    extends State<PomodoistSocialSignInButton> {
  bool _submitting = false;

  AccountAuthOperation get _operation => switch (widget.provider) {
    PomodoistSocialProvider.apple => AccountAuthOperation.apple,
    PomodoistSocialProvider.google => AccountAuthOperation.google,
  };

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      switch (widget.provider) {
        case PomodoistSocialProvider.apple:
          await widget.account.signInWithApple(redirectTo: widget.redirectTo);
        case PomodoistSocialProvider.google:
          await widget.account.signInWithGoogle(redirectTo: widget.redirectTo);
      }
      if (mounted && widget.account.currentUserId != null) {
        widget.onSignedIn?.call();
      }
    } on Object catch (error) {
      if (!mounted) return;
      final failure = classifyAccountAuthFailure(error, operation: _operation);
      if (failure.isCancelled) return;
      final feedback = presentAccountAuthFailure(
        context.l10n,
        failure,
        operation: _operation,
        provider: widget.label,
      );
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(feedback.message),
          action: feedback.recovery == AccountAuthRecovery.retry
              ? SnackBarAction(
                  label: context.l10n.commonRetry,
                  onPressed: () => unawaited(_submit()),
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (widget.provider) {
      PomodoistSocialProvider.apple => Icons.apple,
      PomodoistSocialProvider.google => LucideIcons.circleUserRound,
    };
    return ShadButton.outline(
      enabled: !_submitting,
      onPressed: _submitting ? null : _submit,
      leading: _submitting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      child: Text(widget.label),
    );
  }
}

enum _EmailAction {
  magicLink,
  signIn,
  signUp,
  resetPassword,
  resendConfirmation,
}

const _accountOperationSlowThreshold = Duration(seconds: 30);

class _PomodoistEmailAuthDialog extends ConsumerStatefulWidget {
  const _PomodoistEmailAuthDialog({
    required this.account,
    required this.redirectTo,
    required this.onSignedIn,
    required this.config,
    required this.nativeCaptchaCallbacks,
    required this.initialEmail,
    required this.resetPassword,
  });

  final AccountClient account;
  final String redirectTo;
  final VoidCallback? onSignedIn;
  final RuntimePublicConfig config;
  final Stream<Uri>? nativeCaptchaCallbacks;
  final String initialEmail;
  final bool resetPassword;

  @override
  ConsumerState<_PomodoistEmailAuthDialog> createState() =>
      _PomodoistEmailAuthDialogState();
}

class _PomodoistEmailAuthDialogState
    extends ConsumerState<_PomodoistEmailAuthDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  _EmailAction _mode = _EmailAction.signIn;
  late final CaptchaTokenController _captcha = CaptchaTokenController(
    required: kIsWeb && widget.config.turnstileSiteKey.isNotEmpty,
  );
  NativeCaptchaBroker? _nativeBroker;
  Timer? _slowTimer;
  bool _submitting = false;
  bool _resetEmailSent = false;
  bool _registrationEmailSent = false;
  bool _takingLonger = false;
  AccountAuthFeedback? _feedback;
  _EmailAction? _lastAction;

  bool get _canSubmit => !_submitting && !_registrationEmailSent;

  @override
  void initState() {
    super.initState();
    _mode = widget.resetPassword
        ? _EmailAction.resetPassword
        : _EmailAction.signIn;
    _email.text = widget.initialEmail.trim();
    _email.addListener(_emailChanged);
    _password.addListener(_passwordChanged);
    if (!kIsWeb && widget.config.turnstileSiteKey.isNotEmpty) {
      final callbacks = widget.nativeCaptchaCallbacks;
      if (callbacks != null) {
        _nativeBroker = NativeCaptchaBroker(uriStream: callbacks);
      }
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _nativeBroker?.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _emailChanged() {
    if (_feedback?.field == AccountAuthField.email) _feedback = null;
    if (mounted) setState(() {});
  }

  void _passwordChanged() {
    if (_feedback?.field == AccountAuthField.password) _feedback = null;
    if (mounted) setState(() {});
  }

  void _changeMode(_EmailAction mode) {
    if (_submitting) return;
    _password.clear();
    setState(() {
      _mode = mode;
      _feedback = null;
      _resetEmailSent = false;
      _registrationEmailSent = false;
    });
    _emailFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.listen(passwordRecoveryProvider, (_, recovery) {
      if (recovery.needsRoute &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
    if (_registrationEmailSent) {
      return Dialog(
        constraints: const BoxConstraints(maxWidth: 440),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _AuthSurface(
          onClose: () => Navigator.of(context).pop(),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppMotion.duration(context, AppMotion.state),
            curve: AppMotion.curve,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Icon(
                      LucideIcons.mailCheck,
                      size: 32,
                      color: context.appColors.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.registerCheckEmailTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.registerCheckEmailMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(_email.text.trim()),
                  const SizedBox(height: 24),
                  ShadButton(
                    autofocus: true,
                    onPressed: () => _changeMode(_EmailAction.signIn),
                    child: Text(l10n.authBackToSignIn),
                  ),
                  ShadButton.ghost(
                    onPressed: () => _changeMode(_EmailAction.resetPassword),
                    child: Text(l10n.authForgotPassword),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final feedback = _feedback;
    final resetting = _mode == _EmailAction.resetPassword;
    final signingIn = _mode == _EmailAction.signIn;
    return PopScope(
      canPop: !_submitting || _takingLonger,
      child: Dialog(
        constraints: const BoxConstraints(maxWidth: 440),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _AuthSurface(
          onClose: _submitting && !_takingLonger
              ? null
              : () => Navigator.of(context).pop(),
          child: AutofillGroup(
            key: ValueKey(_mode),
            onDisposeAction: AutofillContextAction.cancel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resetting) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ShadButton.ghost(
                      enabled: !_submitting,
                      onPressed: () => _changeMode(_EmailAction.signIn),
                      leading: const Icon(LucideIcons.arrowLeft, size: 16),
                      child: Text(l10n.authBackToSignIn),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                AnimatedSwitcher(
                  duration: AppMotion.duration(context, AppMotion.state),
                  switchInCurve: AppMotion.curve,
                  child: Align(
                    key: ValueKey((_mode, _resetEmailSent)),
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      resetting
                          ? (_resetEmailSent
                                ? l10n.authResetEmailSentTitle
                                : l10n.authResetTitle)
                          : signingIn
                          ? l10n.authWelcomeTitle
                          : l10n.registerTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  resetting
                      ? (_resetEmailSent
                            ? l10n.authResetEmailSent
                            : l10n.authResetDescription)
                      : signingIn
                      ? l10n.authWelcomeDescription
                      : l10n.registerSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 24),
                if (_resetEmailSent) ...[
                  Text(
                    _email.text.trim(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ShadButton.ghost(
                      enabled: !_submitting,
                      onPressed: () => _changeMode(_EmailAction.resetPassword),
                      child: Text(l10n.authResetEditEmail),
                    ),
                  ),
                ] else ...[
                  Semantics(
                    label: l10n.accountEmail,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.accountEmail,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        ShadInput(
                          key: const Key('account-email-field'),
                          controller: _email,
                          focusNode: _emailFocus,
                          enabled: !_submitting,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: resetting
                              ? TextInputAction.done
                              : TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          autocorrect: false,
                          autofocus: true,
                          placeholder: const Text('name@example.com'),
                          onSubmitted: (_) => resetting
                              ? unawaited(_submit(_mode))
                              : _passwordFocus.requestFocus(),
                        ),
                        if (feedback?.field == AccountAuthField.email)
                          _AuthError(feedback!.message),
                      ],
                    ),
                  ),
                  if (!resetting) ...[
                    const SizedBox(height: 16),
                    _AuthPasswordField(
                      fieldKey: const Key('account-password-field'),
                      label: l10n.registerPassword,
                      controller: _password,
                      focusNode: _passwordFocus,
                      enabled: !_submitting,
                      newPassword: !signingIn,
                      error: feedback?.field == AccountAuthField.password
                          ? feedback?.message
                          : null,
                      onSubmitted: () => unawaited(_submit(_mode)),
                      labelAction: signingIn
                          ? ShadButton.ghost(
                              key: const Key('account-forgot-password'),
                              enabled: !_submitting,
                              onPressed: () =>
                                  _changeMode(_EmailAction.resetPassword),
                              child: Text(l10n.authForgotPassword),
                            )
                          : null,
                    ),
                  ],
                ],
                if (kIsWeb && widget.config.turnstileSiteKey.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  CaptchaVerification(
                    siteKey: widget.config.turnstileSiteKey,
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
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      feedback.message,
                      key: const Key('account-auth-error'),
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
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ShadButton.ghost(
                      key: const Key('account-auth-recovery'),
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
                  const SizedBox(height: 8),
                  Semantics(
                    key: const Key('account-auth-slow'),
                    liveRegion: true,
                    child: Row(
                      children: [
                        const Icon(LucideIcons.hourglass, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(context.l10n.operationTakingLonger),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ShadButton(
                  key: const Key('account-auth-submit'),
                  width: double.infinity,
                  enabled: _canSubmit,
                  onPressed: _canSubmit ? () => _submit(_mode) : null,
                  leading: _submitting
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.appColors.onAccent,
                          ),
                        )
                      : null,
                  child: Text(
                    resetting
                        ? (_resetEmailSent
                              ? l10n.authResetSendAgain
                              : l10n.authSendLink)
                        : signingIn
                        ? l10n.authSignInAction
                        : l10n.registerSubmit,
                  ),
                ),
                if (signingIn) ...[
                  const SizedBox(height: 8),
                  ShadButton.outline(
                    width: double.infinity,
                    enabled: _canSubmit,
                    onPressed: _canSubmit
                        ? () => _submit(_EmailAction.magicLink)
                        : null,
                    leading: const Icon(LucideIcons.mail, size: 16),
                    child: Text(l10n.authSignInWithLink),
                  ),
                ],
                if (!resetting) ...[
                  const SizedBox(height: 24),
                  Divider(height: 1, color: context.appColors.border),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        signingIn ? l10n.authNoAccount : l10n.authHaveAccount,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appColors.secondaryText,
                        ),
                      ),
                      ShadButton.ghost(
                        key: const Key('account-auth-mode'),
                        enabled: !_submitting,
                        onPressed: () => _changeMode(
                          signingIn ? _EmailAction.signUp : _EmailAction.signIn,
                        ),
                        child: Text(
                          signingIn
                              ? l10n.registerSubmit
                              : l10n.authSignInAction,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(_EmailAction action) async {
    if (!_canSubmit) return;
    final emailFailure = validateAccountEmail(_email.text);
    final passwordFailure =
        action == _EmailAction.magicLink ||
            action == _EmailAction.resetPassword ||
            action == _EmailAction.resendConfirmation
        ? null
        : validateAccountPassword(_password.text);
    if (emailFailure != null || passwordFailure != null) {
      _showFailure(
        emailFailure ?? passwordFailure!,
        operation: _operationFor(action),
      );
      return;
    }
    if (kIsWeb &&
        widget.config.turnstileSiteKey.isNotEmpty &&
        !_captcha.canSubmit) {
      _showFailure(
        const AccountAuthFailure(
          AccountAuthFailureKind.captchaRequired,
          field: AccountAuthField.captcha,
          recovery: AccountAuthRecovery.retryCaptcha,
        ),
        operation: AccountAuthOperation.captcha,
      );
      return;
    }
    setState(() {
      _submitting = true;
      _takingLonger = false;
      _feedback = null;
      _lastAction = action;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(_accountOperationSlowThreshold, () {
      if (mounted && _submitting) setState(() => _takingLonger = true);
    });
    var webRequestStarted = false;
    try {
      final String? token;
      if (kIsWeb) {
        token = _captcha.beginRequest();
        webRequestStarted = true;
      } else if (widget.config.turnstileSiteKey.isNotEmpty) {
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
      if (!mounted) return;
      var signedIn = false;
      switch (action) {
        case _EmailAction.resetPassword:
          final recovery = ref.read(passwordRecoveryProvider);
          final sent = await recovery.requestEmail(
            _email.text,
            redirectTo: passwordRecoveryRedirect(widget.redirectTo),
            captchaToken: token,
          );
          if (!mounted) return;
          if (sent) {
            setState(() => _resetEmailSent = true);
          } else if (recovery.failure case final failure?) {
            _showFailure(
              failure,
              operation: AccountAuthOperation.passwordReset,
            );
          }
          return;
        case _EmailAction.magicLink:
        case _EmailAction.signIn:
        case _EmailAction.signUp:
        case _EmailAction.resendConfirmation:
          final result = await ref
              .read(emailAuthProvider)
              .submit(
                action: switch (action) {
                  _EmailAction.magicLink => EmailAuthAction.magicLink,
                  _EmailAction.signIn => EmailAuthAction.signIn,
                  _EmailAction.signUp => EmailAuthAction.signUp,
                  _EmailAction.resendConfirmation =>
                    EmailAuthAction.resendConfirmation,
                  _EmailAction.resetPassword => throw StateError(
                    'Separate recovery flow',
                  ),
                },
                email: _email.text,
                password: _password.text,
                redirectTo: widget.redirectTo,
                captchaToken: token,
              );
          if (result == null) return;
          signedIn = result == EmailAuthResult.signedIn;
      }
      if (action == _EmailAction.signIn || action == _EmailAction.signUp) {
        TextInput.finishAutofillContext(shouldSave: true);
      }
      if (!mounted) return;
      if ((action == _EmailAction.signUp ||
              action == _EmailAction.resendConfirmation) &&
          !signedIn) {
        FocusScope.of(context).unfocus();
        _password.clear();
        setState(() => _registrationEmailSent = true);
        return;
      }
      final successMessage = switch (action) {
        _EmailAction.magicLink => context.l10n.authMagicLinkSent,
        _EmailAction.resetPassword => context.l10n.authResetEmailSent,
        _EmailAction.signIn => context.l10n.authSignedIn,
        _EmailAction.signUp => context.l10n.authAccountCreated,
        _EmailAction.resendConfirmation =>
          context.l10n.registerCheckEmailMessage,
      };
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      if (signedIn) widget.onSignedIn?.call();
      messenger?.showSnackBar(SnackBar(content: Text(successMessage)));
    } on Object catch (error) {
      if (mounted) {
        _showFailure(
          classifyAccountAuthFailure(error, operation: _operationFor(action)),
          operation: _operationFor(action),
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

  AccountAuthOperation _operationFor(_EmailAction action) => switch (action) {
    _EmailAction.magicLink => AccountAuthOperation.magicLink,
    _EmailAction.resetPassword => AccountAuthOperation.passwordReset,
    _EmailAction.signIn => AccountAuthOperation.passwordSignIn,
    _EmailAction.signUp => AccountAuthOperation.signUp,
    _EmailAction.resendConfirmation => AccountAuthOperation.confirmationEmail,
  };

  void _showFailure(
    AccountAuthFailure failure, {
    required AccountAuthOperation operation,
  }) {
    if (!mounted || failure.isCancelled) return;
    final feedback = presentAccountAuthFailure(
      context.l10n,
      failure,
      operation: operation,
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
        unawaited(_submit(_lastAction ?? _mode));
      case AccountAuthRecovery.retryCaptcha:
        if (kIsWeb) {
          _captcha.reset();
          setState(() => _feedback = null);
        } else {
          unawaited(_submit(_lastAction ?? _mode));
        }
      case AccountAuthRecovery.switchToSignIn:
        _password.clear();
        setState(() {
          _mode = _EmailAction.signIn;
          _feedback = null;
        });
        _passwordFocus.requestFocus();
      case AccountAuthRecovery.sendNewLink:
        if (_mode == _EmailAction.resetPassword) {
          unawaited(_submit(_EmailAction.resetPassword));
          return;
        }
        setState(() {
          _mode = _EmailAction.signIn;
          _feedback = null;
        });
        unawaited(_submit(_EmailAction.magicLink));
      case AccountAuthRecovery.resendConfirmation:
        unawaited(_submit(_EmailAction.resendConfirmation));
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

class _AuthSurface extends StatelessWidget {
  const _AuthSurface({required this.onClose, required this.child});

  final VoidCallback? onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.timer,
                size: 20,
                color: context.appColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pomodoist',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: context.l10n.commonClose,
                onPressed: onClose,
                icon: const Icon(LucideIcons.x, size: 18),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}

class _AuthError extends StatelessWidget {
  const _AuthError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.appColors.error),
      ),
    ),
  );
}

class _AuthPasswordField extends StatefulWidget {
  const _AuthPasswordField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.newPassword,
    required this.onSubmitted,
    this.fieldKey,
    this.labelAction,
    this.error,
    this.autofocus = false,
    this.textInputAction = TextInputAction.done,
  });
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool newPassword;
  final VoidCallback onSubmitted;
  final Key? fieldKey;
  final Widget? labelAction;
  final String? error;
  final bool autofocus;
  final TextInputAction textInputAction;

  @override
  State<_AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<_AuthPasswordField> {
  var _visible = false;

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
            ?widget.labelAction,
          ],
        ),
        const SizedBox(height: 8),
        ShadInput(
          key: widget.fieldKey,
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: !_visible,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: [
            widget.newPassword
                ? AutofillHints.newPassword
                : AutofillHints.password,
          ],
          textInputAction: widget.textInputAction,
          onSubmitted: (_) => widget.onSubmitted(),
          trailing: IconButton(
            onPressed: widget.enabled
                ? () => setState(() => _visible = !_visible)
                : null,
            tooltip: _visible
                ? context.l10n.authHidePassword
                : context.l10n.authShowPassword,
            icon: Icon(
              _visible ? LucideIcons.eyeOff : LucideIcons.eye,
              size: 18,
            ),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ),
        if (widget.error case final message?) _AuthError(message),
      ],
    ),
  );
}

class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({
    this.fromCallback = false,
    this.initialFailure,
    super.key,
  });
  final bool fromCallback;
  final AccountAuthFailure? initialFailure;

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  bool _requestingLink = false;

  @override
  void initState() {
    super.initState();
    _beginCallback();
  }

  @override
  void didUpdateWidget(PasswordResetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fromCallback && !oldWidget.fromCallback) _beginCallback();
  }

  void _beginCallback() {
    if (!widget.fromCallback) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(passwordRecoveryProvider)
            .beginCallback(failure: widget.initialFailure);
      }
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  void _close() {
    final recovery = ref.read(passwordRecoveryProvider);
    if (recovery.updating && !recovery.takingLonger) return;
    recovery.dismiss();
    final signedIn = ref.read(accountClientProvider)?.currentUserId != null;
    context.go(signedIn ? '/settings?section=account' : '/login');
  }

  Future<void> _save() async {
    final recovery = ref.read(passwordRecoveryProvider);
    final saved = await recovery.savePassword(
      _password.text,
      _confirmation.text,
    );
    if (!mounted) return;
    if (saved) {
      TextInput.finishAutofillContext(shouldSave: true);
      _password.clear();
      _confirmation.clear();
    } else if (recovery.failure?.kind ==
        AccountAuthFailureKind.passwordMismatch) {
      _confirmationFocus.requestFocus();
    } else {
      _passwordFocus.requestFocus();
    }
  }

  Future<void> _requestNewLink() async {
    if (_requestingLink) return;
    setState(() => _requestingLink = true);
    try {
      var account = ref.read(accountClientProvider);
      if (account == null) {
        await ref.read(accountBootstrapProvider.notifier).retry();
        if (!mounted) return;
        account = ref.read(accountClientProvider);
      }
      if (account == null || !mounted) return;
      await showPomodoistEmailAuthDialog(
        context: context,
        account: account,
        redirectTo: pomodoistLoginRedirect,
        config: ref.read(runtimePublicConfigProvider),
        nativeCaptchaCallbacks: ref
            .read(nativeLinkCoordinatorProvider)
            ?.captchaCallbacks,
        resetPassword: true,
      );
    } finally {
      if (mounted) setState(() => _requestingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(passwordRecoveryProvider);
    final l10n = context.l10n;
    final bootstrap = ref.watch(accountBootstrapProvider);
    final saving = recovery.updating;
    final canClose = !saving || recovery.takingLonger;
    final updated = recovery.stage == PasswordRecoveryStage.updated;
    final checking =
        recovery.stage == PasswordRecoveryStage.checking ||
        (!recovery.available && bootstrap.isLoading);
    final editable =
        recovery.stage == PasswordRecoveryStage.ready ||
        recovery.stage == PasswordRecoveryStage.saving;
    final failure = recovery.failure;
    final feedback = failure == null
        ? null
        : presentAccountAuthFailure(
            l10n,
            failure,
            operation: AccountAuthOperation.passwordUpdate,
          );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && canClose) _close();
        },
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.appColors.border),
                  ),
                  child: _AuthSurface(
                    onClose: canClose ? _close : null,
                    child: AutofillGroup(
                      onDisposeAction: AutofillContextAction.cancel,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            updated
                                ? l10n.authPasswordUpdatedTitle
                                : editable
                                ? l10n.authNewPasswordTitle
                                : l10n.authResetTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            updated
                                ? l10n.authPasswordUpdatedMessage
                                : editable
                                ? l10n.authNewPasswordDescription
                                : checking
                                ? l10n.authCheckingResetLink
                                : l10n.authResetLinkExpired,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.appColors.secondaryText,
                                ),
                          ),
                          const SizedBox(height: 24),
                          if (recovery.takingLonger) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(l10n.operationTakingLonger),
                            ),
                            ShadButton.ghost(
                              onPressed: _close,
                              child: Text(l10n.commonClose),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (checking)
                            const LinearProgressIndicator()
                          else if (updated)
                            ShadButton(
                              onPressed: _close,
                              child: Text(l10n.purchaseSuccessContinue),
                            )
                          else if (editable) ...[
                            _AuthPasswordField(
                              fieldKey: const Key('account-new-password'),
                              label: l10n.authNewPassword,
                              controller: _password,
                              focusNode: _passwordFocus,
                              enabled: !saving,
                              newPassword: true,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              onSubmitted: _confirmationFocus.requestFocus,
                              error:
                                  feedback?.field ==
                                          AccountAuthField.password &&
                                      failure?.kind !=
                                          AccountAuthFailureKind
                                              .passwordMismatch
                                  ? feedback?.message
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            _AuthPasswordField(
                              fieldKey: const Key('account-confirm-password'),
                              label: l10n.authConfirmPassword,
                              controller: _confirmation,
                              focusNode: _confirmationFocus,
                              enabled: !saving,
                              newPassword: true,
                              onSubmitted: _save,
                              error:
                                  failure?.kind ==
                                      AccountAuthFailureKind.passwordMismatch
                                  ? feedback?.message
                                  : null,
                            ),
                            if (feedback != null &&
                                feedback.field == AccountAuthField.form)
                              _AuthError(feedback.message),
                            const SizedBox(height: 24),
                            ShadButton(
                              enabled: !saving,
                              onPressed: _save,
                              leading: saving
                                  ? SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: context.appColors.onAccent,
                                      ),
                                    )
                                  : null,
                              child: Text(l10n.authSavePassword),
                            ),
                          ] else ...[
                            if (!recovery.available && bootstrap.hasError)
                              _AuthError(
                                pomodoistAccountFailureMessage(
                                  context,
                                  bootstrap.error!,
                                ),
                              ),
                            if (feedback != null &&
                                failure?.kind !=
                                    AccountAuthFailureKind.linkExpired)
                              _AuthError(feedback.message),
                            ShadButton(
                              enabled: !_requestingLink,
                              onPressed: _requestingLink
                                  ? null
                                  : _requestNewLink,
                              child: Text(
                                recovery.available
                                    ? l10n.authSendLink
                                    : l10n.commonRetry,
                              ),
                            ),
                            ShadButton.ghost(
                              onPressed: _close,
                              child: Text(l10n.authBackToSignIn),
                            ),
                          ],
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
}
