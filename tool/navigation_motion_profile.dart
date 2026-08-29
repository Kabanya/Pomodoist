import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/router.dart';
import 'package:pomodoist/app/runtime_public_config.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/onboarding/onboarding_gate.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_motion_profile_result_stub.dart'
    if (dart.library.js_interop) 'task_motion_profile_result_web.dart';
import 'navigation_motion_profile_database_web.dart'
    if (dart.library.io) 'navigation_motion_profile_database_native.dart';

const _baseline = bool.fromEnvironment('NAVIGATION_MOTION_BASELINE');
const _repetitions = 20;
const _taskId = 'navigation-profile-task-0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(onboardingCompletedPreferenceKey, true);
  final database = createNavigationProfileDatabase();
  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        runtimePublicConfigProvider.overrideWithValue(
          RuntimePublicConfig.fromBuildTime(),
        ),
        accountAuthStateProvider.overrideWith(
          (ref) => Stream.value(const AccountAuthState(signedIn: true)),
        ),
        appStartupProvider.overrideWith((ref) async {
          await database.ensureSeedData();
          await _seedTasks(database);
        }),
      ],
      child: const _NavigationMotionProfile(),
    ),
  );
}

class _NavigationMotionProfile extends ConsumerStatefulWidget {
  const _NavigationMotionProfile();

  @override
  ConsumerState<_NavigationMotionProfile> createState() =>
      _NavigationMotionProfileState();
}

class _NavigationMotionProfileState
    extends ConsumerState<_NavigationMotionProfile> {
  final _timings = <FrameTiming>[];
  final _results = <String>[];
  late final TimingsCallback _timingsCallback;
  var _collecting = false;

  @override
  void initState() {
    super.initState();
    _timingsCallback = (timings) {
      if (_collecting) _timings.addAll(timings);
    };
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final router = ref.read(routerProvider);
    await _measurePair(router, 'todayTimeline', '/today', '/timeline');
    await _measurePair(router, 'timelineKanban', '/timeline', '/kanban');
    await _measurePair(router, 'kanbanReports', '/kanban', '/reports');
    await _measureTaskDetail(router);
    final result = '${_baseline ? 'baseline' : 'motion'}|${_results.join('|')}';
    publishTaskMotionProfileResult(result);
    debugPrint('NAVIGATION_MOTION_PROFILE_DONE $result');
  }

  Future<void> _measurePair(
    GoRouter router,
    String name,
    String first,
    String second,
  ) async {
    router.go(first);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _timings.clear();
    _collecting = true;
    for (var index = 0; index < _repetitions; index++) {
      router.go(index.isEven ? second : first);
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }
    _collecting = false;
    _record(name);
  }

  Future<void> _measureTaskDetail(GoRouter router) async {
    router.go('/today');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _timings.clear();
    _collecting = true;
    for (var index = 0; index < _repetitions; index++) {
      router.go('/task/$_taskId');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      router.go('/today');
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }
    _collecting = false;
    _record('taskDetail');
  }

  void _record(String name) {
    final build = _timings
        .map((timing) => timing.buildDuration.inMicroseconds)
        .toList();
    final raster = _timings
        .map((timing) => timing.rasterDuration.inMicroseconds)
        .toList();
    final refreshRate = View.of(context).display.refreshRate;
    final budget = (Duration.microsecondsPerSecond / refreshRate).round();
    final overBudget = _timings.where((timing) {
      return timing.buildDuration.inMicroseconds > budget ||
          timing.rasterDuration.inMicroseconds > budget;
    }).length;
    _results.add(
      '$name:${_timings.length},${_p95(build)},${_p95(raster)},$overBudget',
    );
  }

  int _p95(List<int> values) {
    if (values.isEmpty) return 0;
    values.sort();
    return values[((values.length - 1) * 0.95).ceil()];
  }
}

Future<void> _seedTasks(AppDatabase database) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  await database.batch((batch) {
    batch.insertAllOnConflictUpdate(database.tasks, [
      for (var index = 0; index < 500; index++)
        TasksCompanion.insert(
          id: 'navigation-profile-task-$index',
          userId: localUserId,
          content: 'Navigation profile task $index',
          projectId: inboxProjectId,
          dueJson: drift.Value(_profileSchedule(index, today)),
          orderKey: index.toString().padLeft(4, '0'),
          createdAt: now.toUtc(),
          updatedAt: now.toUtc(),
        ),
    ]);
  });
}

String _profileSchedule(int index, DateTime today) {
  final date = today.add(Duration(days: (index % 60) - 30));
  if (index.isEven) return TaskSchedule.allDay(date).toJsonString();
  final start = date.add(
    Duration(hours: 8 + (index % 10), minutes: index % 60),
  );
  return TaskSchedule.timed(
    start: start,
    end: start.add(const Duration(minutes: 30)),
  ).toJsonString();
}
