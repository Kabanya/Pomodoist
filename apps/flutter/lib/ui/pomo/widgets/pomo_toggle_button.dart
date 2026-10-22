import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';

class PomoToggleButton extends ConsumerStatefulWidget {
  const PomoToggleButton({super.key});

  @override
  ConsumerState<PomoToggleButton> createState() => _PomoToggleButtonState();
}

class _PomoToggleButtonState extends ConsumerState<PomoToggleButton> {
  bool _saving = false;

  Future<void> _toggle() async {
    final controller = ref.read(pomoControllerProvider);
    if (_saving || controller.busy || controller.closing) return;
    setState(() => _saving = true);
    try {
      await controller.setEnabled(!controller.prefs.enabled);
      if (controller.error != null) throw controller.error!;
    } catch (_) {
      if (mounted) {
        showActionFeedback(
          context,
          message: context.l10n.pomoError,
          icon: LucideIcons.triangleAlert,
          sound: ActionFeedbackSound.none,
          haptic: AppHapticCue.none,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!pomoSupported) return const SizedBox.shrink();
    final controller = ref.watch(pomoControllerProvider);
    final enabled = controller.prefs.enabled;
    final colors = context.appColors;
    final label = enabled
        ? context.l10n.commandSearchDisablePomo
        : context.l10n.commandSearchEnablePomo;
    return Semantics(
      toggled: enabled,
      child: IconButton(
        tooltip: label,
        onPressed: _saving || controller.busy || controller.closing
            ? null
            : _toggle,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          maximumSize: const Size(44, double.infinity),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: enabled ? colors.accent : colors.secondaryText,
          backgroundColor: enabled ? colors.accentTint : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: _saving
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.secondaryText,
                ),
              )
            : const ExcludeSemantics(child: _TomatoIcon()),
      ),
    );
  }
}

class _TomatoIcon extends StatelessWidget {
  const _TomatoIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(20),
    painter: _TomatoIconPainter(IconTheme.of(context).color!),
  );
}

class _TomatoIconPainter extends CustomPainter {
  const _TomatoIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = Path()
      ..moveTo(12, 9)
      ..cubicTo(8, 5.5, 3, 7, 3, 12)
      ..cubicTo(3, 17, 7, 21, 12, 21)
      ..cubicTo(17, 21, 21, 17, 21, 12)
      ..cubicTo(21, 7, 16, 5.5, 12, 9)
      ..close();
    final crown = Path()
      ..moveTo(7.5, 6.5)
      ..lineTo(12, 9)
      ..lineTo(16.5, 6.5)
      ..moveTo(12, 9)
      ..cubicTo(11, 5, 12, 3, 14, 2);
    canvas.drawPath(body, paint);
    canvas.drawPath(crown, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TomatoIconPainter oldDelegate) =>
      color != oldDelegate.color;
}
