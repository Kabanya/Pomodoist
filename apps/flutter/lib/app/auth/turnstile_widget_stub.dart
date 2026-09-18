import 'package:flutter/material.dart';

import 'captcha_security.dart';

class TurnstileWidget extends StatelessWidget {
  const TurnstileWidget({
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
