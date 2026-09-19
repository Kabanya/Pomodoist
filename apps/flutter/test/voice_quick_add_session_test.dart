import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/tasks/widgets/voice_quick_add_session.dart';

void main() {
  test(
    'voice activity follows one session and ignores stale completion',
    () async {
      final sessions = VoiceQuickAddSessionSlot<Object>();
      final otherOverlay = VoiceQuickAddSessionSlot<Object>();
      addTearDown(sessions.dispose);
      addTearDown(otherOverlay.dispose);
      final activity = <bool>[];
      sessions.addListener(() => activity.add(sessions.value));
      final first = Object();
      final second = Object();

      expect(sessions.value, isFalse);
      expect(sessions.open(first), same(first));
      expect(sessions.open(second), same(first));
      expect(sessions.current, same(first));
      expect(sessions.value, isTrue);
      expect(otherOverlay.value, isFalse);
      expect(activity, [true]);

      sessions.finish(second);
      expect(sessions.value, isTrue);
      sessions.finish(first);
      sessions.finish(first);
      expect(sessions.value, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(activity, [true, false]);

      sessions.open(first);
      sessions.finish(first);
      sessions.open(second);
      sessions.finish(first);
      await Future<void>.delayed(Duration.zero);
      expect(sessions.current, same(second));
      expect(sessions.value, isTrue);
      expect(activity.skip(2), everyElement(isTrue));

      sessions.finish(second);
      await Future<void>.delayed(Duration.zero);
      expect(activity.last, isFalse);
    },
  );
}
