// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/app_language.dart';
import 'package:pomodoist/app/app_startup_gate.dart';
import 'package:pomodoist/app/app_theme_mode.dart';
import 'package:pomodoist/app/keyboard_shortcuts.dart';
import 'package:pomodoist/app/macos_app_menu.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/router.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/app/widgets/resizable_dialog.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_screen.dart';
import 'package:pomodoist/features/onboarding/onboarding_gate.dart';
import 'package:pomodoist/features/planning/presentation/today_screen.dart';
import 'package:pomodoist/features/productivity/domain/achievement_models.dart';
import 'package:pomodoist/features/productivity/domain/productivity_models.dart';
import 'package:pomodoist/features/productivity/presentation/reports_screen.dart';
import 'package:pomodoist/features/settings/presentation/keyboard_shortcuts_screen.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/browse_screen.dart';
import 'package:pomodoist/features/tasks/presentation/inbox_screen.dart';
import 'package:pomodoist/features/tasks/presentation/kanban/kanban_screen.dart';
import 'package:pomodoist/features/tasks/presentation/priority_matrix_screen.dart';
import 'package:pomodoist/features/tasks/presentation/search_screen.dart';
import 'package:pomodoist/features/tasks/presentation/timeline_screen.dart';
import 'package:pomodoist/features/tasks/presentation/upcoming_screen.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_bar.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _wideSidebarFrameKey = Key('wide-sidebar-frame');
const _wideSidebarResizeHandleKey = Key('wide-sidebar-resize-handle');
const _wideSidebarEdgeHandleKey = Key('wide-sidebar-edge-reveal-handle');
const _shellMenuButtonKey = Key('shell-menu-button');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
    });
  });

  testWidgets('wide layout renders Todoist-like sidebar', (tester) async {
    await _pumpWideApp(tester);

    expect(find.text('Add task'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Priority Matrix'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Kanban'), findsOneWidget);
    expect(find.text('Today'), findsAtLeastNWidgets(1));
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('sidebar-destination-/integrations/google-calendar'),
      ),
      findsNothing,
    );
    const destinations = [
      '/browse',
      '/search',
      '/today',
      '/upcoming',
      '/focus',
      '/inbox',
      '/priority-matrix',
      '/timeline',
      '/kanban',
      '/reports',
      '/settings',
    ];
    for (final path in destinations) {
      expect(find.byKey(ValueKey('sidebar-destination-$path')), findsOneWidget);
    }
    final destinationTops = [
      for (final path in destinations)
        tester.getTopLeft(find.byKey(ValueKey('sidebar-destination-$path'))).dy,
    ];
    for (var i = 1; i < destinationTops.length; i++) {
      expect(destinationTops[i], greaterThan(destinationTops[i - 1]));
    }
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Projects: 1'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-project-work')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-destination-/inbox')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-destination-/today')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-destination-/upcoming')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    await _disposeApp(tester);
  });

  testWidgets('sidebar keyboard shortcut toggles wide layout', (tester) async {
    await _pumpWideApp(tester);

    expect(find.text('Add task'), findsOneWidget);

    await _pressSidebarShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(find.text('Add task'), findsNothing);

    await _pressSidebarShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(find.text('Add task'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('macOS modifier flags trigger app shortcuts', (tester) async {
    await _pumpWideApp(tester);

    expect(find.text('Add task'), findsOneWidget);

    _sendRawMacShortcut(keyCode: 11, character: 'b');
    await tester.pumpAndSettle();

    expect(find.text('Add task'), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('quick add shortcut opens only one existing dialog', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SearchScreen), findsNothing);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyN,
    );
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyN,
    );

    expect(find.byKey(const Key('sidebar-quick-add-input')), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('number shortcuts follow the desktop sidebar order', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit1,
    );
    expect(find.byType(BrowseScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit2,
    );
    expect(find.byType(SearchScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit3,
    );
    expect(find.byType(TodayScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit4,
    );
    expect(find.byType(UpcomingScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit5,
    );
    expect(find.byType(FocusScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit6,
    );
    expect(find.byType(InboxScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit7,
    );
    expect(find.byType(PriorityMatrixScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit8,
    );
    expect(find.byType(TimelineScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit9,
    );
    expect(find.byType(KanbanScreen), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit0,
    );
    expect(find.byType(ReportsScreen), findsOneWidget);

    await _pressShortcutWithShift(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit1,
    );
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('reassigned sidebar shortcut replaces the default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
      keyboardShortcutsPreferenceKey: jsonEncode({
        AppShortcutCommand.toggleSidebar.storageKey: {
          'physicalKeyId': PhysicalKeyboardKey.keyJ.usbHidUsage,
          'keyLabel': 'J',
          'meta': true,
          'control': false,
          'alt': false,
          'shift': false,
        },
      }),
    });
    await _pumpWideApp(tester);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyB,
    );
    expect(find.text('Add task'), findsOneWidget);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyJ,
    );
    expect(find.text('Add task'), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('macOS app menu syncs commands and reuses shortcut actions', (
    tester,
  ) async {
    const channel = MethodChannel(macOSAppMenuChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _pumpWideApp(tester);

    final syncCall = calls.lastWhere(
      (call) => call.method == macOSAppMenuSetCommandsMethod,
    );
    final commands = Map<String, Object?>.from(syncCall.arguments as Map);
    expect(commands.keys, {
      for (final command in AppShortcutCommand.values) command.name,
    });
    expect(commands[AppShortcutCommand.quickAdd.name], {
      'label': 'Add task',
      'keyLabel': 'N',
      'meta': true,
      'control': false,
      'alt': false,
      'shift': false,
    });

    await messenger.handlePlatformMessage(
      macOSAppMenuChannelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(macOSAppMenuSelectedMethod, 'quickAdd'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar-quick-add-input')), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('top menu button toggles wide sidebar', (tester) async {
    await _pumpWideApp(tester);

    expect(find.byKey(_shellMenuButtonKey), findsOneWidget);
    expect(find.text('Add task'), findsOneWidget);

    await tester.tap(find.byKey(_shellMenuButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Add task'), findsNothing);

    await tester.tap(find.byKey(_shellMenuButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Add task'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('wide sidebar restore animates from collapsed state', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await _pressSidebarShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(find.byKey(_wideSidebarFrameKey), findsNothing);

    await _pressSidebarShortcutWithoutSettling(
      tester,
      LogicalKeyboardKey.metaLeft,
    );
    await tester.pump();

    expect(find.byKey(_wideSidebarFrameKey), findsOneWidget);
    expect(_wideSidebarWidth(tester), closeTo(0, 0.1));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(_wideSidebarWidth(tester), greaterThan(0));
    expect(_wideSidebarWidth(tester), lessThan(280));

    await tester.pumpAndSettle();
    expect(_wideSidebarWidth(tester), closeTo(280, 0.1));
    await _disposeApp(tester);
  });

  testWidgets('wide sidebar resize handle changes sidebar width', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    expect(_wideSidebarWidth(tester), closeTo(280, 0.1));

    await _dragWideSidebarHandle(
      tester,
      _wideSidebarResizeHandleKey,
      const Offset(80, 0),
    );

    expect(_wideSidebarWidth(tester), greaterThan(320));
    expect(find.text('Add task'), findsOneWidget);
    expect(find.byKey(_wideSidebarEdgeHandleKey), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('wide sidebar collapses when resized below threshold', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await _dragWideSidebarHandle(
      tester,
      _wideSidebarResizeHandleKey,
      const Offset(-190, 0),
    );

    expect(find.byKey(_wideSidebarFrameKey), findsNothing);
    expect(find.text('Add task'), findsNothing);
    expect(find.byKey(_wideSidebarEdgeHandleKey), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('wide sidebar can be restored from left edge handle', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await _pressSidebarShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(find.byKey(_wideSidebarFrameKey), findsNothing);
    expect(find.byKey(_wideSidebarEdgeHandleKey), findsOneWidget);

    await _dragWideSidebarHandle(
      tester,
      _wideSidebarEdgeHandleKey,
      const Offset(260, 0),
    );

    expect(find.text('Add task'), findsOneWidget);
    expect(find.byKey(_wideSidebarEdgeHandleKey), findsNothing);
    expect(_wideSidebarWidth(tester), greaterThanOrEqualTo(220));
    await _disposeApp(tester);
  });

  testWidgets('sidebar keyboard shortcut opens compact drawer', (tester) async {
    await _pumpCompactApp(tester);

    expect(find.text('Add task'), findsNothing);

    await _pressSidebarShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(find.text('Add task'), findsOneWidget);

    await _pressSidebarShortcut(tester, LogicalKeyboardKey.metaLeft);
    expect(find.text('Add task'), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('top menu button opens compact drawer', (tester) async {
    await _pumpCompactApp(tester);

    expect(find.byKey(_shellMenuButtonKey), findsOneWidget);
    expect(find.text('Add task'), findsNothing);

    await tester.tap(find.byKey(_shellMenuButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Add task'), findsOneWidget);
    expect(find.text('Today'), findsAtLeastNWidgets(1));
    await _disposeApp(tester);
  });

  testWidgets('compact layout floats active focus player above navigation', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpCompactApp(
      tester,
      activeRun: _activeRun(now),
      activeInterval: _activeInterval(now),
    );

    final surface = find.byKey(const Key('mini-focus-player-surface'));
    final decoration =
        tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;

    expect(tester.getSize(surface).width, lessThan(600));
    expect(decoration.borderRadius, BorderRadius.circular(20));
    expect(decoration.boxShadow, isNotEmpty);
    await _disposeApp(tester);
  });

  testWidgets('voice sheet opens above compact timer chrome', (tester) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpCompactApp(
      tester,
      activeRun: _activeRun(now),
      activeInterval: _activeInterval(now),
      hasAccountPro: true,
    );

    expect(find.byKey(const Key('mini-focus-player-surface')), findsOneWidget);
    expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('mobile-bottom-navigation')),
        matching: find.text('Priority Matrix'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mobile-bottom-navigation')),
        matching: find.text('Timeline'),
      ),
      findsNothing,
    );
    expect(find.text('Today task 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Voice quick add'));
    await _pumpFrames(tester);

    expect(find.text('Voice add'), findsOneWidget);
    await tester.tap(find.text('Focus'), warnIfMissed: false);
    await _pumpFrames(tester);

    expect(find.text('Voice add'), findsOneWidget);
    expect(find.text('Today task 1'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('Kanban uses outer 820 breakpoint and hides wide mini player', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpApp(
      tester,
      size: const Size(820, 800),
      activeRun: _activeRun(now),
      activeInterval: _activeInterval(now),
    );

    await tester.tap(find.byKey(const ValueKey('sidebar-destination-/kanban')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('kanban-desktop-board')), findsOneWidget);
    expect(find.byKey(const Key('mini-focus-player-surface')), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets(
    'Kanban is drawer-only and leaves mobile destinations unselected',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      final now = DateTime.utc(2026, 4, 27, 10);
      await _pumpApp(
        tester,
        size: const Size(819, 800),
        activeRun: _activeRun(now),
        activeInterval: _activeInterval(now),
      );

      await tester.tap(find.byKey(_shellMenuButtonKey));
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(const ValueKey('sidebar-destination-/kanban')),
      );
      await _pumpFrames(tester);

      expect(find.byKey(const Key('kanban-mobile-board')), findsOneWidget);
      expect(find.byKey(const Key('mini-focus-player-surface')), findsNothing);
      expect(find.byKey(const Key('kanban-shell-add')), findsOneWidget);
      expect(find.byKey(const Key('kanban-shell-focus')), findsOneWidget);
      for (final label in const [
        'Today',
        'Upcoming',
        'Focus',
        'Inbox',
        'Projects',
      ]) {
        final semantics = find.descendant(
          of: find.byKey(const Key('mobile-bottom-navigation')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == label,
          ),
        );
        expect(semantics, findsOneWidget, reason: label);
        expect(
          tester.widget<Semantics>(semantics).properties.selected,
          isFalse,
          reason: label,
        );
      }
      semanticsHandle.dispose();
      await _disposeApp(tester);
    },
  );

  testWidgets('sidebar projects toggle collapses and expands project list', (
    tester,
  ) async {
    final harness = await _pumpWideApp(tester);

    expect(
      find.byKey(ValueKey('sidebar-project-${harness.workProjectId}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sidebar-projects-toggle')));
    await _pumpFrames(tester);
    expect(
      find.byKey(ValueKey('sidebar-project-${harness.workProjectId}')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('sidebar-projects-toggle')));
    await _pumpFrames(tester);
    expect(
      find.byKey(ValueKey('sidebar-project-${harness.workProjectId}')),
      findsOneWidget,
    );
    await _disposeApp(tester);
  });

  testWidgets('sidebar quick add creates a task and closes', (tester) async {
    final harness = await _pumpWideApp(tester);

    await tester.tap(find.byKey(const Key('sidebar-add-task')));
    await _pumpFrames(tester);
    expect(find.byKey(ResizableDialog.containerKey), findsOneWidget);
    expect(find.byType(QuickAddComposer), findsOneWidget);
    expect(find.byKey(const Key('sidebar-quick-add-voice')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('sidebar-quick-add-input')),
      'Новая задача из сайдбара',
    );
    await tester.tap(find.byKey(const Key('sidebar-quick-add-submit')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('sidebar-quick-add-input')), findsNothing);
    final tasks = await harness.db.select(harness.db.tasks).get();
    expect(
      tasks.where((task) => task.content == 'Новая задача из сайдбара'),
      hasLength(1),
    );
    await _disposeApp(tester);
  });

  testWidgets('sidebar quick add suggestions support keyboard selection', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await tester.tap(find.byKey(const Key('sidebar-add-task')));
    await _pumpFrames(tester);

    final field = find.byKey(const Key('sidebar-quick-add-input'));
    await tester.enterText(field, '#W');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('quick-add-suggestion-#Work')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, '#Work ');

    await tester.enterText(field, '#Work @D');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('quick-add-suggestion-@Design')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('quick-add-suggestion-@Deep Work')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      tester.widget<TextField>(field).controller!.text,
      '#Work @"Deep Work" ',
    );
    await _disposeApp(tester);
  });

  testWidgets('sidebar quick add microphone opens voice sheet', (tester) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: '2026-01-01T10:00:00.000Z',
    });
    await _pumpWideApp(tester, hasAccountPro: true);

    await tester.tap(find.byKey(const Key('sidebar-add-task')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('sidebar-quick-add-voice')));
    await _pumpFrames(tester);

    expect(find.text('Voice add'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('sidebar quick add microphone opens paywall without Pro', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await tester.tap(find.byKey(const Key('sidebar-add-task')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('sidebar-quick-add-voice')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('billing-paywall')), findsOneWidget);
    expect(find.byKey(const Key('billing-paywall-close')), findsOneWidget);
    expect(find.text('Voice add'), findsNothing);

    await tester.tap(find.byKey(const Key('billing-paywall-close')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('billing-paywall')), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('sidebar navigation opens new and project routes', (
    tester,
  ) async {
    final harness = await _pumpWideApp(tester);

    await tester.tap(find.text('Search'));
    await _pumpFrames(tester);
    expect(find.text('Search'), findsAtLeastNWidgets(1));
    expect(find.text('Search tasks'), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await _pumpFrames(tester);
    expect(find.text('Reports'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const Key('sidebar-projects-link')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('projects-search-field')), findsOneWidget);
    expect(find.byKey(const Key('projects-add-button')), findsOneWidget);

    await tester.tap(find.text('Browse'));
    await _pumpFrames(tester);
    expect(find.text('Browse'), findsAtLeastNWidgets(1));

    await tester.tap(
      find.byKey(ValueKey('sidebar-project-${harness.workProjectId}')),
    );
    await _pumpFrames(tester);
    expect(
      find.text('List view - board and calendar are roadmap items.'),
      findsOneWidget,
    );
    expect(find.text('Work'), findsAtLeastNWidgets(2));
    await _disposeApp(tester);
  });

  testWidgets('settings language selection switches UI to Russian', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await tester.tap(
      find.byKey(const ValueKey('sidebar-destination-/settings')),
    );
    await _pumpFrames(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -520));
    await tester.pumpAndSettle();
    final languageSelect = find
        .byKey(const Key('settings-language-select'))
        .last;
    expect(find.byKey(const Key('settings-language-select')), findsWidgets);
    expect(find.text('Language'), findsAtLeastNWidgets(1));

    await tester.tap(languageSelect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsAtLeastNWidgets(1));
    expect(find.text('Добавить задачу'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('settings shortcut button opens the shortcut route', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await tester.tap(
      find.byKey(const ValueKey('sidebar-destination-/settings')),
    );
    await _pumpFrames(tester);
    final settingsScrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('settings-list')),
        matching: find.byType(Scrollable),
      ),
    );
    for (var i = 0; i < 3; i += 1) {
      settingsScrollable.position.jumpTo(
        settingsScrollable.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('settings-shortcuts-button')));
    await _pumpFrames(tester);

    expect(find.byType(KeyboardShortcutsScreen), findsOneWidget);
    expect(find.byKey(const Key('shortcut-row-toggleSidebar')), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('settings theme selection switches between dark and light', (
    tester,
  ) async {
    await _pumpWideApp(tester);

    await tester.tap(
      find.byKey(const ValueKey('sidebar-destination-/settings')),
    );
    await _pumpFrames(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -760));
    await tester.pumpAndSettle();
    final settings = find.byKey(const Key('settings-theme-mode-select')).last;
    expect(settings, findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(settings)).brightness, Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(settings)).brightness, Brightness.light);
    await _disposeApp(tester);
  });

  testWidgets('system theme follows platform brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpWideApp(tester);

    await tester.tap(
      find.byKey(const ValueKey('sidebar-destination-/settings')),
    );
    await _pumpFrames(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -760));
    await tester.pumpAndSettle();
    final settings = find.byKey(const Key('settings-theme-mode-select')).last;

    expect(settings, findsOneWidget);
    expect(Theme.of(tester.element(settings)).brightness, Brightness.dark);
    await _disposeApp(tester);
  });

  testWidgets('projects screen searches and switches to archived projects', (
    tester,
  ) async {
    final harness = await _pumpWideApp(tester);

    await tester.tap(find.byKey(const Key('sidebar-projects-link')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('projects-search-field')), findsOneWidget);
    expect(find.byKey(const Key('projects-archived-switch')), findsOneWidget);
    expect(find.byKey(const Key('projects-add-button')), findsOneWidget);
    expect(
      find.byKey(ValueKey('projects-screen-project-${harness.workProjectId}')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('projects-screen-project-${harness.archivedProjectId}'),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('projects-search-field')),
      'zzz',
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(ValueKey('projects-screen-project-${harness.workProjectId}')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('projects-search-field')),
      'Work',
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(ValueKey('projects-screen-project-${harness.workProjectId}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('projects-archived-switch')));
    await _pumpFrames(tester);
    expect(
      find.byKey(ValueKey('projects-screen-project-${harness.workProjectId}')),
      findsNothing,
    );
    expect(
      find.byKey(
        ValueKey('projects-screen-project-${harness.archivedProjectId}'),
      ),
      findsOneWidget,
    );
    await _disposeApp(tester);
  });
}

class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode.themeMode,
      routerConfig: router,
      locale: language.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

class _SidebarHarness {
  const _SidebarHarness({
    required this.db,
    required this.workProjectId,
    required this.archivedProjectId,
  });

  final AppDatabase db;
  final String workProjectId;
  final String archivedProjectId;
}

Future<_SidebarHarness> _pumpWideApp(
  WidgetTester tester, {
  bool hasAccountPro = false,
}) async {
  return _pumpApp(
    tester,
    size: const Size(1200, 800),
    hasAccountPro: hasAccountPro,
  );
}

Future<_SidebarHarness> _pumpCompactApp(
  WidgetTester tester, {
  FocusRunItem? activeRun,
  FocusIntervalItem? activeInterval,
  bool hasAccountPro = false,
}) async {
  return _pumpApp(
    tester,
    size: const Size(600, 800),
    activeRun: activeRun,
    activeInterval: activeInterval,
    hasAccountPro: hasAccountPro,
  );
}

Future<_SidebarHarness> _pumpApp(
  WidgetTester tester, {
  required Size size,
  FocusRunItem? activeRun,
  FocusIntervalItem? activeInterval,
  bool hasAccountPro = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await db.ensureSeedData();
  final createdAt = DateTime.utc(2026);
  const workProjectId = 'work';
  const archivedProjectId = 'archived-work';
  final project = ProjectItem(
    id: workProjectId,
    userId: localUserId,
    name: 'Work',
    color: '#3B6EA8',
    orderKey: 'b',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
  final archivedProject = ProjectItem(
    id: archivedProjectId,
    userId: localUserId,
    name: 'Archived Work',
    color: '#8B5CF6',
    orderKey: 'c',
    isArchived: true,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
  final labels = [
    LabelItem(
      id: 'design',
      userId: localUserId,
      name: 'Design',
      orderKey: 'a',
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    LabelItem(
      id: 'deep-work',
      userId: localUserId,
      name: 'Deep Work',
      orderKey: 'b',
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
  ];
  final inboxTasks = [_task('inbox-1', 'Inbox task', createdAt: createdAt)];
  final todayTasks = [
    _task('today-1', 'Today task 1', createdAt: createdAt),
    _task('today-2', 'Today task 2', createdAt: createdAt),
  ];
  final upcomingTasks = [
    _task('upcoming-1', 'Upcoming task 1', createdAt: createdAt),
    _task('upcoming-2', 'Upcoming task 2', createdAt: createdAt),
    _task('upcoming-3', 'Upcoming task 3', createdAt: createdAt),
  ];
  final projectTasks = [
    _task(
      'project-1',
      'Project task',
      projectId: workProjectId,
      createdAt: createdAt,
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStartupProvider.overrideWith((ref) => Future<void>.value()),
        appStartupLifecycleProvider.overrideWith((ref) {}),
        shortcutTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        taskStartNotificationCoordinatorProvider.overrideWith((ref) {}),
        reengagementNotificationCoordinatorProvider.overrideWith((ref) {}),
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 1, 2, 11)),
        ),
        appDatabaseProvider.overrideWithValue(db),
        applePurchasesSupportedProvider.overrideWithValue(false),
        billingAccountEntitlementProvider.overrideWithValue(hasAccountPro),
        currentUserProvider.overrideWith(
          (ref) => Stream.value(
            UserRow(
              id: localUserId,
              email: null,
              displayName: 'Local User',
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          ),
        ),
        tasksByQueryProvider.overrideWith((ref, query) {
          return Stream.value(switch (query.kind) {
            TaskQueryKind.inbox => inboxTasks,
            TaskQueryKind.today => todayTasks,
            TaskQueryKind.upcoming => upcomingTasks,
            TaskQueryKind.day => [
              ...todayTasks,
              ...upcomingTasks,
            ].where((task) => task.dueDate == query.date).toList(),
            TaskQueryKind.project =>
              query.projectId == workProjectId
                  ? projectTasks
                  : const <TaskItem>[],
            TaskQueryKind.search => [
              ...inboxTasks,
              ...todayTasks,
              ...upcomingTasks,
              ...projectTasks,
            ],
            TaskQueryKind.all => [
              ...inboxTasks,
              ...todayTasks,
              ...upcomingTasks,
              ...projectTasks,
            ],
            TaskQueryKind.completed => const <TaskItem>[],
          });
        }),
        projectsProvider.overrideWith(
          (ref) => Stream.value([project, archivedProject]),
        ),
        labelsProvider.overrideWith((ref) => Stream.value(labels)),
        productivitySummaryProvider.overrideWith(
          (ref) => Stream.value(
            const ProductivitySummary(
              completedTasks: 0,
              completedFocusIntervals: 0,
              totalFocusSeconds: 0,
              plannedFocusIntervals: 2,
              openTasks: 7,
              allTimeCompletedTasks: 0,
              allTimeCompletedFocusIntervals: 0,
            ),
          ),
        ),
        achievementsProvider.overrideWith(
          (ref) => Stream.value(const <AchievementItem>[]),
        ),
        activeFocusRunProvider.overrideWith(
          (ref) => Stream<FocusRunItem?>.value(activeRun),
        ),
        activeFocusIntervalProvider.overrideWith(
          (ref) => Stream<FocusIntervalItem?>.value(activeInterval),
        ),
      ],
      child: const _TestApp(),
    ),
  );
  await _pumpFrames(tester);
  await tester.pump();

  return _SidebarHarness(
    db: db,
    workProjectId: workProjectId,
    archivedProjectId: archivedProjectId,
  );
}

Future<void> _pressSidebarShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
) async {
  await _pressSidebarShortcutWithoutSettling(tester, modifier);
  await tester.pumpAndSettle();
}

void _sendRawMacShortcut({required int keyCode, required String character}) {
  final data = RawKeyEventDataMacOs(
    characters: character,
    charactersIgnoringModifiers: character,
    keyCode: keyCode,
    modifiers: RawKeyEventDataMacOs.modifierCommand,
  );
  RawKeyboard.instance.handleRawKeyEvent(RawKeyDownEvent(data: data));
  RawKeyboard.instance.handleRawKeyEvent(RawKeyUpEvent(data: data));
}

Future<void> _pressSidebarShortcutWithoutSettling(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
) async {
  await _pressShortcutWithoutSettling(
    tester,
    modifier,
    LogicalKeyboardKey.keyB,
  );
}

Future<void> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await _pressShortcutWithoutSettling(tester, modifier, key);
  await tester.pumpAndSettle();
}

Future<void> _pressShortcutWithShift(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _pressShortcutWithoutSettling(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
}

Future<void> _dragWideSidebarHandle(
  WidgetTester tester,
  Key handleKey,
  Offset offset,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(handleKey)),
  );
  await tester.pump();
  await gesture.moveBy(offset);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

double _wideSidebarWidth(WidgetTester tester) {
  return tester.getSize(find.byKey(_wideSidebarFrameKey)).width;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

TaskItem _task(
  String id,
  String content, {
  String projectId = inboxProjectId,
  required DateTime createdAt,
}) {
  return TaskItem(
    id: id,
    userId: localUserId,
    content: content,
    projectId: projectId,
    priority: 4,
    status: 'open',
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: id,
    isDeleted: false,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

FocusRunItem _activeRun(DateTime now) {
  return FocusRunItem(
    id: 'run',
    userId: localUserId,
    presetId: 'preset',
    status: 'active',
    startedAt: now,
    targetWorkIntervals: 2,
    completedWorkIntervals: 0,
    createdAt: now,
    updatedAt: now,
  );
}

FocusIntervalItem _activeInterval(DateTime now) {
  return FocusIntervalItem(
    id: 'interval',
    runId: 'run',
    type: 'work',
    status: 'running',
    plannedSeconds: 25 * 60,
    startedAt: now.subtract(const Duration(minutes: 1)),
    pausedTotalSeconds: 0,
    sequenceNumber: 1,
    createdAt: now,
    updatedAt: now,
  );
}
