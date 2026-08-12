import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_l10n.dart';
import '../../app/theme/app_theme.dart';
import 'billing.dart';
import '../onboarding/onboarding_gate.dart';

const stripePurchaseFallbackUrl = 'pomodoist://purchase-success';

class PurchaseSuccessScreen extends ConsumerStatefulWidget {
  const PurchaseSuccessScreen({required this.returnTo, this.source, super.key});

  final String returnTo;
  final String? source;

  @override
  ConsumerState<PurchaseSuccessScreen> createState() =>
      _PurchaseSuccessScreenState();
}

class _PurchaseSuccessScreenState extends ConsumerState<PurchaseSuccessScreen> {
  late bool _active = widget.source != 'stripe';

  @override
  void initState() {
    super.initState();
    if (!_active) unawaited(_pollEntitlement());
  }

  Future<void> _pollEntitlement() async {
    for (var attempt = 0; attempt < 10 && mounted; attempt += 1) {
      if (attempt > 0) {
        await Future<void>.delayed(ref.read(billingStripePollIntervalProvider));
      }
      try {
        if (await ref.read(billingEntitlementRefresherProvider)()) {
          if (mounted) setState(() => _active = true);
          return;
        }
      } on Object {
        // A later poll can recover from a transient account refresh failure.
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.accentTint,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Icon(
                        _active ? Icons.verified_rounded : Icons.hourglass_top,
                        key: Key(
                          _active
                              ? 'purchase-success-icon'
                              : 'purchase-processing-icon',
                        ),
                        color: colors.accent,
                        size: 46,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _active
                        ? l10n.purchaseSuccessTitle
                        : l10n.purchaseProcessingTitle,
                    key: Key(
                      _active
                          ? 'purchase-success-title'
                          : 'purchase-processing-title',
                    ),
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _active
                        ? l10n.purchaseSuccessMessage
                        : l10n.purchaseProcessingMessage,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.secondaryText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('purchase-success-continue'),
                    onPressed: () => _continue(context),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.purchaseSuccessContinue),
                  ),
                  if (kIsWeb && widget.source == 'stripe') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('purchase-open-app'),
                      onPressed: () => launchUrl(
                        Uri.parse(stripePurchaseFallbackUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.purchaseOpenApp),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _continue(BuildContext context) {
    final onboarding = ref.read(onboardingControllerProvider);
    if (!onboarding.completed && onboarding.step == OnboardingStep.paywall) {
      ref.read(onboardingControllerProvider.notifier).next();
    }
    context.go(widget.returnTo);
  }
}
