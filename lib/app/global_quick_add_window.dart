import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import '../features/tasks/presentation/widgets/quick_add_bar.dart';
import '../l10n/app_localizations.dart';
import 'app_l10n.dart';
import 'app_language.dart';
import 'app_theme_mode.dart';
import 'theme/app_theme.dart';

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
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode.themeMode,
      locale: language.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
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
    );
  }
}
