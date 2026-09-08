import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadApp, ShadAppBuilder, ShadTheme, GlobalShadLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import '../features/tasks/presentation/widgets/quick_add_bar.dart';
import '../l10n/app_localizations.dart';
import 'app_l10n.dart';
import 'app_language.dart';
import 'app_theme_mode.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_settings.dart';
import 'theme/app_motion.dart';

const globalQuickAddCompactSize = Size(600, 300);
const globalQuickAddVoiceSize = Size(720, 720);

final globalQuickAddWindowManager = GlobalQuickAddWindowManager();

class GlobalQuickAddWindowManager extends WindowObserver {
  int? _viewId;
  Future<int>? _opening;

  Future<void> show() async {
    final existingId = _viewId;
    if (existingId != null &&
        MultiViewDesktop.allWindowViewIds.contains(existingId)) {
      final window = MultiViewDesktop.fromId(existingId);
      await window.show();
      await window.focus();
      return;
    }

    final pending = _opening;
    if (pending != null) {
      final id = await pending;
      await MultiViewDesktop.fromId(id).focus();
      return;
    }

    final opening = openWindow(
      (context, id) => GlobalQuickAddWindowApp(
        onClose: () => unawaited(close()),
        onVoiceModeChanged: (active) => unawaited(setVoiceMode(active)),
      ),
      options: const WindowOptions(
        size: globalQuickAddCompactSize,
        minimumSize: Size(420, 260),
        maximumSize: Size(900, 800),
        title: 'Pomodoist',
        alwaysOnTop: true,
      ),
    );
    _opening = opening;
    try {
      _viewId = await opening;
    } finally {
      _opening = null;
    }
  }

  Future<void> close() async {
    final id = _viewId;
    _viewId = null;
    if (id != null && MultiViewDesktop.allWindowViewIds.contains(id)) {
      await MultiViewDesktop.fromId(id).closeWindow();
    }
  }

  Future<void> setVoiceMode(bool active) async {
    final id = _viewId;
    if (id == null || !MultiViewDesktop.allWindowViewIds.contains(id)) return;
    await MultiViewDesktop.fromId(
      id,
    ).setSize(active ? globalQuickAddVoiceSize : globalQuickAddCompactSize);
  }

  @override
  void onWindowClosed(int viewId) {
    if (_viewId == viewId) _viewId = null;
  }
}

class GlobalQuickAddWindowApp extends ConsumerWidget {
  const GlobalQuickAddWindowApp({
    required this.onClose,
    required this.onVoiceModeChanged,
    super.key,
  });

  final VoidCallback onClose;
  final ValueChanged<bool> onVoiceModeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      appBuilder: (context) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode.themeMode,
        themeAnimationDuration: AppMotion.duration(context, AppMotion.state),
        themeAnimationCurve: AppMotion.curve,
        locale: language.locale,
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
          child: ShadAppBuilder(child: child),
        ),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Builder(
                builder: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.addTask,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 18),
                    QuickAddComposer(
                      onCompleted: onClose,
                      onCancel: onClose,
                      onVoiceModeChanged: onVoiceModeChanged,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
