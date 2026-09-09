import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_motion.dart';
import 'app_theme.dart';
import 'app_theme_settings.dart';

final _decodedThemeImageProvider = FutureProvider.autoDispose
    .family<ui.Image?, String>((ref, id) async {
      final bytes = await ref.watch(themeImageBytesProvider(id).future);
      if (bytes == null) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final image = (await codec.getNextFrame()).image;
        if (!ref.mounted) {
          image.dispose();
          return null;
        }
        ref.onDispose(image.dispose);
        return image;
      } finally {
        codec.dispose();
      }
    });

class ThemeBackground extends ConsumerWidget {
  const ThemeBackground({
    required this.zone,
    required this.child,
    this.sharedWholeApp = false,
    this.wholeAppViewport,
    this.color,
    super.key,
  });

  final ThemeBackgroundZone zone;
  final Widget child;
  final bool sharedWholeApp;
  final ({LayerLink link, Size size})? wholeAppViewport;
  final Color? color;

  static bool hasImage(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ThemeBackgroundScope>()
          ?.hasImage ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgrounds = ref.watch(
      appThemeSettingsProvider.select(
        (settings) => settings.activeTheme.backgrounds,
      ),
    );
    final theme = Theme.of(context);
    final image = backgrounds.resolve(zone, theme.brightness);
    return ThemeBackgroundPreview(
      image: image,
      color:
          color ??
          (zone == ThemeBackgroundZone.sidebar
              ? context.appColors.surface
              : context.appColors.canvas),
      viewport: backgrounds.mode == ThemeBackgroundMode.wholeApp
          ? wholeAppViewport
          : null,
      paintImage:
          !sharedWholeApp || backgrounds.mode != ThemeBackgroundMode.wholeApp,
      child: _ThemeBackgroundScope(
        hasImage: image.imageId != null,
        child: Theme(
          data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
          child: child,
        ),
      ),
    );
  }
}

class _ThemeBackgroundScope extends InheritedWidget {
  const _ThemeBackgroundScope({required this.hasImage, required super.child});

  final bool hasImage;

  @override
  bool updateShouldNotify(_ThemeBackgroundScope oldWidget) =>
      hasImage != oldWidget.hasImage;
}

class ThemeBackgroundPreview extends ConsumerWidget {
  const ThemeBackgroundPreview({
    required this.image,
    required this.color,
    required this.child,
    this.paintImage = true,
    this.viewport,
    super.key,
  });

  final ThemeBackgroundImage image;
  final Color color;
  final Widget child;

  // The wide shell paints one shared image; its zones only add their tint.
  final bool paintImage;
  final ({LayerLink link, Size size})? viewport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = image.imageId;
    final loaded = id == null
        ? null
        : ref.watch(_decodedThemeImageProvider(id));
    final decoded = loaded == null || loaded.isLoading || loaded.hasError
        ? null
        : loaded.value;
    final duration = AppMotion.duration(context, AppMotion.state);
    Widget background = Stack(
      fit: StackFit.expand,
      children: [
        if (paintImage) ColoredBox(color: color),
        if (paintImage && decoded != null)
          TweenAnimationBuilder<double>(
            key: ValueKey(decoded),
            tween: Tween(begin: 0, end: 1),
            duration: duration,
            curve: AppMotion.curve,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: image.blur),
              duration: duration,
              curve: AppMotion.curve,
              builder: (context, blur, child) => ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.clamp,
                ),
                enabled: blur > 0,
                child: child,
              ),
              child: RawImage(
                image: decoded,
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            end: color.withValues(alpha: decoded == null ? 1 : image.dim),
          ),
          duration: duration,
          curve: AppMotion.curve,
          builder: (context, tint, child) => ColoredBox(color: tint!),
        ),
      ],
    );
    final viewport = this.viewport;
    if (viewport != null) {
      // Keep the drawer crop fixed to the shell while the drawer slides.
      background = OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: viewport.size.width,
        maxWidth: viewport.size.width,
        minHeight: viewport.size.height,
        maxHeight: viewport.size.height,
        child: CompositedTransformFollower(
          link: viewport.link,
          showWhenUnlinked: false,
          child: SizedBox.fromSize(size: viewport.size, child: background),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(child: ClipRect(child: background)),
          ),
        ),
        child,
      ],
    );
  }
}
