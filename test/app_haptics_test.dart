import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/haptics/app_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playHaptic sends only requested haptic calls', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await playHaptic(AppHapticCue.none);
    expect(calls, isEmpty);

    await playHaptic(AppHapticCue.light);
    await playHaptic(AppHapticCue.success);

    expect(calls.map((call) => (call.method, call.arguments)), [
      ('HapticFeedback.vibrate', 'HapticFeedbackType.lightImpact'),
      ('HapticFeedback.vibrate', 'HapticFeedbackType.mediumImpact'),
    ]);
  });
}
