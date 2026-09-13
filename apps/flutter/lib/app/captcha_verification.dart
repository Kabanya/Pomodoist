import 'package:flutter/material.dart';

import 'app_l10n.dart';
import 'captcha_security.dart';
import 'turnstile_widget.dart';

class CaptchaVerification extends StatelessWidget {
  const CaptchaVerification({
    required this.siteKey,
    required this.controller,
    required this.onChanged,
    this.onSolved,
    this.loadTimeout = const Duration(seconds: 10),
    super.key,
  });

  final String siteKey;
  final CaptchaTokenController controller;
  final VoidCallback onChanged;
  final ValueChanged<String>? onSolved;
  final Duration loadTimeout;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final retryRequired =
        status == CaptchaStatus.error || status == CaptchaStatus.expired;
    if (!retryRequired) {
      return TurnstileWidget(
        key: ValueKey(controller.generation),
        siteKey: siteKey,
        controller: controller,
        onChanged: onChanged,
        onSolved: onSolved,
        loadTimeout: loadTimeout,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            status == CaptchaStatus.expired
                ? context.l10n.authCaptchaExpired
                : context.l10n.authCaptchaFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('captcha-verification-retry'),
          onPressed: () {
            controller.reset();
            onChanged();
          },
          child: Text(context.l10n.authRetryVerification),
        ),
      ],
    );
  }
}
