// Run with flutter run --profile -d macos --flavor staging -t tool/pomo_resource_profile.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pomodoist/config/pomo_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/ui/core/widgets/pomodoist_app.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
// shortcut: uses Thermion 0.5.0 scheduler diagnostics; revisit on renderer upgrades.
// ignore: implementation_imports
import 'package:thermion_flutter/src/platform/src/frame_scheduler.dart';

final _frames = <FrameTiming>[];
final _errors = <String>[];
var _recording = false;
var _mode = 'hidden';

Future<void> main() async {
  if (!kProfileMode) {
    throw StateError('Use --profile for resource measurements');
  }
  WidgetsFlutterBinding.ensureInitialized();
  // The platform mock and temporary database keep measurements off user data.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'onboarding.completed.v1': true});
  final directory = await Directory.systemTemp.createTemp('pomo-resource-');
  final database = AppDatabase(
    NativeDatabase(File('${directory.path}/app.db')),
  );
  final container = ProviderContainer(
    overrides: [
      ...pomoOverrides,
      appDatabaseProvider.overrideWithValue(database),
    ],
  );
  FlutterError.onError = (details) {
    _errors.add(details.exceptionAsString());
    FlutterError.presentError(details);
  };
  SchedulerBinding.instance.addTimingsCallback((frames) {
    if (_recording) _frames.addAll(frames);
  });
  registerExtension('ext.pomodoist.resourceProfile', (_, parameters) async {
    if (parameters['mode'] case final String mode) {
      if (!{'hidden', 'animated', 'static'}.contains(mode)) {
        throw ArgumentError.value(mode, 'mode');
      }
      _mode = mode;
      await container
          .read(pomoPreferencesProvider)
          .update(
            (p) => p.copyWith(
              enabled: mode != 'hidden',
              dismissed: false,
              focusOnly: false,
              quiet: mode == 'static',
              reduceMotion: false,
              scale: 1,
            ),
          );
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (parameters['record'] == 'true') {
      _frames.clear();
      _recording = true;
    } else if (parameters['record'] == 'false') {
      _recording = false;
    }
    final widgets = <String, int>{};
    void visit(Element element) {
      final name = element.widget.runtimeType.toString();
      widgets[name] = (widgets[name] ?? 0) + 1;
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    final controller = container.read(pomoControllerProvider);
    return ServiceExtensionResponse.result(
      jsonEncode({
        'mode': _mode,
        'pid': pid,
        'visible': controller.visible,
        'animated': controller.animated,
        'emotion': controller.emotion.name,
        'error': controller.error?.toString(),
        'flutterErrors': _errors,
        'nativeScheduler': {
          'active': FrameScheduler.instance.isActive,
          'paused': FrameScheduler.instance.isPaused,
          'scheduledFrames': FrameScheduler.instance.scheduledFrameCount,
        },
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'widgets': {
          for (final name in [
            'TodayScreen',
            'OnboardingScreen',
            '_StartupLoading',
            '_StartupError',
            'PomoModel',
            'Texture',
          ])
            name: widgets[name] ?? 0,
        },
        'views': [
          for (final view in PlatformDispatcher.instance.views)
            {
              'id': view.viewId,
              'width': view.physicalSize.width,
              'height': view.physicalSize.height,
              'dpr': view.devicePixelRatio,
            },
        ],
        'frames': [
          for (final frame in _frames)
            {
              'buildUs': frame.buildDuration.inMicroseconds,
              'rasterUs': frame.rasterDuration.inMicroseconds,
              'totalUs': frame.totalSpan.inMicroseconds,
            },
        ],
      }),
    );
  });
  runMultiApp(
    home: (_, _) => const PomodoistApp(),
    globalScope: (child) => UncontrolledProviderScope(
      container: container,
      child: PomoRuntime(child: child),
    ),
    config: MultiAppConfig(
      globalWindowOptions: const WindowOptions(
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
      ),
      macosParams: const MacosPlatformParams(
        closeAppAfterLastWindowClosed: false,
      ),
    ),
  );
}
