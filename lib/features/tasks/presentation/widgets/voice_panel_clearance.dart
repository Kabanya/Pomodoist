import 'dart:math' as math;

import 'package:flutter/material.dart';

final _clearances = Expando<_BottomClearance>();

_BottomClearance _clearance(OverlayState overlay) =>
    _clearances[overlay] ??= _BottomClearance();

ValueNotifier<double> voicePanelBottomClearanceOf(BuildContext context) =>
    _clearance(Overlay.of(context, rootOverlay: true));

class _BottomClearance extends ValueNotifier<double> {
  _BottomClearance() : super(0);

  final areas = <Object, double>{};

  void update(Object owner, double? height) {
    if (height == null) {
      areas.remove(owner);
    } else {
      areas[owner] = height;
    }
    value = areas.values.fold(0.0, math.max);
  }
}

/// Keeps the floating voice controls above the actual bottom navigation/player.
class VoicePanelBottomClearance extends StatefulWidget {
  const VoicePanelBottomClearance({required this.child, super.key});

  final Widget child;

  @override
  State<VoicePanelBottomClearance> createState() =>
      _VoicePanelBottomClearanceState();
}

class _VoicePanelBottomClearanceState extends State<VoicePanelBottomClearance> {
  final _boundsKey = GlobalKey();
  _BottomClearance? _owner;

  void _measure() {
    if (!mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final box = _boundsKey.currentContext?.findRenderObject() as RenderBox?;
    final root = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || root == null || !box.hasSize || !root.hasSize) return;
    final owner = _clearance(overlay);
    if (!identical(_owner, owner)) _owner?.update(this, null);
    _owner = owner;
    final height = box.size.height == 0
        ? 0.0
        : (root.size.height - box.localToGlobal(Offset.zero, ancestor: root).dy)
              .clamp(0.0, root.size.height);
    owner.update(this, height);
  }

  @override
  Widget build(BuildContext context) {
    MediaQuery.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: SizedBox(key: _boundsKey, child: widget.child),
      ),
    );
  }

  @override
  void dispose() {
    final owner = _owner;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => owner?.update(this, null),
    );
    super.dispose();
  }
}
