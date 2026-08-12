import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    OutlinedButton.icon(
      onPressed: () => unawaited(
        _runSocialSignIn(
          context: context,
          account: account,
          signIn: () => account.signInWithApple(redirectTo: redirectTo),
          onSignedIn: onSignedIn,
        ),
      ),
      icon: const Icon(Icons.apple),
      label: Text(appleLabel),
    ),
    OutlinedButton.icon(
      onPressed: () => unawaited(
        _runSocialSignIn(
          context: context,
          account: account,
          signIn: () => account.signInWithGoogle(redirectTo: redirectTo),
          onSignedIn: onSignedIn,
        ),
      ),
      icon: const Icon(Icons.account_circle_outlined),
      label: Text(googleLabel),
    ),
    OutlinedButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PomodoistEmailAuthDialog(
          account: account,
          redirectTo: redirectTo,
          onSignedIn: onSignedIn,
          config: config,
          nativeCaptchaCallbacks: nativeCaptchaCallbacks,
        ),
      ),
      icon: const Icon(Icons.email_outlined),
      label: Text(emailLabel),
    ),
  ];
}

Future<void> _runSocialSignIn({
  required BuildContext context,
  required AccountClient account,
  required Future<void> Function() signIn,
  VoidCallback? onSignedIn,
}) async {
  try {
    await signIn();
    if (context.mounted && account.currentUserId != null) {
      onSignedIn?.call();
    }
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Authentication failed. Please try again.')),
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
  });

  final AccountClient account;
  final String redirectTo;
  final VoidCallback? onSignedIn;
  final RuntimePublicConfig config;
  final Stream<Uri>? nativeCaptchaCallbacks;

  @override
  State<_PomodoistEmailAuthDialog> createState() =>
      _PomodoistEmailAuthDialogState();
}

class _PomodoistEmailAuthDialogState extends State<_PomodoistEmailAuthDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  _EmailAction _mode = _EmailAction.signIn;
  late final CaptchaTokenController _captcha = CaptchaTokenController(
    required: kIsWeb && widget.config.turnstileSiteKey.isNotEmpty,
  );
  NativeCaptchaBroker? _nativeBroker;
  Timer? _slowTimer;
  bool _submitting = false;
  bool _takingLonger = false;
  String? _error;

  bool get _canSubmit =>
      !_submitting &&
      _email.text.trim().isNotEmpty &&
      (!kIsWeb || _captcha.canSubmit);

  @override
  void initState() {
    super.initState();
    _email.addListener(_changed);
    _password.addListener(_changed);
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
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(minWidth: 360),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        _mode == _EmailAction.signIn ? 'Email sign in' : 'Create account',
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
                segments: const [
                  ButtonSegment(
                    value: _EmailAction.signIn,
                    label: Text('Sign in'),
                  ),
                  ButtonSegment(
                    value: _EmailAction.signUp,
                    label: Text('Create account'),
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
                          _error = null;
                        });
                      },
              ),
              TextField(
                key: const Key('account-email-field'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                key: const Key('account-password-field'),
                controller: _password,
                autofillHints: _mode == _EmailAction.signIn
                    ? const [AutofillHints.password]
                    : const [AutofillHints.newPassword],
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (kIsWeb && widget.config.turnstileSiteKey.isNotEmpty) ...[
                const SizedBox(height: 16),
                CaptchaVerification(
                  siteKey: widget.config.turnstileSiteKey,
                  controller: _captcha,
                  onChanged: _changed,
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const Key('account-auth-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
          child: const Text('Cancel'),
        ),
        if (_mode == _EmailAction.signIn)
          TextButton(
            onPressed: _canSubmit
                ? () => _submit(_EmailAction.magicLink)
                : null,
            child: const Text('Send link'),
          ),
        FilledButton(
          onPressed: _canSubmit && _password.text.isNotEmpty
              ? () => _submit(_mode)
              : null,
          child: _submitting
              ? _takingLonger
                    ? const Icon(Icons.hourglass_top, size: 18)
                    : const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
              : Text(
                  _mode == _EmailAction.signIn ? 'Sign in' : 'Create account',
                ),
        ),
      ],
    );
  }

  Future<void> _submit(_EmailAction action) async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _takingLonger = false;
      _error = null;
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
          throw StateError('Security verification is unavailable');
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
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      if (signedIn) widget.onSignedIn?.call();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            action == _EmailAction.magicLink
                ? 'Magic link sent.'
                : action == _EmailAction.signUp
                ? 'Account created.'
                : 'Signed in.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = isEmailConfirmationRequired(error)
              ? 'Please confirm your email using the link we sent you, then sign in again.'
              : 'Authentication failed. Check your details and try again.';
        });
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
}
