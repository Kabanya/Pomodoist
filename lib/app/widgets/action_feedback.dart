import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics/app_haptics.dart';

export '../../core/haptics/app_haptics.dart';

enum ActionFeedbackSound { none, click }

void showActionFeedback(
  BuildContext context, {
  required String message,
  required IconData icon,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 2),
  bool showCloseIcon = false,
  bool compact = false,
  ActionFeedbackSound sound = ActionFeedbackSound.click,
  AppHapticCue haptic = AppHapticCue.light,
}) {
  if (Scaffold.maybeOf(context) == null) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }

  messenger.hideCurrentSnackBar();
  final compactWidth = compact ? _compactSnackBarWidth(context) : null;
  final colors = Theme.of(context).colorScheme;
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: compactWidth,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
          : null,
      shape: compact
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))
          : null,
      backgroundColor: compact ? colors.inverseSurface : null,
      duration: duration,
      persist: false,
      action: compact ? null : action,
      showCloseIcon: compact ? false : showCloseIcon,
      content: compact
          ? _CompactActionFeedbackContent(
              message: message,
              icon: icon,
              action: action,
              showCloseIcon: showCloseIcon,
            )
          : Row(
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Flexible(child: Text(message)),
              ],
            ),
    ),
  );
  unawaited(playHaptic(haptic));
  unawaited(_playActionFeedbackSound(sound));
}

double? _compactSnackBarWidth(BuildContext context) {
  final width = MediaQuery.maybeSizeOf(context)?.width;
  if (width == null) {
    return 320;
  }
  return math.min(320, math.max(0, width - 24));
}

class _CompactActionFeedbackContent extends StatelessWidget {
  const _CompactActionFeedbackContent({
    required this.message,
    required this.icon,
    required this.action,
    required this.showCloseIcon,
  });

  final String message;
  final IconData icon;
  final SnackBarAction? action;
  final bool showCloseIcon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.onInverseSurface),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onInverseSurface),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 6),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: colors.inversePrimary,
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                action!.onPressed();
                ScaffoldMessenger.of(
                  context,
                ).hideCurrentSnackBar(reason: SnackBarClosedReason.action);
              },
              child: Text(action!.label),
            ),
          ],
          if (showCloseIcon) ...[
            const SizedBox(width: 2),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              padding: EdgeInsets.zero,
              iconSize: 15,
              color: colors.onInverseSurface,
              onPressed: () {
                ScaffoldMessenger.of(
                  context,
                ).hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _playActionFeedbackSound(ActionFeedbackSound sound) async {
  final soundType = switch (sound) {
    ActionFeedbackSound.none => null,
    ActionFeedbackSound.click => SystemSoundType.click,
  };
  if (soundType == null) {
    return;
  }
  try {
    await SystemSound.play(soundType);
  } catch (_) {
    // System sounds are best-effort across platforms and tests.
  }
}
