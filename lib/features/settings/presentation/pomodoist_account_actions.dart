import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/account_auth_feedback.dart';
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
    OutlinedButton.icon(
      onPressed: () => showPomodoistEmailAuthDialog(
        context: context,
        account: account,
        redirectTo: redirectTo,
        onSignedIn: onSignedIn,
        config: config,
        nativeCaptchaCallbacks: nativeCaptchaCallbacks,
      ),
      icon: const Icon(Icons.email_outlined),
      label: Text(emailLabel),
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
  VoidCallback? onSignedIn,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PomodoistEmailAuthDialog(
      account: account,
      redirectTo: redirectTo,
      onSignedIn: onSignedIn,
      config: config,
      nativeCaptchaCallbacks: nativeCaptchaCallbacks,
      initialEmail: initialEmail,
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
      PomodoistSocialProvider.google => Icons.account_circle_outlined,
    };
    return OutlinedButton.icon(
      onPressed: _submitting ? null : _submit,
      icon: _submitting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(widget.label),
    );
  }
}

enum _EmailAction { magicLink, signIn, signUp }

const _accountOperationSlowThreshold = Duration(seconds: 30);

class _PomodoistEmailAuthDialog extends StatefulWidget {
  const _PomodoistEmailAuthDialog({
    required this.account,
    required this.redirectTo,
    required this.onSignedIn,
    required this.config,
    required this.nativeCaptchaCallbacks,
    required this.initialEmail,
  });

  final AccountClient account;
  final String redirectTo;
  final VoidCallback? onSignedIn;
  final RuntimePublicConfig config;
  final Stream<Uri>? nativeCaptchaCallbacks;
  final String initialEmail;

  @override
  State<_PomodoistEmailAuthDialog> createState() =>
      _PomodoistEmailAuthDialogState();
}

class _PomodoistEmailAuthDialogState extends State<_PomodoistEmailAuthDialog> {
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
  bool _takingLonger = false;
  AccountAuthFeedback? _feedback;
  _EmailAction? _lastAction;

  bool get _canSubmit => !_submitting;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final feedback = _feedback;
    return AlertDialog(
      constraints: const BoxConstraints(minWidth: 360),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        _mode == _EmailAction.signIn
            ? l10n.authEmailSignInTitle
            : l10n.registerTitle,
      ),
      content: SingleChildScrollView(
        child: AutofillGroup(
          key: ValueKey(_mode),
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<_EmailAction>(
                key: const Key('account-auth-mode'),
                segments: [
                  ButtonSegment(
                    value: _EmailAction.signIn,
                    label: Text(l10n.authSignInAction),
                  ),
                  ButtonSegment(
                    value: _EmailAction.signUp,
                    label: Text(l10n.registerSubmit),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _submitting
                    ? null
                    : (selection) {
                        final mode = selection.single;
                        if (mode == _mode) return;
                        _password.clear();
                        setState(() {
                          _mode = mode;
                          _feedback = null;
                        });
                        _passwordFocus.requestFocus();
                      },
              ),
              Semantics(
                liveRegion: feedback?.field == AccountAuthField.email,
                child: TextField(
                  key: const Key('account-email-field'),
                  controller: _email,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.accountEmail,
                    errorText: feedback?.field == AccountAuthField.email
                        ? feedback?.message
                        : null,
                  ),
                ),
              ),
              Semantics(
                liveRegion: feedback?.field == AccountAuthField.password,
                child: TextField(
                  key: const Key('account-password-field'),
                  controller: _password,
                  focusNode: _passwordFocus,
                  autofillHints: _mode == _EmailAction.signIn
                      ? const [AutofillHints.password]
                      : const [AutofillHints.newPassword],
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.registerPassword,
                    errorText: feedback?.field == AccountAuthField.password
                        ? feedback?.message
                        : null,
                  ),
                ),
              ),
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
                  child: TextButton(
                    key: const Key('account-auth-recovery'),
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
                      const Icon(Icons.hourglass_top, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(context.l10n.operationTakingLonger)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        if (_mode == _EmailAction.signIn)
          TextButton(
            onPressed: _canSubmit
                ? () => _submit(_EmailAction.magicLink)
                : null,
            child: Text(l10n.authSendLink),
          ),
        FilledButton(
          onPressed: _canSubmit ? () => _submit(_mode) : null,
          child: _submitting
              ? _takingLonger
                    ? const Icon(Icons.hourglass_top, size: 18)
                    : const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
              : Text(
                  _mode == _EmailAction.signIn
                      ? l10n.authSignInAction
                      : l10n.registerSubmit,
                ),
        ),
      ],
    );
  }

  Future<void> _submit(_EmailAction action) async {
    if (!_canSubmit) return;
    final emailFailure = validateAccountEmail(_email.text);
    final passwordFailure = action == _EmailAction.magicLink
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
      switch (action) {
        case _EmailAction.magicLink:
          await widget.account.signInWithEmail(
            _email.text.trim(),
            redirectTo: widget.redirectTo,
            captchaToken: token,
          );
        case _EmailAction.signIn:
          await widget.account.signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
            captchaToken: token,
          );
        case _EmailAction.signUp:
          await widget.account.signUpWithPassword(
            email: _email.text.trim(),
            password: _password.text,
            redirectTo: widget.redirectTo,
            captchaToken: token,
          );
      }
      if (action != _EmailAction.magicLink) {
        TextInput.finishAutofillContext(shouldSave: true);
      }
      if (!mounted) return;
      final signedIn = widget.account.currentUserId != null;
      if (action == _EmailAction.signIn && !signedIn) {
        _showFailure(
          const AccountAuthFailure(
            AccountAuthFailureKind.unexpected,
            field: AccountAuthField.form,
            recovery: AccountAuthRecovery.retry,
          ),
          operation: AccountAuthOperation.passwordSignIn,
        );
        return;
      }
      final successMessage = switch (action) {
        _EmailAction.magicLink => context.l10n.authMagicLinkSent,
        _EmailAction.signIn => context.l10n.authSignedIn,
        _EmailAction.signUp =>
          signedIn
              ? context.l10n.authAccountCreated
              : context.l10n.registerCheckEmailMessage,
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
    _EmailAction.signIn => AccountAuthOperation.passwordSignIn,
    _EmailAction.signUp => AccountAuthOperation.signUp,
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
        setState(() {
          _mode = _EmailAction.signIn;
          _feedback = null;
        });
        unawaited(_submit(_EmailAction.magicLink));
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
