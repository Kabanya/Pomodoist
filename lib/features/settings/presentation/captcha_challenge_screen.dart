import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_l10n.dart';
import '../../../app/captcha_handoff.dart';
import '../../../app/captcha_security.dart';
import '../../../app/captcha_verification.dart';
import '../../../app/runtime_public_config.dart';

class CaptchaChallengeScreen extends ConsumerStatefulWidget {
  const CaptchaChallengeScreen({
    required this.uri,
    this.handoffController,
    this.onHandoff = replaceWithCaptchaCallback,
    super.key,
  });

  final Uri uri;
  final CaptchaHandoffController? handoffController;
  final CaptchaHandoff onHandoff;

  @override
  ConsumerState<CaptchaChallengeScreen> createState() =>
      _CaptchaChallengeScreenState();
}

class _CaptchaChallengeScreenState
    extends ConsumerState<CaptchaChallengeScreen> {
  late final CaptchaChallengeRequest? _request;
  late final CaptchaTokenController _controller;
  late final CaptchaHandoffController _handoffController;

  @override
  void initState() {
    super.initState();
    try {
      _request = CaptchaChallengeRequest.parse(widget.uri);
    } on FormatException {
      _request = null;
    }
    _controller = CaptchaTokenController(required: true);
    _handoffController = widget.handoffController ?? CaptchaHandoffController();
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) {
      return _ChallengeScaffold(
        child: Text(
          context.l10n.captchaChallengeInvalid,
          key: const Key('captcha-challenge-invalid'),
          textAlign: TextAlign.center,
        ),
      );
    }
    final callback = _handoffController.callbackUri;
    if (callback != null) {
      return _ChallengeScaffold(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.captchaChallengeHandoffHelp,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('captcha-handoff-retry'),
              onPressed: () => _handoffController.retry(widget.onHandoff),
              child: Text(context.l10n.captchaReturnToApp),
            ),
          ],
        ),
      );
    }
    final config = ref.watch(runtimePublicConfigProvider);
    return _ChallengeScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.captchaChallengePrompt,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          CaptchaVerification(
            siteKey: config.turnstileSiteKey,
            controller: _controller,
            onChanged: () {
              if (mounted) setState(() {});
            },
            onSolved: (token) {
              if (!mounted) return;
              final accepted = _handoffController.solveAndHandoff(
                request,
                token,
                widget.onHandoff,
              );
              if (accepted && mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

class _ChallengeScaffold extends StatelessWidget {
  const _ChallengeScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.captchaChallengeTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      child,
                    ],
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
