import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadApp, ShadAppBuilder, ShadTheme, GlobalShadLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

import 'package:pomodoist/ui/updates/widgets/update_widgets.dart';
import 'package:pomodoist/ui/core/localization/app_locale.dart';
import 'package:pomodoist/ui/core/widgets/app_zoom.dart';
import 'package:pomodoist/ui/core/view_models/app_view_model.dart';
import 'package:pomodoist/ui/core/view_models/app_theme_mode_view_model.dart';
import 'package:pomodoist/routing/router.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/macos_glass.dart';
import 'package:pomodoist/ui/core/widgets/keyboard_dismiss_region.dart';

class PomodoistApp extends ConsumerWidget {
  const PomodoistApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appViewModelProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final router = ref.watch(routerProvider);
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
      appBuilder: (context) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode.themeMode,
        themeAnimationDuration: AppMotion.duration(context, AppMotion.state),
        themeAnimationCurve: AppMotion.curve,
        routerConfig: router,
        builder: (context, child) => ShadTheme(
          data: AppTheme.shadFromMaterial(
            Theme.of(context),
            reduceMotion: MediaQuery.disableAnimationsOf(context),
          ),
          child: MacosGlassHost(
            child: AppZoom(
              child: ShadAppBuilder(
                backgroundColor: rootBackground,
                child: KeyboardDismissRegion(
                  child: DesktopUpdateHost(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
        locale: resolveAppLocale(app.language),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalShadLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}
