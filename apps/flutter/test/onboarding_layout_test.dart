import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/onboarding/widgets/onboarding_gate.dart';

void main() {
  test('phone onboarding stays fullscreen when rotated', () {
    expect(onboardingUsesFullScreen(const Size(390, 844)), isTrue);
    expect(onboardingUsesFullScreen(const Size(844, 390)), isTrue);
    expect(onboardingUsesFullScreen(const Size(520, 900)), isTrue);
    expect(onboardingUsesFullScreen(const Size(820, 1180)), isFalse);
    expect(onboardingUsesFullScreen(const Size(1280, 800)), isFalse);
  });
}
