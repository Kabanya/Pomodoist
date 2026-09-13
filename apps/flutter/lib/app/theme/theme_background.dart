import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_motion.dart';
import 'app_theme.dart';
import 'app_theme_settings.dart';
import 'macos_glass.dart';

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
    this.blurBehind = false,
    super.key,
  });

  final ThemeBackgroundZone zone;
  final Widget child;
  final bool sharedWholeApp;
  final ({LayerLink link, Size size})? wholeAppViewport;
  final Color? color;
  final bool blurBehind;

  static bool hasBackdrop(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ThemeBackgroundScope>()
          ?.hasBackdrop ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgrounds = ref.watch(
      appThemeSettingsProvider.select(
        (settings) => settings.activeTheme.backgrounds,
      ),
    );
    final theme = Theme.of(context);
    final type = backgrounds.effectiveType(
      isMacOS: supportsMacosGlass,
      glassReady: macosGlassReady(context, ref),
    );
    final image = backgrounds.resolve(zone, theme.brightness);
    return ThemeBackgroundPreview(
      image: image,
      glassDim: type == ThemeBackgroundType.macosGlass
          ? backgrounds.glassDim(theme.brightness)
          : null,
      blurBehind: blurBehind,
      color:
          color ??
          (zone == ThemeBackgroundZone.sidebar
              ? context.appColors.surface
              : context.appColors.canvas),
      viewport:
          type == ThemeBackgroundType.photo &&
              backgrounds.mode == ThemeBackgroundMode.wholeApp
          ? wholeAppViewport
          : null,
      paintImage:
          !sharedWholeApp ||
          type != ThemeBackgroundType.photo ||
          backgrounds.mode != ThemeBackgroundMode.wholeApp,
      child: _ThemeBackgroundScope(
        hasBackdrop:
            image.imageId != null || type == ThemeBackgroundType.macosGlass,
        child: Theme(
          data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
          child: child,
        ),
      ),
    );
  }
}

class _ThemeBackgroundScope extends InheritedWidget {
  const _ThemeBackgroundScope({
    required this.hasBackdrop,
    required super.child,
  });

  final bool hasBackdrop;

  @override
  bool updateShouldNotify(_ThemeBackgroundScope oldWidget) =>
      hasBackdrop != oldWidget.hasBackdrop;
}

class ThemeBackgroundPreview extends ConsumerWidget {
  const ThemeBackgroundPreview({
    required this.image,
    required this.color,
    required this.child,
    this.paintImage = true,
    this.viewport,
    this.glassDim,
    this.glassSample = false,
    this.blurBehind = false,
    super.key,
  });

  final ThemeBackgroundImage image;
  final Color color;
  final Widget child;
  final double? glassDim;
  final bool glassSample;
  final bool blurBehind;

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
        if (glassDim == null && paintImage) ColoredBox(color: color),
        if (glassDim != null && glassSample)
          const CustomPaint(painter: _TransparencyPainter()),
        if (glassDim == null && paintImage && decoded != null)
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
            end: color.withValues(
              alpha: glassDim ?? (decoded == null ? 1 : image.dim),
            ),
          ),
          duration: duration,
          curve: AppMotion.curve,
          builder: (context, tint, child) => ColoredBox(color: tint!),
        ),
      ],
    );
    if (glassDim != null && blurBehind) {
      background = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: background,
      );
    }
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

class _TransparencyPainter extends CustomPainter {
  const _TransparencyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var y = 0.0; y < size.height; y += 12) {
      for (var x = 0.0; x < size.width; x += 12) {
        paint.color = ((x / 12).round() + (y / 12).round()).isEven
            ? const Color(0xFFEEEEEE)
            : const Color(0xFFBBBBBB);
        canvas.drawRect(Rect.fromLTWH(x, y, 12, 12), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TransparencyPainter oldDelegate) => false;
}
