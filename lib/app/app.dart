import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadApp, ShadAppBuilder, ShadTheme, GlobalShadLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

import '../features/updates/update_widgets.dart';
import 'app_language.dart';
import 'app_zoom.dart';
import 'platform_quick_add.dart';
import 'app_theme_mode.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_settings.dart';
import 'theme/app_motion.dart';

class PomodoistApp extends ConsumerWidget {
  const PomodoistApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(platformQuickAddControllerProvider);
    final router = ref.watch(routerProvider);
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(appThemeModeProvider);
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
          child: AppZoom(
            child: ShadAppBuilder(
              child: DesktopUpdateHost(child: child ?? const SizedBox.shrink()),
            ),
          ),
        ),
        locale: language.locale,
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
