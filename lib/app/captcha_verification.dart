import 'package:flutter/material.dart';

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
    final retryRequired =
        controller.status == CaptchaStatus.error ||
        controller.status == CaptchaStatus.expired;
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
        if (controller.message case final message?) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          key: const Key('captcha-verification-retry'),
          onPressed: () {
            controller.reset();
            onChanged();
          },
          child: const Text('Retry verification'),
        ),
      ],
    );
  }
}
