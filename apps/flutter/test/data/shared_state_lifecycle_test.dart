import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_announcement_repository.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_announcement_repository_impl.dart';
import 'package:pomodoist/data/repositories/focus/focus_completion_repository_impl.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository_impl.dart';
import 'package:pomodoist/data/repositories/settings/app_zoom_repository_impl.dart';
import 'package:pomodoist/data/repositories/settings/keyboard_shortcuts_repository_impl.dart';
import 'package:pomodoist/data/repositories/settings/language_repository_impl.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository_impl.dart';
import 'package:pomodoist/data/repositories/settings/theme_mode_repository_impl.dart';
import 'package:pomodoist/data/repositories/settings/theme_settings_repository_impl.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/ui/core/view_models/app_theme_mode_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('delayed hydration cannot overwrite newer selections', () {
    test(
      'task preferences keep edited keys and still load unrelated values',
      () async {
        SharedPreferences.setMockInitialValues({
          taskListStylePreferenceKey: TaskListStyle.classic.name,
          taskRowSpacingPreferenceKey: TaskRowSpacing.compact.name,
          timelineHourWidthPreferenceKey: 288,
        });
        final open = Completer<SharedPreferences?>();
        final repository = LocalTaskPreferencesRepository(
          PreferencesService(() => open.future),
        );
        addTearDown(repository.dispose);
        final updates = <TaskPreferences>[];
        final subscription = repository.watch().listen(updates.add);
        addTearDown(subscription.cancel);

        final loading = repository.load();
        final style = repository.setListStyle(TaskListStyle.modern);
        final spacing = repository.setRowSpacing(TaskRowSpacing.spacious);
        open.complete(await SharedPreferences.getInstance());
        (await loading).getOrThrow();
        (await style).getOrThrow();
        (await spacing).getOrThrow();

        expect(repository.state.listStyle, TaskListStyle.modern);
        expect(repository.state.rowSpacing, TaskRowSpacing.spacious);
        expect(repository.state.hourWidth, 288);
        expect(updates, isNotEmpty);
        expect(updates.last, same(repository.state));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(taskRowSpacingPreferenceKey), 'spacious');
      },
    );

    test('language selection wins over a late stored value', () async {
      SharedPreferences.setMockInitialValues({
        appLanguagePreferenceKey: AppLanguage.ru.storageValue,
      });
      final open = Completer<SharedPreferences?>();
      final repository = LocalLanguageRepository(
        PreferencesService(() => open.future),
      );
      addTearDown(repository.dispose);
      final seen = <AppLanguage>[];
      final subscription = repository.watch().listen(seen.add);
      addTearDown(subscription.cancel);

      final saving = repository.setLanguage(AppLanguage.de);
      open.complete(await SharedPreferences.getInstance());

      (await saving).getOrThrow();
      (await repository.ready).getOrThrow();
      expect(repository.language, AppLanguage.de);
      expect(seen, [AppLanguage.de]);
    });

    test(
      'voice preferences keep an explicit mode and smart-mode choice',
      () async {
        SharedPreferences.setMockInitialValues({
          voiceTranscriptionModePreferenceKey:
              VoiceTranscriptionMode.cloud.storageValue,
          voiceSmartModePreferenceKey: false,
        });
        final open = Completer<SharedPreferences?>();
        final repository = LocalVoicePreferencesRepository(
          PreferencesService(() => open.future),
        );
        addTearDown(repository.dispose);

        final mode = repository.setMode(VoiceTranscriptionMode.system);
        final smartMode = repository.setSmartMode(true);
        open.complete(await SharedPreferences.getInstance());
        (await mode).getOrThrow();
        (await smartMode).getOrThrow();
        (await repository.ready).getOrThrow();

        expect(repository.mode, VoiceTranscriptionMode.system);
        expect(repository.smartMode, isTrue);
      },
    );

    test('focus clear invalidates an in-flight preference load', () async {
      SharedPreferences.setMockInitialValues({
        focusViewModePreferenceKey: 'full',
      });
      final open = Completer<SharedPreferences?>();
      final repository = StoredFocusPreferencesRepository(
        PreferencesService(() => open.future),
      );
      addTearDown(repository.dispose);

      final loading = repository.load();
      final clearing = repository.clear();
      open.complete(await SharedPreferences.getInstance());
      (await loading).getOrThrow();
      (await clearing).getOrThrow();

      expect(repository.state.viewMode, FocusViewMode.minimal);
      expect(
        (await SharedPreferences.getInstance()).getString(
          focusViewModePreferenceKey,
        ),
        isNull,
      );
    });

    test('theme mode selection wins over a late stored value', () async {
      SharedPreferences.setMockInitialValues({
        appThemeModePreferenceKey: AppThemeMode.light.storageValue,
      });
      final open = Completer<SharedPreferences?>();
      final container = ProviderContainer(
        overrides: [
          preferencesServiceProvider.overrideWithValue(
            PreferencesService(() => open.future),
          ),
          sharedThemeCookieReaderProvider.overrideWithValue(() => ''),
          sharedThemeCookieWriterProvider.overrideWithValue((_) {}),
        ],
      );
      addTearDown(container.dispose);

      final selection = container
          .read(appThemeModeProvider.notifier)
          .setThemeMode(AppThemeMode.dark);
      open.complete(await SharedPreferences.getInstance());
      await selection;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(appThemeModeProvider), AppThemeMode.dark);
      expect(
        (await SharedPreferences.getInstance()).getString(
          appThemeModePreferenceKey,
        ),
        AppThemeMode.dark.storageValue,
      );
    });
  });

  group('session event owners', () {
    test('focus completion identity is shared and never replayed', () {
      final repository = DefaultFocusCompletionRepository();
      addTearDown(repository.dispose);
      FocusRunCompletionEvent event(String id) => FocusRunCompletionEvent(
        runId: id,
        completedWorkIntervals: 4,
        targetWorkIntervals: 4,
        completedAt: DateTime.utc(2026, 9, 20),
      );
      final seen = <String?>[];
      final firstSubscription = repository.watch().listen(
        (event) => seen.add(event?.runId),
      );
      addTearDown(firstSubscription.cancel);

      repository.present(event('run-1'));
      expect(repository.state?.runId, 'run-1');
      expect(repository.tryBeginAction('run-1'), isTrue);
      expect(repository.tryBeginAction('run-1'), isFalse);
      repository.endAction('run-1');
      repository.dismiss(runId: 'run-1');
      repository.present(event('run-1'));
      expect(repository.state, isNull);
      expect(seen, ['run-1', null]);

      firstSubscription.cancel();
      repository.present(event('run-2'));
      expect(repository.state?.runId, 'run-2');
      expect(seen, ['run-1', null]);
      repository.dismiss(runId: 'run-2');
      expect(repository.state, isNull);
    });

    test('achievement queue deduplicates across observers', () {
      final repository = DefaultAchievementAnnouncementRepository();
      addTearDown(repository.dispose);
      AchievementItem item(String id) => AchievementItem(
        id: id,
        group: AchievementGroup.focus,
        presentation: AchievementPresentation.globalBanner,
        progress: 1,
        target: 1,
      );
      final seen = <AchievementAnnouncementState>[];
      final subscription = repository.watch().listen(seen.add);
      addTearDown(subscription.cancel);

      repository.enqueue([item('a'), item('b'), item('a')]);
      expect(repository.state.current?.id, 'a');
      expect(repository.state.queue.map((item) => item.id), ['b', 'a']);

      repository.enqueue([item('a'), item('c')]);
      expect(repository.state.queue.map((item) => item.id), ['b', 'a', 'c']);

      repository.dismissCurrent();
      expect(repository.state.current?.id, 'b');
      expect(repository.state.queue.map((item) => item.id), ['a', 'c']);
      expect(seen, isNotEmpty);
      expect(seen.last, same(repository.state));
    });
  });

  group('app preference repositories', () {
    test('round-trip plain values through the preference service', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(SharedPreferences.getInstance);

      final zoom = LocalAppZoomRepository(preferences);
      expect((await zoom.read()).getOrThrow(), isNull);
      (await zoom.write(130)).getOrThrow();
      expect((await zoom.read()).getOrThrow(), 130);

      final themeMode = LocalThemeModeRepository(preferences);
      expect((await themeMode.read()).getOrThrow(), isNull);
      (await themeMode.write('dark')).getOrThrow();
      expect((await themeMode.read()).getOrThrow(), 'dark');

      final shortcuts = LocalKeyboardShortcutsRepository(preferences);
      expect((await shortcuts.read()).getOrThrow(), isNull);
      (await shortcuts.write('{"quickAdd":1}')).getOrThrow();
      expect((await shortcuts.read()).getOrThrow(), '{"quickAdd":1}');

      final themeSettings = LocalThemeSettingsRepository(preferences);
      expect((await themeSettings.read()).getOrThrow(), isNull);
      expect((await themeSettings.readBackup()).getOrThrow(), isNull);
      (await themeSettings.write('{"version":2}')).getOrThrow();
      (await themeSettings.writeBackup('{"version":1}')).getOrThrow();
      expect((await themeSettings.read()).getOrThrow(), '{"version":2}');
      expect((await themeSettings.readBackup()).getOrThrow(), '{"version":1}');
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('app.themeSettings'), '{"version":2}');
      expect(stored.getString('app.themeSettings.v1Backup'), '{"version":1}');
    });

    test('unexpected stored types are ignored instead of published', () async {
      SharedPreferences.setMockInitialValues({
        'app.zoomPercent': 'huge',
        'app.themeMode': 4,
        'keyboard.shortcuts.v1': true,
      });
      final preferences = PreferencesService(SharedPreferences.getInstance);

      expect(
        (await LocalAppZoomRepository(preferences).read()).getOrThrow(),
        isNull,
      );
      expect(
        (await LocalThemeModeRepository(preferences).read()).getOrThrow(),
        isNull,
      );
      expect(
        (await LocalKeyboardShortcutsRepository(
          preferences,
        ).read()).getOrThrow(),
        isNull,
      );
    });
  });
}
