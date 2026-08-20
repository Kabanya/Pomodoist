import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/app/app.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/app_theme_mode.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/widgets/action_feedback.dart';
import 'package:pomodoist/app/widgets/adaptive_shell.dart';
import 'package:pomodoist/app/widgets/mini_focus_player.dart';
import 'package:pomodoist/app/widgets/resizable_dialog.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/db/app_database.dart' hide FocusDailyStats;
import 'package:pomodoist/core/notifications/notification_scheduler.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_screen.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/auth/google_calendar_auth_contract.dart';
import 'package:pomodoist/features/productivity/domain/achievement_models.dart';
import 'package:pomodoist/features/productivity/presentation/achievement_announcements.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AppThemeMode parses stored values', () {
    expect(AppThemeMode.tryFromStorageValue('system'), AppThemeMode.system);
    expect(AppThemeMode.tryFromStorageValue('light'), AppThemeMode.light);
    expect(AppThemeMode.tryFromStorageValue('dark'), AppThemeMode.dark);
    expect(AppThemeMode.tryFromStorageValue('unexpected'), isNull);
    expect(AppThemeMode.tryFromStorageValue(null), isNull);
    expect(AppThemeMode.fromStorageValue('system'), AppThemeMode.system);
    expect(AppThemeMode.fromStorageValue('light'), AppThemeMode.light);
    expect(AppThemeMode.fromStorageValue('dark'), AppThemeMode.dark);
    expect(AppThemeMode.fromStorageValue('unexpected'), AppThemeMode.system);
    expect(AppThemeMode.fromStorageValue(null), AppThemeMode.system);
  });

  test('AppThemeMode parses only the exact shared theme cookie', () {
    expect(
      appThemeModeFromCookieHeader(
        'session=abc; pomodoist-theme=dark; other=value',
      ),
      AppThemeMode.dark,
    );
    expect(appThemeModeFromCookieHeader('other-pomodoist-theme=light'), isNull);
    expect(appThemeModeFromCookieHeader('pomodoist-theme=unexpected'), isNull);
    expect(appThemeModeFromCookieHeader(''), isNull);
  });

  test('AppThemeModeController uses the shared cookie immediately', () async {
    SharedPreferences.setMockInitialValues({
      appThemeModePreferenceKey: AppThemeMode.light.storageValue,
    });
    final writes = <String>[];
    final container = ProviderContainer(
      overrides: [
        sharedThemeCookieReaderProvider.overrideWithValue(
          () => 'session=abc; pomodoist-theme=dark',
        ),
        sharedThemeCookieWriterProvider.overrideWithValue(writes.add),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeModeProvider), AppThemeMode.dark);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(appThemeModeProvider), AppThemeMode.dark);
    expect(
      prefs.getString(appThemeModePreferenceKey),
      AppThemeMode.dark.storageValue,
    );
    expect(writes, isEmpty);
  });

  test(
    'AppThemeModeController writes a selection to the shared cookie',
    () async {
      final writes = <String>[];
      final container = ProviderContainer(
        overrides: [
          sharedThemeCookieReaderProvider.overrideWithValue(() => ''),
          sharedThemeCookieWriterProvider.overrideWithValue(writes.add),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(appThemeModeProvider), AppThemeMode.system);
      final persisted = container
          .read(appThemeModeProvider.notifier)
          .setThemeMode(AppThemeMode.light);

      expect(writes, [AppThemeMode.light.storageValue]);
      await persisted;
    },
  );

  test('AppThemeModeController promotes a legacy web preference', () async {
    SharedPreferences.setMockInitialValues({
      appThemeModePreferenceKey: AppThemeMode.light.storageValue,
    });
    final writes = <String>[];
    final container = ProviderContainer(
      overrides: [
        sharedThemeCookieReaderProvider.overrideWithValue(() => ''),
        sharedThemeCookieWriterProvider.overrideWithValue(writes.add),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeModeProvider), AppThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appThemeModeProvider), AppThemeMode.light);
    expect(writes, [AppThemeMode.light.storageValue]);
  });

  test('AppThemeModeController ignores invalid preferences', () async {
    SharedPreferences.setMockInitialValues({
      appThemeModePreferenceKey: 'sepia',
    });
    final writes = <String>[];
    final container = ProviderContainer(
      overrides: [
        sharedThemeCookieReaderProvider.overrideWithValue(
          () => 'pomodoist-theme=sepia',
        ),
        sharedThemeCookieWriterProvider.overrideWithValue(writes.add),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeModeProvider), AppThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appThemeModeProvider), AppThemeMode.system);
    expect(writes, isEmpty);
  });

  test('AppThemeModeController reloads a shared theme on resume', () async {
    var cookie = 'pomodoist-theme=dark';
    final container = ProviderContainer(
      overrides: [
        sharedThemeCookieReaderProvider.overrideWithValue(() => cookie),
        sharedThemeCookieWriterProvider.overrideWithValue((_) {}),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeModeProvider), AppThemeMode.dark);
    cookie = 'pomodoist-theme=light';
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appThemeModeProvider), AppThemeMode.light);
  });

  test('FocusTimerVisualStyle parses stored values', () {
    expect(
      FocusTimerVisualStyle.fromStorageValue('circle'),
      FocusTimerVisualStyle.circle,
    );
    expect(
      FocusTimerVisualStyle.fromStorageValue('unexpected'),
      FocusTimerVisualStyle.circle,
    );
    expect(
      FocusTimerVisualStyle.fromStorageValue(null),
      FocusTimerVisualStyle.circle,
    );
  });

  testWidgets('action feedback can skip sound', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showActionFeedback(
                context,
                message: 'Saved',
                icon: Icons.check,
                sound: ActionFeedbackSound.none,
                haptic: AppHapticCue.none,
              ),
              child: const Text('Show feedback'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show feedback'));
    await tester.pump();

    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('action feedback with action still times out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showActionFeedback(
                context,
                message: 'Saved',
                icon: Icons.check,
                duration: const Duration(milliseconds: 10),
                action: SnackBarAction(label: 'Undo', onPressed: () {}),
                sound: ActionFeedbackSound.none,
                haptic: AppHapticCue.none,
              ),
              child: const Text('Show feedback'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show feedback'));
    await tester.pump();

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('PomodoistApp shows startup error with retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith((ref) async {
            attempts++;
            throw StateError('seed failed');
          }),
        ],
        child: const PomodoistApp(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('app-startup-error-title')), findsOneWidget);
    expect(find.textContaining('seed failed'), findsOneWidget);
    expect(find.byType(AdaptiveShell), findsNothing);

    await tester.tap(find.byKey(const Key('app-startup-retry-button')));
    await tester.pump();

    expect(attempts, 2);
  });

  testWidgets('milestone achievement appears in the global banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _AchievementAnnouncementHarness(item: _focusAchievement),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('achievement-global-banner')), findsOneWidget);
    expect(find.byKey(const Key('achievement-bottom-plaque')), findsNothing);
    expect(find.textContaining('First tomato'), findsOneWidget);
  });

  testWidgets('combo achievement appears in the bottom plaque', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _AchievementAnnouncementHarness(item: _comboAchievement),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('achievement-bottom-plaque')), findsOneWidget);
    expect(find.byKey(const Key('achievement-global-banner')), findsNothing);
    expect(find.textContaining('Day not wasted'), findsOneWidget);
  });

  testWidgets('FocusScreen renders the idle preset picker', (tester) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('No active session'), findsOneWidget);
    expect(find.text('Classic'), findsAtLeastNWidgets(1));
    expect(find.text('Classic default'), findsNothing);
    expect(find.text('25m work'), findsOneWidget);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('New preset'), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);
  });

  testWidgets('FocusScreen full idle preset picker switches presets', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('preset-choice-$deepWorkPresetId')));
    await tester.pump();

    expect(find.text('50m work'), findsOneWidget);
    expect(find.text('25m work'), findsNothing);
  });

  testWidgets('FocusScreen persists the last selected preset', (tester) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('preset-choice-$deepWorkPresetId')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString(lastFocusPresetIdPreferenceKey), deepWorkPresetId);
  });

  testWidgets('FocusScreen minimal idle mode keeps launch controls compact', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('No active session'), findsNothing);
    expect(find.byKey(const Key('minimal-preset-select')), findsOneWidget);
    expect(find.text('Classic'), findsAtLeastNWidgets(1));
    expect(find.text('Start focus'), findsOneWidget);
    expect(find.text('Customize'), findsNothing);

    await tester.tap(find.byKey(const Key('minimal-idle-more-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('New preset'), findsOneWidget);
  });

  testWidgets('FocusScreen shows focus provider errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
          focusPresetsProvider.overrideWith(
            (ref) => Stream.error(StateError('presets failed')),
          ),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('focus-load-error')), findsOneWidget);
    expect(find.textContaining('presets failed'), findsOneWidget);
    expect(find.byKey(const Key('focus-loading')), findsNothing);
  });

  testWidgets('FocusScreen empty presets do not look like loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(
            _FakeFocusRepository(presets: const []),
          ),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('focus-loading')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('minimal-idle-more-menu')), findsOneWidget);

    await tester.tap(find.byKey(const Key('minimal-idle-more-menu')));
    await tester.pumpAndSettle();

    expect(find.text('New preset'), findsOneWidget);
  });

  test(
    'FocusViewModeController persists mode across provider rebuilds',
    () async {
      final firstContainer = ProviderContainer();
      expect(firstContainer.read(focusViewModeProvider), FocusViewMode.minimal);

      await firstContainer
          .read(focusViewModeProvider.notifier)
          .setMode(FocusViewMode.full);
      firstContainer.dispose();

      final secondContainer = ProviderContainer();
      addTearDown(secondContainer.dispose);
      expect(
        secondContainer.read(focusViewModeProvider),
        FocusViewMode.minimal,
      );

      await secondContainer.read(sharedPreferencesProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(secondContainer.read(focusViewModeProvider), FocusViewMode.full);
    },
  );

  test(
    'FocusTimerVisualStyleController persists style across provider rebuilds',
    () async {
      final firstContainer = ProviderContainer();
      expect(
        firstContainer.read(focusTimerVisualStyleProvider),
        FocusTimerVisualStyle.circle,
      );

      await firstContainer
          .read(focusTimerVisualStyleProvider.notifier)
          .setStyle(FocusTimerVisualStyle.bar);
      firstContainer.dispose();

      final secondContainer = ProviderContainer();
      addTearDown(secondContainer.dispose);
      expect(
        secondContainer.read(focusTimerVisualStyleProvider),
        FocusTimerVisualStyle.circle,
      );

      await secondContainer.read(sharedPreferencesProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(
        secondContainer.read(focusTimerVisualStyleProvider),
        FocusTimerVisualStyle.bar,
      );
    },
  );

  testWidgets('SettingsScreen persists timer visual style', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarAuthServiceProvider.overrideWithValue(
            const _NoopGoogleCalendarAuthService(),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    final timerVisualStyleSelect = find.byWidgetPredicate(
      (widget) =>
          widget is SegmentedButton<FocusTimerVisualStyle> &&
          widget.key == const Key('settings-timer-visual-style-select'),
    );
    await tester.scrollUntilVisible(
      timerVisualStyleSelect,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(timerVisualStyleSelect, findsWidgets);
    expect(find.text('Pomodoro timer'), findsOneWidget);

    await tester.ensureVisible(find.text('Bar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bar'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();

    expect(
      prefs.getString(focusTimerVisualStylePreferenceKey),
      FocusTimerVisualStyle.bar.storageValue,
    );
  });

  testWidgets('SettingsScreen persists default timed block duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarAuthServiceProvider.overrideWithValue(
            const _NoopGoogleCalendarAuthService(),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    final defaultTimedBlockInput = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.key == const Key('settings-default-timed-block-minutes-input'),
    );
    await tester.scrollUntilVisible(
      defaultTimedBlockInput,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final fortyFiveMinutes = find.byWidgetPredicate(
      (widget) =>
          widget is ChoiceChip &&
          widget.key == const ValueKey('settings-default-block-45'),
    );
    await tester.ensureVisible(fortyFiveMinutes.first);
    await tester.pumpAndSettle();
    await tester.tap(fortyFiveMinutes.first);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getInt(quickAddDefaultTimedBlockMinutesPreferenceKey), 45);

    await tester.enterText(defaultTimedBlockInput.first, '75');
    await tester.pump();

    expect(prefs.getInt(quickAddDefaultTimedBlockMinutesPreferenceKey), 75);

    await tester.enterText(defaultTimedBlockInput.first, '0');
    await tester.pump();

    expect(prefs.getInt(quickAddDefaultTimedBlockMinutesPreferenceKey), 75);
    expect(find.text('Enter 1 to 480 minutes.'), findsOneWidget);
  });

  testWidgets('SettingsScreen shows return reminders enabled by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          notificationSchedulerProvider.overrideWithValue(
            _FakeNotificationScheduler(),
          ),
          googleCalendarAuthServiceProvider.overrideWithValue(
            const _NoopGoogleCalendarAuthService(),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings-reengagement-notifications-switch')),
    );
    expect(tile.value, isTrue);
  });

  testWidgets('SettingsScreen disables return reminders', (tester) async {
    final scheduler = _FakeNotificationScheduler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          notificationSchedulerProvider.overrideWithValue(scheduler),
          googleCalendarAuthServiceProvider.overrideWithValue(
            const _NoopGoogleCalendarAuthService(),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('settings-reengagement-notifications-switch')),
    );
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();

    expect(
      prefs.getBool(reengagementNotificationsEnabledPreferenceKey),
      isFalse,
    );
    expect(scheduler.cancelReengagementCount, 1);
  });

  testWidgets('SettingsScreen places completion celebration before About', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarAuthServiceProvider.overrideWithValue(
            const _NoopGoogleCalendarAuthService(),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final about = find.byKey(const Key('settings-app-info-section'));
    await tester.scrollUntilVisible(
      about,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final celebration = find.byKey(
      const Key('settings-focus-completion-celebration-switch'),
    );

    expect(celebration, findsOneWidget);
    expect(
      tester.getTopLeft(celebration).dy,
      lessThan(tester.getTopLeft(about).dy),
    );
  });

  testWidgets('SettingsScreen persists disabled completion celebration', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarAuthServiceProvider.overrideWithValue(
            const _NoopGoogleCalendarAuthService(),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final about = find.byKey(const Key('settings-app-info-section'));
    await tester.scrollUntilVisible(
      about,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final celebration = find.byKey(
      const Key('settings-focus-completion-celebration-switch'),
    );
    expect(celebration, findsOneWidget);
    await tester.tap(celebration);
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('focus.completionCelebration.enabled'), isFalse);
  });

  test(
    'AppThemeModeController persists mode across provider rebuilds',
    () async {
      final firstContainer = ProviderContainer();
      expect(firstContainer.read(appThemeModeProvider), AppThemeMode.system);

      await firstContainer
          .read(appThemeModeProvider.notifier)
          .setThemeMode(AppThemeMode.dark);
      firstContainer.dispose();

      final secondContainer = ProviderContainer();
      addTearDown(secondContainer.dispose);
      expect(secondContainer.read(appThemeModeProvider), AppThemeMode.system);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(secondContainer.read(appThemeModeProvider), AppThemeMode.dark);
    },
  );

  testWidgets('MiniFocusPlayer renders full mode when preferred', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpMiniFocusPlayer(
      tester,
      _FakeFocusRepository(
        activeRun: _focusRun(now),
        activeInterval: _focusInterval(now, status: 'running'),
      ),
      now,
    );

    expect(find.byKey(const Key('minimal-mini-focus-more-menu')), findsNothing);
    expect(find.textContaining('Work ·'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);
  });

  testWidgets('MiniFocusPlayer keeps full-width shape by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpMiniFocusPlayer(
      tester,
      _FakeFocusRepository(
        activeRun: _focusRun(now),
        activeInterval: _focusInterval(now, status: 'running'),
      ),
      now,
    );

    final surface = find.byKey(const Key('mini-focus-player-surface'));
    final decoration =
        tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;

    expect(
      tester.getSize(surface).width,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );
    expect(decoration.borderRadius, isNull);
    expect(decoration.border, isA<Border>());
  });

  testWidgets('MiniFocusPlayer uses floating mobile shape when requested', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpMiniFocusPlayer(
      tester,
      _FakeFocusRepository(
        activeRun: _focusRun(now),
        activeInterval: _focusInterval(now, status: 'running'),
      ),
      now,
      floating: true,
    );

    final surface = find.byKey(const Key('mini-focus-player-surface'));
    final decoration =
        tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;

    expect(
      tester.getSize(surface).width,
      lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
    );
    expect(decoration.borderRadius, BorderRadius.circular(20));
    expect(decoration.border, isA<Border>());
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('MiniFocusPlayer pauses from the inline control', (tester) async {
    final now = DateTime.utc(2026, 4, 27, 10);
    final fake = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'running'),
    );
    await _pumpMiniFocusPlayer(tester, fake, now);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();

    expect(fake.pauseCount, 1);
  });

  testWidgets('MiniFocusPlayer renders minimal mode and stops from overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.minimal.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    final fake = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'running'),
    );
    await _pumpMiniFocusPlayer(tester, fake, now);

    expect(
      find.byKey(const Key('minimal-mini-focus-more-menu')),
      findsOneWidget,
    );
    expect(find.textContaining('Work ·'), findsNothing);

    await tester.tap(find.byKey(const Key('minimal-mini-focus-more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop').last);
    await tester.pump();

    expect(fake.stopReasons, [StopFocusReason.stopped]);
    expect(find.text('Focus stopped'), findsOneWidget);
  });

  testWidgets('MiniFocusPlayer starts ready interval with feedback', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 4, 27, 10);
    final fake = _FakeFocusRepository(
      activeRun: _focusRun(now),
      activeInterval: _focusInterval(now, status: 'ready'),
    );
    await _pumpMiniFocusPlayer(tester, fake, now);

    await tester.tap(find.byTooltip('Start interval'));
    await tester.pump();

    expect(fake.startReadyCount, 1);
    expect(find.text('Interval started'), findsOneWidget);
  });

  testWidgets(
    'AdaptiveShell compact bottom chrome keeps feedback above focus',
    (tester) async {
      final now = DateTime.utc(2026, 4, 27, 10);
      await _pumpCompactAdaptiveShell(tester, now);

      final surface = find.byKey(const Key('mini-focus-player-surface'));
      final bottomNavigation = find.byKey(
        const Key('mobile-bottom-navigation'),
      );

      expect(surface, findsOneWidget);
      expect(bottomNavigation, findsOneWidget);
      expect(
        tester.getBottomLeft(surface).dy,
        lessThanOrEqualTo(tester.getTopLeft(bottomNavigation).dy),
      );

      await tester.tap(find.text('Notify'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final snackbar = find.byType(SnackBar);
      expect(snackbar, findsOneWidget);
      expect(
        tester.getBottomLeft(snackbar).dy,
        lessThanOrEqualTo(tester.getTopLeft(surface).dy),
      );
    },
  );

  testWidgets(
    'AdaptiveShell compact routed content ignores bottom safe inset',
    (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      final now = DateTime.utc(2026, 4, 27, 10);

      await _pumpCompactAdaptiveShell(
        tester,
        now,
        child: const SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              key: Key('compact-safearea-bottom-probe'),
              height: 24,
            ),
          ),
        ),
      );

      final probe = find.byKey(const Key('compact-safearea-bottom-probe'));
      final surface = find.byKey(const Key('mini-focus-player-surface'));

      expect(probe, findsOneWidget);
      expect(surface, findsOneWidget);
      expect(
        tester.getBottomLeft(probe).dy,
        moreOrLessEquals(tester.getTopLeft(surface).dy, epsilon: 1),
      );
    },
  );

  testWidgets('active focus remaining completes expired running interval', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 4, 27, 10);
    final fake = _FakeFocusRepository(
      activeInterval: _focusInterval(
        now,
        status: 'running',
        startedAt: now.subtract(const Duration(minutes: 25)),
      ),
    );
    Duration? remaining;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(fake),
          focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            remaining = ref.watch(activeFocusRemainingProvider);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(remaining, Duration.zero);
    expect(fake.completeCount, 1);
  });

  testWidgets('FocusScreen uses circular timer style by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpActiveFocusScreen(tester, now);

    expect(find.byKey(const Key('focus-circular-timer')), findsOneWidget);
    expect(find.byKey(const Key('focus-linear-timer')), findsNothing);
  });

  testWidgets('FocusScreen enlarges circular timer on macOS', (tester) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpActiveFocusScreen(
      tester,
      now,
      platform: TargetPlatform.macOS,
      size: const Size(900, 900),
    );

    expect(
      tester.getSize(find.byKey(const Key('focus-circular-timer'))),
      const Size.square(320),
    );
  });

  testWidgets('FocusScreen enlarges circular timer on iPad-sized iOS', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpActiveFocusScreen(
      tester,
      now,
      platform: TargetPlatform.iOS,
      size: const Size(820, 1180),
    );

    expect(
      tester.getSize(find.byKey(const Key('focus-circular-timer'))),
      const Size.square(320),
    );
  });

  testWidgets('FocusScreen uses desktop timer at wide content when short', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpActiveFocusScreen(
      tester,
      now,
      platform: TargetPlatform.macOS,
      size: const Size(900, 700),
    );

    expect(
      tester.getSize(find.byKey(const Key('focus-circular-timer'))),
      const Size.square(320),
    );
  });

  testWidgets('FocusScreen fits compact timer to phone content width', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpActiveFocusScreen(
      tester,
      now,
      platform: TargetPlatform.iOS,
      size: const Size(390, 844),
    );

    expect(
      tester.getSize(find.byKey(const Key('focus-circular-timer'))),
      const Size.square(300),
    );
  });

  testWidgets('FocusScreen uses linear timer style when preferred', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
      focusTimerVisualStylePreferenceKey:
          FocusTimerVisualStyle.bar.storageValue,
    });
    final now = DateTime.utc(2026, 4, 27, 10);
    await _pumpActiveFocusScreen(tester, now);

    expect(find.byKey(const Key('focus-linear-timer')), findsOneWidget);
    expect(find.byKey(const Key('focus-circular-timer')), findsNothing);
  });

  testWidgets('Focus preset form validates required fields', (tester) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('New preset'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('preset-work-minutes-field')),
      '0',
    );
    await tester.tap(find.byKey(const Key('preset-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('1-180'), findsOneWidget);
  });

  testWidgets('Customize preset dialog opens wider by default', (tester) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();

    final dialogSize = tester.getSize(find.byKey(ResizableDialog.containerKey));
    expect(find.text('Customize preset'), findsOneWidget);
    expect(dialogSize.width, greaterThanOrEqualTo(650));
  });

  testWidgets('Focus preset dialog resizes and respects minimum size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('New preset'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(ResizableDialog.containerKey);
    final handle = find.byKey(ResizableDialog.resizeHandleKey);
    final initialSize = tester.getSize(dialog);

    await tester.drag(handle, const Offset(-160, -160));
    await tester.pump();
    final smallerSize = tester.getSize(dialog);
    expect(smallerSize.width, lessThan(initialSize.width));
    expect(smallerSize.height, lessThan(initialSize.height));

    await tester.drag(handle, const Offset(220, 180));
    await tester.pump();
    final largerSize = tester.getSize(dialog);
    expect(largerSize.width, greaterThan(smallerSize.width));
    expect(largerSize.height, greaterThan(smallerSize.height));

    await tester.drag(handle, const Offset(-1000, -1000));
    await tester.pump();
    final minSize = tester.getSize(dialog);
    expect(minSize.width, moreOrLessEquals(360));
    expect(minSize.height, moreOrLessEquals(420));
  });

  testWidgets('FocusScreen switches active run preset for next intervals', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      focusViewModePreferenceKey: FocusViewMode.full.storageValue,
    });
    final fake = _FakeFocusRepository(
      activeRun: FocusRunItem(
        id: 'run',
        userId: localUserId,
        presetId: defaultPresetId,
        status: 'active',
        startedAt: DateTime.utc(2026, 4, 27, 10),
        targetWorkIntervals: 2,
        completedWorkIntervals: 0,
        createdAt: DateTime.utc(2026, 4, 27, 10),
        updatedAt: DateTime.utc(2026, 4, 27, 10),
      ),
      activeInterval: FocusIntervalItem(
        id: 'interval',
        runId: 'run',
        type: 'work',
        status: 'running',
        plannedSeconds: 25 * 60,
        startedAt: DateTime.now().toUtc(),
        pausedTotalSeconds: 0,
        sequenceNumber: 1,
        createdAt: DateTime.utc(2026, 4, 27, 10),
        updatedAt: DateTime.utc(2026, 4, 27, 10),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(fake),
          activeFocusRemainingProvider.overrideWith(
            (ref) => const Duration(minutes: 24),
          ),
        ],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final menu = find.byKey(const Key('focus-details-menu'));
    await tester.ensureVisible(menu);
    await tester.pump();
    await tester.tap(
      find.descendant(of: menu, matching: find.byIcon(Icons.more_horiz)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Deep Work').last);
    await tester.pumpAndSettle();

    expect(fake.changedPresetId, deepWorkPresetId);
    expect(find.text('50m'), findsAtLeastNWidgets(1));
  });
}

Future<void> _pumpActiveFocusScreen(
  WidgetTester tester,
  DateTime now, {
  TargetPlatform? platform,
  Size? size,
}) async {
  final previousSize = tester.view.physicalSize;
  final previousDevicePixelRatio = tester.view.devicePixelRatio;
  if (size != null) {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..physicalSize = previousSize
        ..devicePixelRatio = previousDevicePixelRatio;
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(
          _FakeFocusRepository(
            activeRun: _focusRun(now),
            activeInterval: _focusInterval(now, status: 'running'),
          ),
        ),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: MaterialApp(
        theme: platform == null ? null : ThemeData(platform: platform),
        home: const FocusScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMiniFocusPlayer(
  WidgetTester tester,
  _FakeFocusRepository focusRepository,
  DateTime now, {
  bool floating = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(focusRepository),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MiniFocusPlayer(floating: floating),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpCompactAdaptiveShell(
  WidgetTester tester,
  DateTime now, {
  Widget? child,
}) async {
  final previousSize = tester.view.physicalSize;
  final previousDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view
    ..physicalSize = const Size(600, 800)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..physicalSize = previousSize
      ..devicePixelRatio = previousDevicePixelRatio;
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(
          _FakeFocusRepository(
            activeRun: _focusRun(now),
            activeInterval: _focusInterval(now, status: 'running'),
          ),
        ),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        achievementsProvider.overrideWith(
          (ref) => Stream.value(const <AchievementItem>[]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: AdaptiveShell(
          location: '/today',
          child:
              child ??
              Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Saved')));
                    },
                    child: const Text('Notify'),
                  ),
                ),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FocusRunItem _focusRun(DateTime now) {
  return FocusRunItem(
    id: 'run',
    userId: localUserId,
    presetId: defaultPresetId,
    status: 'active',
    startedAt: now,
    targetWorkIntervals: 2,
    completedWorkIntervals: 0,
    createdAt: now,
    updatedAt: now,
  );
}

FocusIntervalItem _focusInterval(
  DateTime now, {
  required String status,
  DateTime? startedAt,
  DateTime? pausedAt,
}) {
  return FocusIntervalItem(
    id: 'interval',
    runId: 'run',
    type: 'work',
    status: status,
    plannedSeconds: 25 * 60,
    startedAt: startedAt ?? now.subtract(const Duration(minutes: 1)),
    pausedAt: pausedAt,
    pausedTotalSeconds: 0,
    sequenceNumber: 1,
    createdAt: now,
    updatedAt: now,
  );
}

class _AchievementAnnouncementHarness extends ConsumerStatefulWidget {
  const _AchievementAnnouncementHarness({required this.item});

  final AchievementItem item;

  @override
  ConsumerState<_AchievementAnnouncementHarness> createState() =>
      _AchievementAnnouncementHarnessState();
}

class _AchievementAnnouncementHarnessState
    extends ConsumerState<_AchievementAnnouncementHarness> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(achievementAnnouncementControllerProvider.notifier).enqueue([
        widget.item,
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Column(
          children: [
            AchievementAnnouncementSlot(
              presentation: AchievementPresentation.globalBanner,
            ),
            Spacer(),
            AchievementAnnouncementSlot(
              presentation: AchievementPresentation.bottomPlaque,
            ),
          ],
        ),
      ),
    );
  }
}

const _focusAchievement = AchievementItem(
  id: 'focus_1',
  group: AchievementGroup.focus,
  presentation: AchievementPresentation.globalBanner,
  titleRu: 'Первый помидор',
  titleEn: 'First tomato',
  subtitleRu: 'Завершить 1 work-фокус',
  subtitleEn: 'Complete 1 work focus',
  progress: 1,
  target: 1,
);

const _comboAchievement = AchievementItem(
  id: 'combo_day_not_wasted',
  group: AchievementGroup.combo,
  presentation: AchievementPresentation.bottomPlaque,
  titleRu: 'День не зря',
  titleEn: 'Day not wasted',
  subtitleRu: 'За день есть фокус и закрытая задача',
  subtitleEn: 'Finish a focus and a task in one day',
  progress: 1,
  target: 1,
);

class _FakeNotificationScheduler extends NotificationScheduler {
  int cancelReengagementCount = 0;

  @override
  Future<void> cancelReengagementReminder() async {
    cancelReengagementCount++;
  }

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => const {};

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelTaskStart(String taskId) async {}
}

class _FakeFocusRepository implements FocusRepository {
  _FakeFocusRepository({
    FocusRunItem? activeRun,
    FocusIntervalItem? activeInterval,
    List<FocusPresetItem>? presets,
  }) : _activeRun = activeRun,
       _activeInterval = activeInterval,
       _presets = presets ?? _defaultPresets;

  final FocusRunItem? _activeRun;
  final FocusIntervalItem? _activeInterval;
  final List<FocusPresetItem> _presets;
  String? changedPresetId;
  final stopReasons = <StopFocusReason>[];
  int startReadyCount = 0;
  int pauseCount = 0;
  int completeCount = 0;

  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value(_presets);

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(_activeRun);

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() =>
      Stream.value(_activeInterval);

  @override
  Stream<List<FocusRunItem>> watchRunsForTask(String taskId) =>
      Stream.value(const []);

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForTask(String taskId) =>
      Stream.value(const []);

  @override
  Stream<List<FocusIntervalItem>> watchIntervalsForRun(String runId) =>
      Stream.value(const []);

  @override
  Stream<FocusDailyStats> watchDailyStats(DateTime localDate) {
    return Stream.value(
      const FocusDailyStats(
        completedTasks: 0,
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        interruptedIntervals: 0,
        plannedFocusIntervals: 0,
      ),
    );
  }

  @override
  Future<String> createPreset(CreateFocusPresetInput input) async => 'created';

  @override
  Future<void> updatePreset(String id, UpdateFocusPresetInput input) async {}

  @override
  Future<void> deletePreset(String id) async {}

  @override
  Future<void> setDefaultPreset(String id) async {}

  @override
  Future<void> changeActiveRunPreset(String presetId) async {
    changedPresetId = presetId;
  }

  @override
  Future<String> startRun(StartFocusRunInput input, {DateTime? now}) async =>
      'run';

  @override
  Future<void> startReadyInterval() async {
    startReadyCount++;
  }

  @override
  Future<void> pauseActiveInterval({DateTime? now}) async {
    pauseCount++;
  }

  @override
  Future<void> resumeActiveInterval({DateTime? now}) async {}

  @override
  Future<void> restartActiveInterval({DateTime? now}) async {}

  @override
  Future<void> completeActiveInterval({DateTime? now}) async {
    completeCount++;
  }

  @override
  Future<void> skipActiveInterval({DateTime? now}) async {}

  @override
  Future<void> stopActiveRun({
    required StopFocusReason reason,
    DateTime? now,
  }) async {
    stopReasons.add(reason);
  }

  @override
  Future<void> logDistraction({required String runId, String? note}) async {}
}

class _NoopGoogleCalendarAuthService implements GoogleCalendarAuthService {
  const _NoopGoogleCalendarAuthService();

  @override
  Future<String?> accessToken({bool interactive = false}) async => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    return const GoogleCalendarAuthAccount();
  }
}

final _defaultPresets = [
  FocusPresetItem(
    id: defaultPresetId,
    userId: localUserId,
    name: 'Classic',
    workSeconds: 25 * 60,
    shortBreakSeconds: 5 * 60,
    longBreakSeconds: 15 * 60,
    intervalsBeforeLongBreak: 4,
    autoStartBreaks: false,
    autoStartWork: false,
    allowPause: true,
    strictMode: false,
    isDefault: true,
    createdAt: DateTime.utc(2026, 4, 27),
    updatedAt: DateTime.utc(2026, 4, 27),
  ),
  FocusPresetItem(
    id: deepWorkPresetId,
    userId: localUserId,
    name: 'Deep Work',
    workSeconds: 50 * 60,
    shortBreakSeconds: 10 * 60,
    longBreakSeconds: 25 * 60,
    intervalsBeforeLongBreak: 4,
    autoStartBreaks: false,
    autoStartWork: false,
    allowPause: true,
    strictMode: false,
    isDefault: false,
    createdAt: DateTime.utc(2026, 4, 27),
    updatedAt: DateTime.utc(2026, 4, 27),
  ),
];
