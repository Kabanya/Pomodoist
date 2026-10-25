import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/clock_provider.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/onboarding/view_models/onboarding_view_model.dart';
import 'package:pomodoist/ui/core/view_models/app_theme_mode_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/task_settings_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/repositories/focus/focus_preferences_repository.dart';
import 'package:pomodoist/utils/clock.dart';
// Override disk writes to test the existing onboarding error/retry path.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'launch offer is consumed only after display and survives restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(onboardingViewModelProvider.notifier);
      await container.read(sharedPreferencesProvider.future);
      await container.pump();
      final saved = await SharedPreferences.getInstance();
      expect(
        container.read(onboardingViewModelProvider).launchOfferShown,
        isFalse,
      );
      expect(saved.getBool('launchOffer.shown.v1'), isNull);

      await controller.markLaunchOfferShown();
      expect(
        container.read(onboardingViewModelProvider).launchOfferShown,
        isTrue,
      );
      expect(saved.getBool('launchOffer.shown.v1'), isTrue);

      final nextWeek = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 11, 2)),
          ),
        ],
      );
      addTearDown(nextWeek.dispose);
      nextWeek.read(onboardingViewModelProvider);
      await nextWeek.read(sharedPreferencesProvider.future);
      await nextWeek.pump();
      expect(
        nextWeek.read(onboardingViewModelProvider).launchOfferShown,
        isTrue,
      );
    },
  );

  test('launch offer cannot be consumed before preferences load', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(onboardingViewModelProvider.notifier);
    await controller.markLaunchOfferShown();
    await container.read(sharedPreferencesProvider.future);
    await container.pump();
    expect(
      container.read(onboardingViewModelProvider).launchOfferShown,
      isFalse,
    );
    expect(
      (await SharedPreferences.getInstance()).getBool('launchOffer.shown.v1'),
      isNull,
    );
  });

  test(
    'failed launch offer save still consumes this session without throwing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(onboardingViewModelProvider.notifier);
      await container.read(sharedPreferencesProvider.future);
      await container.pump();
      final original = SharedPreferencesStorePlatform.instance;
      final store = _FailingSessionStore(
        await original.getAll(),
        failedKey: 'launchOffer.shown.v1',
      );
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);

      await controller.markLaunchOfferShown();
      expect(
        container.read(onboardingViewModelProvider).launchOfferShown,
        isTrue,
      );
      expect((await store.getAll())['flutter.launchOffer.shown.v1'], isNull);
      store.fail = false;
      await controller.markLaunchOfferShown();
      expect((await store.getAll())['flutter.launchOffer.shown.v1'], isNull);
    },
  );

  test('finishing onboarding leaves one learning invitation pending', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(onboardingViewModelProvider.notifier);
    await container.read(sharedPreferencesProvider.future);
    await container.pump();

    await controller.complete();
    final saved = await SharedPreferences.getInstance();
    expect(saved.getBool('onboarding.completed.v1'), isTrue);
    expect(saved.getBool('learningTour.invitationPending.v1'), isTrue);
  });

  test(
    'timer choices start with circle and compact, including before loading',
    () async {
      expect(onboardingTimerStyles, [
        FocusTimerVisualStyle.circle,
        FocusTimerVisualStyle.bar,
      ]);
      expect(onboardingSessionDisplays, [
        FocusSessionDisplay.compact,
        FocusSessionDisplay.icons,
      ]);
      expect(const OnboardingState().timerStyle, FocusTimerVisualStyle.circle);
      expect(
        const OnboardingState().sessionDisplay,
        FocusSessionDisplay.compact,
      );
      for (final stored in [null, 'unknown']) {
        SharedPreferences.setMockInitialValues({
          focusTimerVisualStylePreferenceKey: ?stored,
          focusSessionDisplayPreferenceKey: ?stored,
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(onboardingViewModelProvider);
        await container.read(sharedPreferencesProvider.future);
        await container.pump();
        final state = container.read(onboardingViewModelProvider);
        expect(state.timerStyle, FocusTimerVisualStyle.circle);
        expect(state.sessionDisplay, FocusSessionDisplay.compact);
      }
    },
  );

  test(
    'timer and session choices update independently and observe Focus changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(onboardingViewModelProvider.notifier);
      await container.read(sharedPreferencesProvider.future);
      await container.pump();
      for (final style in onboardingTimerStyles) {
        await controller.setTimerStyle(style);
        for (final display in onboardingSessionDisplays) {
          await controller.setSessionDisplay(display);
          await container.pump();
          final state = container.read(onboardingViewModelProvider);
          expect(state.timerStyle, style);
          expect(state.sessionDisplay, display);
          expect(
            container.read(focusPreferencesStateProvider).sessionDisplay,
            display,
          );
        }
      }
      (await container
              .read(focusPreferencesRepositoryProvider)
              .setSessionDisplay(FocusSessionDisplay.compact))
          .getOrThrow();
      await container.pump();
      expect(
        container.read(onboardingViewModelProvider).sessionDisplay,
        FocusSessionDisplay.compact,
      );
    },
  );

  test(
    'session save failure reaches onboarding feedback and can be retried',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(onboardingViewModelProvider.notifier);
      await container.read(sharedPreferencesProvider.future);
      await container.pump();
      final original = SharedPreferencesStorePlatform.instance;
      final store = _FailingSessionStore(await original.getAll());
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      await expectLater(
        controller.setSessionDisplay(FocusSessionDisplay.icons),
        throwsStateError,
      );
      expect(
        container.read(onboardingViewModelProvider).sessionDisplay,
        FocusSessionDisplay.compact,
      );
      store.fail = false;
      await controller.setSessionDisplay(FocusSessionDisplay.icons);
      await container.pump();
      expect(
        container.read(onboardingViewModelProvider).sessionDisplay,
        FocusSessionDisplay.icons,
      );
      expect(
        (await store.getAll())['flutter.$focusSessionDisplayPreferenceKey'],
        'icons',
      );
    },
  );

  test(
    'appearance steps precede Pro and retain settings across navigation and restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(onboardingViewModelProvider.notifier);
      await container.read(sharedPreferencesProvider.future);
      await container.read(appThemeSettingsProvider.notifier).load();
      await container.pump();
      const steps = [
        OnboardingStep.language,
        OnboardingStep.timer,
        OnboardingStep.tasks,
        OnboardingStep.theme,
        OnboardingStep.paywall,
        OnboardingStep.account,
      ];
      expect(OnboardingStep.values, steps);
      for (final step in steps.skip(1)) {
        controller.next();
        expect(container.read(onboardingViewModelProvider).step, step);
        expect(container.read(onboardingViewModelProvider).completed, isFalse);
      }
      for (final step in steps.reversed.skip(1)) {
        controller.back();
        expect(container.read(onboardingViewModelProvider).step, step);
      }
      controller.selectStep(OnboardingStep.tasks);
      final tasks = container.read(taskListSettingsViewModelProvider.notifier);
      await tasks.setStyle(TaskListStyle.classic);
      await tasks.setSpacing(TaskRowSpacing.compact);
      await tasks.setBranchStyle(TaskBranchStyle.grouped);
      controller.next();
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.theme,
      );
      await container
          .read(appThemeSettingsProvider.notifier)
          .selectTheme('ocean');
      await container
          .read(appThemeModeProvider.notifier)
          .setThemeMode(AppThemeMode.dark);
      controller.back();
      final selected = container.read(taskListSettingsViewModelProvider);
      expect(selected.style, TaskListStyle.classic);
      expect(selected.spacing, TaskRowSpacing.compact);
      expect(selected.branchStyle, TaskBranchStyle.grouped);
      await controller.complete();

      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      restored.read(onboardingViewModelProvider);
      restored.read(taskListSettingsViewModelProvider);
      restored.read(appThemeModeProvider);
      await restored.read(sharedPreferencesProvider.future);
      await restored.read(appThemeSettingsProvider.notifier).load();
      await restored.pump();
      expect(restored.read(onboardingViewModelProvider).completed, isTrue);
      expect(restored.read(taskListSettingsViewModelProvider), selected);
      expect(restored.read(appThemeSettingsProvider).selectedId, 'ocean');
      expect(restored.read(appThemeModeProvider), AppThemeMode.dark);
    },
  );

  test(
    'swipes respect direction, ignore slow drags, and never finish onboarding',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(onboardingViewModelProvider.notifier);
      await container.read(sharedPreferencesProvider.future);
      await container.pump();
      controller.swipe(-100, rightToLeft: false);
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.language,
      );
      controller.swipe(-300, rightToLeft: false);
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.timer,
      );
      controller.swipe(-300, rightToLeft: true);
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.language,
      );
      controller.swipe(300, rightToLeft: true);
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.timer,
      );
      controller.selectStep(OnboardingStep.account);
      controller.swipe(-300, rightToLeft: false);
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.account,
      );
      expect(container.read(onboardingViewModelProvider).completed, isFalse);
    },
  );

  test(
    'jumping between slides retains settings and requires explicit completion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(onboardingViewModelProvider.notifier);
      await container.read(sharedPreferencesProvider.future);
      await container.read(languageRepositoryProvider).ready;
      await container.pump();
      expect(container.read(onboardingViewModelProvider).loading, isFalse);
      await controller.setLanguage(AppLanguage.ru);
      await controller.setTimerStyle(FocusTimerVisualStyle.bar);
      await controller.setSessionDisplay(FocusSessionDisplay.icons);
      await container.pump();
      controller.selectStep(OnboardingStep.account);
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.account,
      );
      expect(container.read(onboardingViewModelProvider).completed, isFalse);
      controller.back();
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.paywall,
      );
      controller.selectStep(OnboardingStep.language);
      controller.back();
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.language,
      );
      expect(
        container.read(onboardingViewModelProvider).language,
        AppLanguage.ru,
      );
      expect(
        container.read(onboardingViewModelProvider).timerStyle,
        FocusTimerVisualStyle.bar,
      );
      controller.next();
      expect(
        container.read(onboardingViewModelProvider).step,
        OnboardingStep.timer,
      );
      await controller.complete();
      expect(container.read(onboardingViewModelProvider).completed, isTrue);
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      reopened.read(onboardingViewModelProvider);
      await reopened.read(sharedPreferencesProvider.future);
      await reopened.read(languageRepositoryProvider).ready;
      await reopened.pump();
      final saved = reopened.read(onboardingViewModelProvider);
      expect(saved.completed, isTrue);
      expect(saved.language, AppLanguage.ru);
      expect(saved.timerStyle, FocusTimerVisualStyle.bar);
      expect(saved.sessionDisplay, FocusSessionDisplay.icons);
    },
  );
}

class _FailingSessionStore extends InMemorySharedPreferencesStore {
  _FailingSessionStore(
    super.data, {
    this.failedKey = focusSessionDisplayPreferenceKey,
  }) : super.withData();
  final String failedKey;
  bool fail = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail && key == 'flutter.$failedKey') {
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
