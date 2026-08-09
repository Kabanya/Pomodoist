import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_l10n.dart';

class AccountSignOutButton extends StatefulWidget {
  const AccountSignOutButton({
    required this.label,
    required this.onSignOut,
    super.key,
  });

  final String label;
  final Future<void> Function() onSignOut;

  @override
  State<AccountSignOutButton> createState() => _AccountSignOutButtonState();
}

class _AccountSignOutButtonState extends State<AccountSignOutButton> {
  static const _slowThreshold = Duration(seconds: 30);

  Timer? _slowTimer;
  var _submitting = false;
  var _takingLonger = false;

  Future<void> _signOut() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _takingLonger = false;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(_slowThreshold, () {
      if (mounted && _submitting) setState(() => _takingLonger = true);
    });
    try {
      await widget.onSignOut();
    } finally {
      _slowTimer?.cancel();
      if (mounted) {
        setState(() {
          _submitting = false;
          _takingLonger = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: _submitting ? null : _signOut,
          icon: _submitting
              ? _takingLonger
                    ? const Icon(Icons.hourglass_top, size: 18)
                    : const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
              : const Icon(Icons.logout),
          label: Text(widget.label),
        ),
        if (_takingLonger)
          Semantics(
            key: const Key('account-sign-out-slow'),
            liveRegion: true,
            child: Text(
              context.l10n.operationTakingLonger,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
