import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_screen.dart';
import 'package:pomodoist/features/focus/presentation/focus_rhythm.dart';
import 'package:pomodoist/features/focus/presentation/focus_rhythm_rail.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
  });

  testWidgets('full idle uses responsive base-surface cycle stage', (
    tester,
  ) async {
    final repository = _FocusRepository();

    await _pumpFocusScreen(
      tester,
      repository: repository,
      size: const Size(719, 900),
    );

    expect(find.byKey(const Key('focus-layout-compact')), findsOneWidget);
    expect(find.byKey(const Key('focus-layout-desktop')), findsNothing);
    expect(find.byKey(const Key('focus-content-full')), findsOneWidget);
    expect(find.byKey(const Key('focus-state-idle')), findsOneWidget);
    expect(find.byKey(const Key('focus-primary-stage')), findsOneWidget);
    expect(find.byKey(const Key('focus-rhythm-rail')), findsOneWidget);
    for (var sequence = 1; sequence <= 8; sequence++) {
      expect(
        find.byKey(ValueKey('focus-rhythm-step-$sequence')),
        findsOneWidget,
      );
    }
    expect(find.byType(Card), findsNothing);
    expect(find.text('Start focus'), findsOneWidget);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('New preset'), findsOneWidget);

    tester.view.physicalSize = const Size(720, 900);
    await tester.pump();

    expect(find.byKey(const Key('focus-layout-desktop')), findsOneWidget);
    expect(find.byKey(const Key('focus-layout-compact')), findsNothing);
  });

  testWidgets('minimal idle keeps compact launch controls on base surface', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(),
      size: const Size(390, 844),
    );

    expect(find.byKey(const Key('focus-content-minimal')), findsOneWidget);
    expect(find.byKey(const Key('focus-state-idle')), findsOneWidget);
    expect(find.byKey(const Key('focus-primary-stage')), findsOneWidget);
    expect(find.byKey(const Key('focus-primary-action')), findsOneWidget);
    expect(find.byKey(const Key('minimal-preset-menu')), findsOneWidget);
    expect(find.byKey(const Key('minimal-preset-select')), findsNothing);
    expect(find.byKey(const Key('minimal-idle-more-menu')), findsNothing);
    expect(find.text('Classic'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.text('25m work'), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);
    expect(find.byKey(const Key('focus-rhythm-rail')), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('full and minimal idle timer icons use neutral color', (
    tester,
  ) async {
    for (final mode in FocusViewMode.values) {
      await tester.pumpWidget(const SizedBox.shrink());
      SharedPreferences.setMockInitialValues({
        focusViewModePreferenceKey: mode.storageValue,
      });
      await _pumpFocusScreen(
        tester,
        repository: _FocusRepository(),
        size: const Size(390, 844),
      );

      final stage = find.byKey(const Key('focus-primary-stage'));
      final idleIcon = tester.widget<Icon>(
        find.descendant(of: stage, matching: find.byIcon(Icons.timer_outlined)),
      );
      final context = tester.element(find.byType(FocusScreen));
      expect(idleIcon.color, context.appColors.mutedText);
    }
  });

  testWidgets('idle rhythm preview keeps every step neutral', (tester) async {
    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(),
      size: const Size(390, 844),
    );

    final node = tester.widget<Container>(
      find.byKey(const ValueKey('focus-rhythm-node-1')),
    );
    final decoration = node.decoration! as BoxDecoration;
    final context = tester.element(find.byType(FocusScreen));
    expect(decoration.color, context.appColors.surfaceHover);
    expect(decoration.border?.top.color, context.appColors.border);
  });

  testWidgets('active rail mark meets non-text contrast in dark theme', (
    tester,
  ) async {
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: FocusRhythmRail(
              rhythm: rhythm,
              semanticsLabel: 'Cycle',
              compact: false,
              activeSequence: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final step = find.byKey(const ValueKey('focus-rhythm-step-1'));
    final node = tester.widget<Container>(
      find.byKey(const ValueKey('focus-rhythm-node-1')),
    );
    final decoration = node.decoration! as BoxDecoration;
    final mark = tester.widget<Text>(
      find.descendant(of: step, matching: find.text('1')),
    );
    expect(
      _contrastRatio(mark.style!.color!, decoration.color!),
      greaterThanOrEqualTo(3),
    );
  });

  testWidgets('partial active data renders transition instead of idle', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final repository = _FocusRepository(activeRun: _run(now));

    await _pumpFocusScreen(
      tester,
      repository: repository,
      size: const Size(390, 844),
    );

    expect(find.byKey(const Key('focus-state-transition')), findsOneWidget);
    expect(find.byKey(const Key('focus-state-idle')), findsNothing);
    expect(find.text('No active session'), findsNothing);
    expect(find.byKey(const Key('focus-view-mode-toggle')), findsOneWidget);
  });

  testWidgets('full active uses rhythm timer and desktop action hierarchy', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(
      now,
      status: 'running',
      startedAt: now.subtract(const Duration(seconds: 42)),
    );
    final repository = _FocusRepository(
      activeRun: _run(now),
      activeInterval: interval,
      intervals: [interval],
    );

    await _pumpFocusScreen(
      tester,
      repository: repository,
      size: const Size(1200, 900),
      now: now,
    );

    expect(find.byKey(const Key('focus-state-active')), findsOneWidget);
    expect(find.byKey(const Key('focus-primary-stage')), findsOneWidget);
    expect(find.byKey(const Key('focus-rhythm-rail')), findsOneWidget);
    expect(find.byKey(const Key('focus-circular-timer')), findsOneWidget);
    expect(find.text('Work interval'), findsOneWidget);
    expect(find.text('24:18'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Complete interval'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('focus-details-menu')), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Log distraction'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('full ready keeps Complete interval visible but unavailable', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'ready');

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: _run(now),
        activeInterval: interval,
        intervals: [interval],
      ),
      size: const Size(1200, 900),
      now: now,
    );

    expect(find.widgetWithText(FilledButton, 'Start interval'), findsOneWidget);
    final complete = find.widgetWithText(OutlinedButton, 'Complete interval');
    expect(complete, findsOneWidget);
    expect(tester.widget<OutlinedButton>(complete).onPressed, isNull);
  });

  testWidgets('strict no-pause preset explains and disables blocked actions', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');
    final preset = _preset(allowPause: false, strictMode: true);

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: _run(now),
        activeInterval: interval,
        intervals: [interval],
        presets: [preset],
      ),
      size: const Size(1200, 900),
      now: now,
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Pause unavailable for this preset',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Pause'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Complete interval'),
          )
          .onPressed,
      isNull,
    );

    final menu = find.byKey(const Key('focus-details-menu'));
    await tester.ensureVisible(menu);
    await tester.pump();
    await tester.tap(
      find.descendant(of: menu, matching: find.byIcon(Icons.more_horiz)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsOneWidget);
    final skipItem = find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuItem &&
          widget.child is Text &&
          (widget.child! as Text).data == 'Skip',
    );
    expect(skipItem, findsOneWidget);
    expect(tester.widget<PopupMenuItem<dynamic>>(skipItem).enabled, isFalse);
  });

  testWidgets('full paused session can resume with a no-pause preset', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'paused', pausedAt: now);
    final repository = _FocusRepository(
      activeRun: _run(now),
      activeInterval: interval,
      intervals: [interval],
      presets: [_preset(allowPause: false)],
    );

    await _pumpFocusScreen(
      tester,
      repository: repository,
      size: const Size(1200, 900),
      now: now,
    );

    final resume = find.widgetWithText(FilledButton, 'Resume');
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
    await tester.tap(resume);
    await tester.pump();

    expect(repository.resumeCount, 1);
    expect(find.text('Pause unavailable for this preset'), findsNothing);
  });

  testWidgets('minimal active renders only phase timer and primary action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: _run(now),
        activeInterval: interval,
        intervals: [interval],
      ),
      size: const Size(390, 844),
      now: now,
    );

    expect(find.byKey(const Key('focus-content-minimal')), findsOneWidget);
    expect(find.byKey(const Key('focus-state-active')), findsOneWidget);
    expect(find.byKey(const Key('focus-primary-stage')), findsOneWidget);
    expect(find.byKey(const Key('focus-circular-timer')), findsOneWidget);
    expect(find.text('Work interval'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.byKey(const Key('focus-rhythm-rail')), findsNothing);
    expect(find.byKey(const Key('focus-task-context')), findsNothing);
    expect(find.byKey(const Key('focus-details-menu')), findsNothing);
    expect(find.byKey(const Key('minimal-active-more-menu')), findsNothing);
    expect(find.text('Classic'), findsNothing);
    expect(find.text('Complete interval'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('minimal paused session can resume with a no-pause preset', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'paused', pausedAt: now);
    final repository = _FocusRepository(
      activeRun: _run(now),
      activeInterval: interval,
      intervals: [interval],
      presets: [_preset(allowPause: false)],
    );

    await _pumpFocusScreen(
      tester,
      repository: repository,
      size: const Size(390, 844),
      now: now,
    );

    final resume = find.widgetWithText(FilledButton, 'Resume');
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
    await tester.tap(resume);
    await tester.pump();

    expect(repository.resumeCount, 1);
    expect(find.text('Pause unavailable for this preset'), findsNothing);
  });

  testWidgets('mode toggle swaps active hierarchy and persists Minimal', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');
    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: _run(now),
        activeInterval: interval,
        intervals: [interval],
      ),
      size: const Size(1200, 900),
      now: now,
    );

    expect(find.byKey(const Key('focus-content-full')), findsOneWidget);
    expect(find.byKey(const Key('focus-rhythm-rail')), findsOneWidget);
    final toggle = find.byKey(const Key('focus-view-mode-toggle'));
    await tester.tap(
      find.descendant(of: toggle, matching: find.text('Minimal')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('focus-content-minimal')), findsOneWidget);
    expect(find.byKey(const Key('focus-rhythm-rail')), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(focusViewModePreferenceKey),
      FocusViewMode.minimal.storageValue,
    );
  });

  testWidgets('keyboard traversal reaches and activates the primary action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');
    final repository = _FocusRepository(
      activeRun: _run(now),
      activeInterval: interval,
      intervals: [interval],
    );
    await _pumpFocusScreen(
      tester,
      repository: repository,
      size: const Size(1200, 900),
      now: now,
    );

    final primary = find.byKey(const Key('focus-primary-action'));
    var reachedPrimary = false;
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (_focusIsWithin(tester, primary)) {
        reachedPrimary = true;
        break;
      }
    }
    expect(reachedPrimary, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(repository.pauseCount, 1);
  });

  testWidgets('resolved linked task shows project and opens task route', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');
    final task = _task(now);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: FocusScreen()),
        ),
        GoRoute(
          path: '/task/:id',
          builder: (context, state) =>
              Text('Task route ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await _pumpLinkedFocusScreen(
      tester,
      router: router,
      focusRepository: _FocusRepository(
        activeRun: _run(now, taskId: task.id),
        activeInterval: interval,
        intervals: [interval],
      ),
      taskRepository: _TaskRepository(task),
      projectRepository: _ProjectRepository([_project(now)]),
      now: now,
    );

    expect(find.byKey(const Key('focus-task-context')), findsOneWidget);
    expect(find.text(task.content), findsOneWidget);
    expect(find.text('# Product Launch'), findsOneWidget);

    final linkedTask = find.byKey(const Key('focus-linked-task'));
    await tester.ensureVisible(linkedTask);
    await tester.pump();
    tester.widget<TextButton>(linkedTask).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Task route ${task.id}'), findsOneWidget);
  });

  testWidgets('project context keeps only its marker colored in both themes', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');
    final task = _task(now);

    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await _pumpFocusScreen(
        tester,
        repository: _FocusRepository(
          activeRun: _run(now, taskId: task.id),
          activeInterval: interval,
          intervals: [interval],
        ),
        size: const Size(1200, 900),
        now: now,
        taskRepository: _TaskRepository(task),
        projectRepository: _ProjectRepository([_project(now)]),
        theme: theme,
      );
      await tester.pumpAndSettle();

      final projectText = tester.widget<Text>(
        find.byKey(const Key('focus-project-context')),
      );
      expect(projectText.textSpan, isA<TextSpan>());
      final span = projectText.textSpan as TextSpan;
      final marker = span.children![0] as TextSpan;
      final name = span.children![1] as TextSpan;
      final context = tester.element(find.byType(FocusScreen));

      expect(marker.text, '#');
      expect(marker.style?.color, const Color(0xFFE8793E));
      expect(name.text, ' Product Launch');
      expect(name.style?.color, context.appColors.secondaryText);
      expect(
        _contrastRatio(name.style!.color!, context.appColors.canvas),
        greaterThanOrEqualTo(4.5),
        reason: 'name=${name.style!.color}, canvas=${context.appColors.canvas}',
      );
    }
  });

  testWidgets('missing project keeps task while deleted task hides context', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');
    final run = _run(now, taskId: 'task-1');

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: run,
        activeInterval: interval,
        intervals: [interval],
      ),
      size: const Size(1200, 900),
      now: now,
      taskRepository: _TaskRepository(_task(now)),
      projectRepository: _ProjectRepository(const []),
    );

    expect(find.byKey(const Key('focus-task-context')), findsOneWidget);
    expect(find.byKey(const Key('focus-project-context')), findsNothing);

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: run,
        activeInterval: interval,
        intervals: [interval],
      ),
      size: const Size(1200, 900),
      now: now,
      taskRepository: _TaskRepository(_task(now, isDeleted: true)),
      projectRepository: _ProjectRepository([_project(now)]),
    );

    expect(find.byKey(const Key('focus-task-context')), findsNothing);
    expect(find.byKey(const Key('focus-project-context')), findsNothing);
  });

  testWidgets('base-surface stage supplies its own Material ancestor', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FocusRepository()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const FocusScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('focus-state-idle')), findsOneWidget);
  });

  testWidgets('phase styling uses tokens plus text icon and primary state', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);

    Future<void> expectPhase({
      required String type,
      required String status,
      required String label,
      required IconData icon,
      required Color Function(AppThemePalette colors) color,
      required String primary,
    }) async {
      SharedPreferences.setMockInitialValues({
        focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
      });
      final interval = _interval(
        now,
        type: type,
        status: status,
        pausedAt: status == 'paused' ? now : null,
      );
      await _pumpFocusScreen(
        tester,
        repository: _FocusRepository(
          activeRun: _run(now),
          activeInterval: interval,
          intervals: [interval],
        ),
        size: const Size(390, 844),
        now: now,
      );

      final context = tester.element(find.byType(FocusScreen));
      expect(find.byKey(const Key('focus-phase-label')), findsOneWidget);
      final phaseText = tester.widget<Text>(
        find.byKey(const Key('focus-phase-label')),
      );
      expect(phaseText.data, label);
      expect(phaseText.style?.color, color(context.appColors));
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.widgetWithText(FilledButton, primary), findsOneWidget);
    }

    await expectPhase(
      type: 'work',
      status: 'running',
      label: 'Work interval',
      icon: Icons.timer_outlined,
      color: (colors) => colors.accent,
      primary: 'Pause',
    );
    await expectPhase(
      type: 'shortBreak',
      status: 'running',
      label: 'Short break',
      icon: Icons.coffee_outlined,
      color: (colors) => colors.info,
      primary: 'Pause',
    );
    await expectPhase(
      type: 'longBreak',
      status: 'running',
      label: 'Long break',
      icon: Icons.schedule,
      color: (colors) => colors.info,
      primary: 'Pause',
    );
    await expectPhase(
      type: 'work',
      status: 'paused',
      label: 'Work interval',
      icon: Icons.timer_outlined,
      color: (colors) => colors.warning,
      primary: 'Resume',
    );
    await expectPhase(
      type: 'work',
      status: 'ready',
      label: 'Ready: Work interval',
      icon: Icons.timer_outlined,
      color: (colors) => colors.accent,
      primary: 'Start interval',
    );
  });

  testWidgets('lagged history merges the authoritative active interval', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final completedWork = _interval(
      now,
      status: 'completed',
      sequence: 1,
      startedAt: now.subtract(const Duration(minutes: 25)),
    );
    final activeBreak = _interval(
      now,
      status: 'paused',
      type: 'shortBreak',
      sequence: 2,
      pausedAt: now,
    );

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: _run(now, completedWorkIntervals: 1),
        activeInterval: activeBreak,
        intervals: [completedWork],
      ),
      size: const Size(1200, 900),
      now: now,
    );

    final activeNode = find.byKey(const ValueKey('focus-rhythm-node-2'));
    expect(activeNode, findsOneWidget);
    final node = tester.widget<Container>(activeNode);
    final decoration = node.decoration! as BoxDecoration;
    final context = tester.element(find.byType(FocusScreen));
    expect(decoration.color, context.appColors.warning);
  });

  testWidgets('non-overflowing rhythm never moves the outer stage scroll', (
    tester,
  ) async {
    final outerController = ScrollController();
    addTearDown(outerController.dispose);
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: outerController,
            child: Column(
              children: [
                const SizedBox(height: 1000),
                SizedBox(
                  width: 600,
                  child: FocusRhythmRail(
                    rhythm: rhythm,
                    semanticsLabel: 'Cycle preview',
                    compact: false,
                    activeSequence: rhythm.steps.last.sequence,
                  ),
                ),
                const SizedBox(height: 700),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(outerController.offset, 0);
  });

  testWidgets('overflow centering stays inside the horizontal rhythm rail', (
    tester,
  ) async {
    final outerController = ScrollController();
    addTearDown(outerController.dispose);
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 12,
    );
    final activeSequence = rhythm.steps[12].sequence;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: outerController,
            child: Column(
              children: [
                const SizedBox(height: 1000),
                SizedBox(
                  key: const Key('rail-host'),
                  width: 260,
                  child: FocusRhythmRail(
                    rhythm: rhythm,
                    semanticsLabel: 'Cycle preview',
                    compact: true,
                    activeSequence: activeSequence,
                  ),
                ),
                const SizedBox(height: 700),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(outerController.offset, 0);
    expect(
      tester
          .getCenter(find.byKey(ValueKey('focus-rhythm-step-$activeSequence')))
          .dx,
      moreOrLessEquals(
        tester.getCenter(find.byKey(const Key('rail-host'))).dx,
        epsilon: 2,
      ),
    );
  });

  testWidgets('rail recenters when a same-shape run token changes', (
    tester,
  ) async {
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 12,
    );
    final activeSequence = rhythm.steps[12].sequence;
    final runToken = ValueNotifier<String>('run-1');
    addTearDown(runToken.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: const Key('recenter-host'),
              width: 260,
              child: ValueListenableBuilder<String>(
                valueListenable: runToken,
                builder: (context, token, child) => FocusRhythmRail(
                  rhythm: rhythm,
                  semanticsLabel: 'Cycle preview',
                  compact: true,
                  activeSequence: activeSequence,
                  recenterToken: token,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final activeStep = find.byKey(
      ValueKey('focus-rhythm-step-$activeSequence'),
    );
    final host = find.byKey(const Key('recenter-host'));
    expect(
      tester.getCenter(activeStep).dx,
      moreOrLessEquals(tester.getCenter(host).dx, epsilon: 2),
    );

    await tester.drag(
      find.byKey(const Key('focus-rhythm-rail')),
      const Offset(180, 0),
    );
    await tester.pump();
    expect(
      (tester.getCenter(activeStep).dx - tester.getCenter(host).dx).abs(),
      greaterThan(20),
    );

    runToken.value = 'run-2';
    await tester.pump();
    await tester.pump();
    expect(
      tester.getCenter(activeStep).dx,
      moreOrLessEquals(tester.getCenter(host).dx, epsilon: 2),
    );
  });

  testWidgets('RTL leading connector points toward the preceding step', (
    tester,
  ) async {
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              width: 600,
              child: FocusRhythmRail(
                rhythm: rhythm,
                semanticsLabel: 'Cycle preview',
                compact: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final firstCenter = tester.getCenter(
      find.byKey(const ValueKey('focus-rhythm-step-1')),
    );
    final secondCenter = tester.getCenter(
      find.byKey(const ValueKey('focus-rhythm-step-2')),
    );
    final connector = find.byKey(const ValueKey('focus-rhythm-connector-2'));
    expect(connector, findsOneWidget);
    final connectorCenter = tester.getCenter(connector);
    expect(firstCenter.dx, greaterThan(secondCenter.dx));
    expect(connectorCenter.dx, greaterThan(secondCenter.dx));
    expect(connectorCenter.dx, lessThan(firstCenter.dx));
  });

  testWidgets('active rhythm connector points only toward the future', (
    tester,
  ) async {
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: FocusRhythmRail(
              rhythm: rhythm,
              semanticsLabel: 'Cycle preview',
              compact: false,
              activeSequence: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(FocusRhythmRail));
    final leading = tester.widget<Divider>(
      find.descendant(
        of: find.byKey(const ValueKey('focus-rhythm-connector-3')),
        matching: find.byType(Divider),
      ),
    );
    final trailing = tester.widget<Divider>(
      find.descendant(
        of: find.byKey(const ValueKey('focus-rhythm-trailing-connector-3')),
        matching: find.byType(Divider),
      ),
    );

    expect(leading.color, context.appColors.border);
    expect(leading.thickness, 1);
    expect(trailing.color, context.appColors.accent);
    expect(trailing.thickness, 2);
  });

  testWidgets('active phase colors the full connector to the next step', (
    tester,
  ) async {
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 2,
    );

    for (final activeSequence in [1, 2]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: FocusRhythmRail(
                rhythm: rhythm,
                semanticsLabel: 'Cycle preview',
                compact: false,
                activeSequence: activeSequence,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(FocusRhythmRail));
      final expectedColor = activeSequence == 1
          ? context.appColors.accent
          : context.appColors.info;
      final trailing = tester.widget<Divider>(
        find.descendant(
          of: find.byKey(
            ValueKey('focus-rhythm-trailing-connector-$activeSequence'),
          ),
          matching: find.byType(Divider),
        ),
      );
      final leading = tester.widget<Divider>(
        find.descendant(
          of: find.byKey(
            ValueKey('focus-rhythm-connector-${activeSequence + 1}'),
          ),
          matching: find.byType(Divider),
        ),
      );

      expect(trailing.color, expectedColor);
      expect(trailing.thickness, 2);
      expect(leading.color, expectedColor);
      expect(leading.thickness, 2);
    }
  });

  testWidgets('connector halves meet between adjacent steps in LTR and RTL', (
    tester,
  ) async {
    final rhythm = buildFocusRhythm(
      preset: _classicPreset,
      targetWorkIntervals: 1,
    );

    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Directionality(
              textDirection: direction,
              child: SizedBox(
                width: 600,
                child: FocusRhythmRail(
                  rhythm: rhythm,
                  semanticsLabel: 'Cycle preview',
                  compact: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final firstCenter = tester.getCenter(
        find.byKey(const ValueKey('focus-rhythm-step-1')),
      );
      final secondCenter = tester.getCenter(
        find.byKey(const ValueKey('focus-rhythm-step-2')),
      );
      final trailing = find.byKey(
        const ValueKey('focus-rhythm-trailing-connector-1'),
      );
      final leading = find.byKey(const ValueKey('focus-rhythm-connector-2'));

      expect(trailing, findsOneWidget);
      expect(leading, findsOneWidget);
      final trailingRect = tester.getRect(trailing);
      final leadingRect = tester.getRect(leading);
      final leftHalf = trailingRect.left < leadingRect.left
          ? trailingRect
          : leadingRect;
      final rightHalf = trailingRect.left < leadingRect.left
          ? leadingRect
          : trailingRect;
      final leftCenter = firstCenter.dx < secondCenter.dx
          ? firstCenter.dx
          : secondCenter.dx;
      final rightCenter = firstCenter.dx < secondCenter.dx
          ? secondCenter.dx
          : firstCenter.dx;

      expect(leftHalf.left, lessThanOrEqualTo(leftCenter));
      expect(leftHalf.right, moreOrLessEquals(rightHalf.left, epsilon: 0.01));
      expect(rightHalf.right, greaterThanOrEqualTo(rightCenter));
    }
  });

  testWidgets('Arabic timer total fits compact layout at two-times text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(
            _FocusRepository(
              activeRun: _run(now),
              activeInterval: interval,
              intervals: [interval],
            ),
          ),
          focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: FocusScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('من أصل 25:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Russian compact header reflows at two-times text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FocusRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: FocusScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Фокус'), findsOneWidget);
    expect(find.byKey(const Key('focus-view-mode-toggle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop rail localizes compact durations', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(
            _FocusRepository(
              activeRun: _run(now),
              activeInterval: interval,
              intervals: [interval],
            ),
          ),
          focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: FocusScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('25 分钟'), findsAtLeastNWidgets(1));
    expect(find.text('25m'), findsNothing);
  });

  testWidgets('focus load error uses the active locale', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FocusRepository()),
          focusPresetsProvider.overrideWith(
            (ref) => Stream.error(StateError('boom')),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FocusScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('تعذر تحميل التركيز'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('loading and error keep the Focus header and mode toggle', (
    tester,
  ) async {
    final loadingPresets = StreamController<List<FocusPresetItem>>();
    addTearDown(loadingPresets.close);

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('focus-loading-scope'),
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FocusRepository()),
          focusPresetsProvider.overrideWith((ref) => loadingPresets.stream),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: FocusScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('focus-loading')), findsOneWidget);
    expect(find.byKey(const Key('focus-heading')), findsOneWidget);
    expect(find.byKey(const Key('focus-view-mode-toggle')), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('focus-error-scope'),
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FocusRepository()),
          focusPresetsProvider.overrideWith(
            (ref) => Stream.error(StateError('boom')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: FocusScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('focus-load-error')), findsOneWidget);
    expect(find.byKey(const Key('focus-heading')), findsOneWidget);
    expect(find.byKey(const Key('focus-view-mode-toggle')), findsOneWidget);
  });

  testWidgets('heading timer and rail expose concise semantic summaries', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: _run(now),
        activeInterval: interval,
        intervals: [interval],
      ),
      size: const Size(1200, 900),
      now: now,
    );

    expect(find.byKey(const Key('focus-heading')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('focus-heading')))
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester.getSemantics(find.byKey(const Key('focus-rhythm-rail'))).label,
      'Focus rhythm, step 1 of 8: Work interval, Running',
    );
    expect(
      tester.getSemantics(find.byKey(const Key('focus-timer-semantics'))).label,
      'Work interval, Running, 25:00 remaining, 25:00 total',
    );
    semantics.dispose();
  });

  testWidgets('320x568 keeps primary and overflow actions reachable', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 10, 9);
    final interval = _interval(now, status: 'running');

    await _pumpFocusScreen(
      tester,
      repository: _FocusRepository(
        activeRun: _run(now),
        activeInterval: interval,
        intervals: [interval],
      ),
      size: const Size(320, 568),
      now: now,
    );

    expect(find.byKey(const Key('focus-stage-scroll')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('focus-view-mode-toggle'))).height,
      greaterThanOrEqualTo(48),
    );
    final primary = find.byKey(const Key('focus-primary-action'));
    final more = find.byKey(const Key('focus-details-menu'));
    expect(tester.getSize(primary).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(more).height, greaterThanOrEqualTo(48));

    await tester.ensureVisible(primary);
    await tester.pump();
    final primaryRect = tester.getRect(primary);
    expect(primaryRect.top, greaterThanOrEqualTo(0));
    expect(primaryRect.bottom, lessThanOrEqualTo(568));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFocusScreen(
  WidgetTester tester, {
  required _FocusRepository repository,
  required Size size,
  DateTime? now,
  _TaskRepository? taskRepository,
  _ProjectRepository? projectRepository,
  ThemeData? theme,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(repository),
        if (now != null)
          focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        if (taskRepository != null)
          taskRepositoryProvider.overrideWithValue(taskRepository),
        if (projectRepository != null)
          projectRepositoryProvider.overrideWithValue(projectRepository),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const Scaffold(body: FocusScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpLinkedFocusScreen(
  WidgetTester tester, {
  required GoRouter router,
  required _FocusRepository focusRepository,
  required _TaskRepository taskRepository,
  required _ProjectRepository projectRepository,
  required DateTime now,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(focusRepository),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        taskRepositoryProvider.overrideWithValue(taskRepository),
        projectRepositoryProvider.overrideWithValue(projectRepository),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump();
}

class _FocusRepository implements FocusRepository {
  _FocusRepository({
    this.activeRun,
    this.activeInterval,
    this.intervals = const [],
    List<FocusPresetItem>? presets,
  }) : presets = presets ?? [_classicPreset];

  final FocusRunItem? activeRun;
  final FocusIntervalItem? activeInterval;
  final List<FocusIntervalItem> intervals;
  final List<FocusPresetItem> presets;
  int pauseCount = 0;
  int resumeCount = 0;

  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value(presets);

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(activeRun);

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() =>
      Stream.value(activeInterval);

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId) =>
      Stream.value(intervals);

  @override
  Future<String> startRun(StartFocusRunInput input, {DateTime? now}) async =>
      'run-1';

  @override
  Future<void> pauseActiveInterval({DateTime? now}) async {
    pauseCount++;
  }

  @override
  Future<void> resumeActiveInterval({DateTime? now}) async {
    resumeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _classicPreset = _preset();

FocusPresetItem _preset({bool allowPause = true, bool strictMode = false}) =>
    FocusPresetItem(
      id: 'classic',
      userId: 'local',
      name: 'Classic',
      workSeconds: 25 * 60,
      shortBreakSeconds: 5 * 60,
      longBreakSeconds: 15 * 60,
      intervalsBeforeLongBreak: 4,
      autoStartBreaks: false,
      autoStartWork: false,
      allowPause: allowPause,
      strictMode: strictMode,
      isDefault: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

FocusRunItem _run(
  DateTime now, {
  String? taskId,
  String? projectId,
  int completedWorkIntervals = 0,
}) => FocusRunItem(
  id: 'run-1',
  userId: 'local',
  taskId: taskId,
  projectId: projectId,
  presetId: _classicPreset.id,
  status: 'active',
  startedAt: now,
  targetWorkIntervals: 4,
  completedWorkIntervals: completedWorkIntervals,
  createdAt: now,
  updatedAt: now,
);

FocusIntervalItem _interval(
  DateTime now, {
  required String status,
  DateTime? startedAt,
  String type = 'work',
  DateTime? pausedAt,
  int sequence = 1,
}) => FocusIntervalItem(
  id: 'interval-$sequence',
  runId: 'run-1',
  type: type,
  status: status,
  plannedSeconds: type == 'work'
      ? 25 * 60
      : type == 'longBreak'
      ? 15 * 60
      : 5 * 60,
  startedAt: startedAt ?? now,
  pausedAt: pausedAt,
  pausedTotalSeconds: 0,
  sequenceNumber: sequence,
  createdAt: now,
  updatedAt: now,
);

TaskItem _task(DateTime now, {bool isDeleted = false}) => TaskItem(
  id: 'task-1',
  userId: 'local',
  content: 'Review Google Calendar sync edge cases',
  projectId: 'project-1',
  priority: 2,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: '1',
  isDeleted: isDeleted,
  createdAt: now,
  updatedAt: now,
);

ProjectItem _project(DateTime now) => ProjectItem(
  id: 'project-1',
  userId: 'local',
  name: 'Product Launch',
  color: '#E8793E',
  orderKey: '1',
  createdAt: now,
  updatedAt: now,
);

class _TaskRepository implements TaskRepository {
  _TaskRepository(this.task);

  final TaskItem? task;

  @override
  Stream<TaskItem?> watchTask(String id) => Stream.value(task);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProjectRepository implements ProjectRepository {
  _ProjectRepository(this.projects);

  final List<ProjectItem> projects;

  @override
  Stream<List<ProjectItem>> watchProjects() => Stream.value(projects);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

bool _focusIsWithin(WidgetTester tester, Finder target) {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext is! Element) {
    return false;
  }
  final targetElement = tester.element(target);
  if (identical(focusedContext, targetElement)) {
    return true;
  }
  var found = false;
  focusedContext.visitAncestorElements((ancestor) {
    if (identical(ancestor, targetElement)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
