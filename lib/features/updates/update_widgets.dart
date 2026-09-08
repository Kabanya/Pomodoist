import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../app/theme/app_motion.dart';

import 'update_controller.dart';
import 'update_copy.dart';
import 'update_providers.dart';
import 'update_release.dart';

class DesktopUpdateHost extends ConsumerStatefulWidget {
  const DesktopUpdateHost({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<DesktopUpdateHost> createState() => _DesktopUpdateHostState();
}

class _DesktopUpdateHostState extends ConsumerState<DesktopUpdateHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(desktopUpdateControllerProvider).start());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(desktopUpdateControllerProvider).onResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(desktopUpdateControllerProvider);
    if (!controller.enabled) return widget.child;
    return Overlay.wrap(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            right: 16,
            bottom: 16,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.popup),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: AppMotion.curve,
                          ),
                        ),
                    child: child,
                  ),
                ),
                child: controller.popupVisible
                    ? DesktopUpdatePopup(
                        key: const ValueKey('desktop-update-popup'),
                        controller: controller,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopUpdatePopup extends StatelessWidget {
  const DesktopUpdatePopup({required this.controller, super.key});
  final DesktopUpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final copy = UpdateCopy.of(context);
      final theme = Theme.of(context);
      final offer = controller.offer;
      final size = MediaQuery.sizeOf(context);
      final reducedMotion = MediaQuery.disableAnimationsOf(context);
      final duration = AppMotion.duration(context, AppMotion.state);
      return Semantics(
        container: true,
        label: copy.title,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.max(0.0, math.min(368.0, size.width - 32)),
            maxHeight: math.max(0.0, math.min(480.0, size.height - 32)),
          ),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.monitorDown,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            copy.title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          key: const Key('desktop-update-close'),
                          tooltip: copy.close,
                          onPressed: controller.dismiss,
                          icon: const Icon(LucideIcons.x),
                        ),
                      ],
                    ),
                    if (offer != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        copy.version(offer.version.text),
                        key: const Key('desktop-update-version'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: AnimatedSwitcher(
                        duration: duration,
                        child: Align(
                          key: ValueKey(controller.phase),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            copy.phase(controller.phase),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                    if (controller.busy) ...[
                      const SizedBox(height: 14),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: controller.progress ?? 0),
                        duration: duration,
                        builder: (context, value, _) => LinearProgressIndicator(
                          key: const Key('desktop-update-progress'),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(6),
                          value: controller.progress == null
                              ? (reducedMotion ? 0.5 : null)
                              : value,
                        ),
                      ),
                      if (controller.progress != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${(controller.progress! * 100).round()}%',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                    if (controller.error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        controller.error!,
                        key: const Key('desktop-update-error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    if (offer != null &&
                        offer.notes.isNotEmpty &&
                        !controller.busy) ...[
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: SingleChildScrollView(
                          child: Text(
                            offer.notes,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(copy.restart, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (offer != null)
                          ShadButton.ghost(
                            onPressed: () async {
                              try {
                                await launchUrl(
                                  offer.releaseUrl,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {
                                /* Release notes are also visible in this card. */
                              }
                            },
                            child: Text(copy.notes),
                          ),
                        if (offer != null)
                          ShadButton(
                            key: const Key('desktop-update-install'),
                            enabled: !controller.busy,
                            onPressed: controller.busy
                                ? null
                                : () => unawaited(controller.update()),
                            leading: const Icon(LucideIcons.download, size: 18),
                            child: Text(copy.update),
                          ),
                        if (offer == null)
                          ShadButton.outline(
                            enabled: !controller.busy,
                            onPressed: controller.busy
                                ? null
                                : () =>
                                      unawaited(controller.check(manual: true)),
                            child: Text(copy.check),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class DesktopUpdateSettings extends ConsumerWidget {
  const DesktopUpdateSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(desktopUpdateControllerProvider);
    if (!controller.isDesktop) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final copy = UpdateCopy.of(context);
        if (!controller.enabled) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              controller.officialUpdatesAllowed
                  ? copy.unsupported
                  : copy.ownerManaged,
            ),
          );
        }
        return Column(
          key: const Key('desktop-update-settings'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 28),
            Text(copy.settings, style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile.adaptive(
              key: const Key('desktop-update-rc'),
              contentPadding: EdgeInsets.zero,
              title: Text(copy.rc),
              subtitle: Text(copy.rcHelp),
              value: controller.channel == UpdateChannel.rc,
              onChanged: controller.busy
                  ? null
                  : (enabled) => unawaited(
                      controller.setChannel(
                        enabled ? UpdateChannel.rc : UpdateChannel.stable,
                      ),
                    ),
            ),
            Text(
              controller.channel == UpdateChannel.stable
                  ? copy.stable
                  : copy.rcChannel,
            ),
            const SizedBox(height: 8),
            Text(
              controller.error ?? copy.phase(controller.phase),
              key: const Key('desktop-update-settings-status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ShadButton.outline(
              key: const Key('desktop-update-check'),
              enabled: !controller.busy,
              onPressed: controller.busy
                  ? null
                  : () => unawaited(controller.check(manual: true)),
              leading: const Icon(LucideIcons.refreshCw),
              child: Text(copy.check),
            ),
          ],
        );
      },
    );
  }
}
