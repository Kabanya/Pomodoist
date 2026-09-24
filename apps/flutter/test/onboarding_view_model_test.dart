import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_language.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';
import 'package:pomodoist/ui/onboarding/view_models/onboarding_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      await controller.setTimerStyle(FocusTimerVisualStyle.circle);
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
        FocusTimerVisualStyle.circle,
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
      expect(saved.timerStyle, FocusTimerVisualStyle.circle);
    },
  );
}
