import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/voice_panel_motion.dart';

void main() {
  test('panel swipes require deliberate vertical movement and fire once', () {
    final swipe = VoicePanelSwipe()..begin(expanded: false);
    swipe.add(const Offset(3, -24));
    expect(swipe.takeAction(), isNull);
    swipe.add(const Offset(-2, -23));
    expect(swipe.takeAction(), isNull);
    swipe.add(const Offset(0, -1));
    expect(swipe.takeAction(), isTrue);
    swipe.add(const Offset(0, 150));
    expect(swipe.takeAction(), isNull);

    swipe.begin(expanded: true);
    swipe.add(const Offset(5, 48));
    expect(swipe.takeAction(), isFalse);

    for (final delta in [const Offset(60, 40), const Offset(0, -25)]) {
      swipe.begin(expanded: true);
      swipe.add(delta);
      swipe.add(const Offset(0, 100));
      expect(swipe.takeAction(), isNull);
    }
    swipe.begin(expanded: false);
    swipe.add(const Offset(0, 24));
    swipe.add(const Offset(0, -100));
    expect(swipe.takeAction(), isNull);

    // Pinch, capsule dragging, or a second finger cancels the entire gesture.
    swipe.begin(expanded: true);
    swipe.add(const Offset(0, 30));
    swipe.cancel();
    swipe.add(const Offset(0, 100));
    expect(swipe.takeAction(), isNull);
    swipe.begin(expanded: true);
    swipe.add(const Offset(0, 48));
    expect(swipe.takeAction(), isFalse);
  });

  test('wheel bursts normalize direction and preserve cancellation', () {
    final swipe = VoicePanelSwipe();
    swipe.scroll(const Offset(0, 30), Duration.zero, expanded: false);
    expect(swipe.takeAction(), isNull);
    swipe.scroll(
      const Offset(0, 20),
      const Duration(milliseconds: 30),
      expanded: false,
    );
    expect(swipe.takeAction(), isTrue);
    swipe.scroll(
      const Offset(0, -90),
      const Duration(milliseconds: 100),
      expanded: true,
    );
    expect(swipe.takeAction(), isNull);
    swipe.scroll(
      const Offset(0, -60),
      const Duration(milliseconds: 180),
      expanded: true,
    );
    expect(swipe.takeAction(), isNull);

    swipe.scroll(
      const Offset(0, -20),
      const Duration(milliseconds: 500),
      expanded: true,
    );
    swipe.cancel(); // Modified wheel input cancels the whole burst.
    swipe.scroll(
      const Offset(0, -80),
      const Duration(milliseconds: 530),
      expanded: true,
    );
    expect(swipe.takeAction(), isNull);
    swipe.scroll(
      const Offset(0, -48),
      const Duration(milliseconds: 800),
      expanded: true,
    );
    expect(swipe.takeAction(), isFalse);
  });
}
