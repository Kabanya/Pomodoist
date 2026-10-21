import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell/app_shell_patch.dart';
import 'app_shell/app_shell_registry.dart';
import 'app_shell/view_shell_overrides.dart';

/// Resolves native window chrome brightness for one secondary/dialog view.
Brightness? resolveViewShellBrightness(
  AppShellRegistry registry,
  ViewShellOverrides? overrides,
) {
  final shell = AppShellPatch.composeAppearance(registry.snapshot, overrides?.appearance);
  return shell?.resolveWindowBrightness();
}

/// Keeps native window chrome in sync with the effective view shell appearance.
class ViewShellBrightnessSync extends StatefulWidget {
  const ViewShellBrightnessSync({
    super.key,
    required this.registry,
    required this.viewShellOverrides,
    required this.onBrightnessChanged,
    required this.child,
  });

  final AppShellRegistry registry;
  final ValueNotifier<ViewShellOverrides?> viewShellOverrides;
  final Future<void> Function(Brightness brightness) onBrightnessChanged;
  final Widget child;

  @override
  State<ViewShellBrightnessSync> createState() => _ViewShellBrightnessSyncState();
}

class _ViewShellBrightnessSyncState extends State<ViewShellBrightnessSync> with WidgetsBindingObserver {
  Brightness? _lastSynced;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.registry.addListener(_scheduleSync);
    widget.viewShellOverrides.addListener(_scheduleSync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBrightness());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.registry.removeListener(_scheduleSync);
    widget.viewShellOverrides.removeListener(_scheduleSync);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _scheduleSync();
  }

  void _scheduleSync() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncBrightness();
    });
  }

  void _syncBrightness() {
    final brightness = resolveViewShellBrightness(widget.registry, widget.viewShellOverrides.value);
    if (brightness == null || _lastSynced == brightness) return;
    _lastSynced = brightness;
    unawaited(widget.onBrightnessChanged(brightness));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
