import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadApp, ShadAppBuilder, ShadTheme, GlobalShadLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import 'package:pomodoist/ui/tasks/widgets/quick_add_bar.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/quick_add/view_models/global_quick_add_view_model.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/ui/core/widgets/app_zoom.dart';
import 'package:pomodoist/ui/core/view_models/app_theme_mode_view_model.dart';
import 'package:pomodoist/ui/core/view_models/app_zoom_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/macos_glass.dart';
import 'package:pomodoist/ui/core/themes/theme_background.dart';
import 'package:pomodoist/ui/core/widgets/keyboard_dismiss_region.dart';

class GlobalQuickAddWindowApp extends ConsumerWidget {
  const GlobalQuickAddWindowApp({
    required this.onClose,
    required this.onVoiceModeChanged,
    this.onCommentExpandedChanged,
    this.onEditorModeChanged,
    this.onPreferredWidthChanged,
    super.key,
  });

  final VoidCallback onClose;
  final ValueChanged<bool> onVoiceModeChanged;
  final ValueChanged<bool>? onCommentExpandedChanged;
  final Future<void> Function(bool)? onEditorModeChanged;
  final void Function(double width, double viewportWidth)?
  onPreferredWidthChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(quickAddWindowLanguageProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final rootBackground = ref.watch(
      macosGlassRootBackgroundProvider(View.of(context).viewId),
    );
    final palettes = ref.watch(
      appThemeSettingsProvider.select(
        (settings) => (settings.activeTheme.light, settings.activeTheme.dark),
      ),
    );
    final lightTheme = AppTheme.light(palette: palettes.$1);
    final darkTheme = AppTheme.dark(palette: palettes.$2);
    return ShadApp.custom(
      theme: AppTheme.shadFromMaterial(lightTheme),
      darkTheme: AppTheme.shadFromMaterial(darkTheme),
      themeMode: themeMode.themeMode,
      appBuilder: (context) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode.themeMode,
        themeAnimationDuration: AppMotion.duration(context, AppMotion.state),
        themeAnimationCurve: AppMotion.curve,
        locale: resolveAppLocale(language),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalShadLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: AppTheme.shadFromMaterial(
            Theme.of(context),
            reduceMotion: MediaQuery.disableAnimationsOf(context),
          ),
          child: MacosGlassHost(
            child: AppZoom(
              child: ShadAppBuilder(
                backgroundColor: rootBackground,
                child: ShortcutHintsHost(
                  child: KeyboardDismissRegion(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
        home: _QuickAddWindowFocus(
          key: const Key('global-quick-add-focus'),
          builder: (inputFocus) => ThemeBackground(
            zone: ThemeBackgroundZone.quickAdd,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: QuickAddComposer(
                  focusNode: inputFocus,
                  onCompleted: onClose,
                  onCancel: onClose,
                  onVoiceModeChanged: onVoiceModeChanged,
                  onCommentExpandedChanged: onCommentExpandedChanged,
                  onEditorModeChanged: onEditorModeChanged,
                  onPreferredWidthChanged: (width) {
                    final view = View.of(context);
                    onPreferredWidthChanged?.call(
                      width * ref.read(appZoomProvider) / 100,
                      view.physicalSize.width / view.devicePixelRatio,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Native activation and Flutter's shared-engine keyboard scope are independent.
// Keep the composer in this window's scope when a different view last had focus.
class _QuickAddWindowFocus extends StatefulWidget {
  const _QuickAddWindowFocus({required this.builder, super.key});
  final Widget Function(FocusNode) builder;

  @override
  State<_QuickAddWindowFocus> createState() => _QuickAddWindowFocusState();
}

class _QuickAddWindowFocusState extends State<_QuickAddWindowFocus>
    with WindowListener {
  final _inputFocus = FocusNode(debugLabel: 'Global Quick Add input');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  @override
  void onWindowFocus() {
    final inputContext = _inputFocus.context;
    if (inputContext != null &&
        ModalRoute.of(inputContext)?.isCurrent == true) {
      _inputFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_inputFocus);
}
