import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/focus/presentation/focus_completion_celebration.dart';

void main() {
  test('the completion mark settles while the particles finish', () {
    final drawing = focusCompletionProgress(.15);
    final celebrating = focusCompletionProgress(.5);
    expect(drawing.ring, inExclusiveRange(0, 1));
    expect(drawing.check, 0);
    expect(drawing.particles, 0);
    expect(celebrating.ring, 1);
    expect(celebrating.check, 1);
    expect(celebrating.particles, inExclusiveRange(0, 1));
    expect(celebrating.halo, inExclusiveRange(0, 1));
  });

  test('Reduce Motion resolves every phase to the final frame', () {
    final end = focusCompletionProgress(1);
    expect(end, (ring: 1.0, check: 1.0, halo: 1.0, particles: 1.0));
    for (final progress in [0.0, .15, .5, .9]) {
      expect(focusCompletionProgress(progress, reduceMotion: true), end);
    }
  });

  test('out of range progress stays at the nearest endpoint', () {
    expect(focusCompletionProgress(-1), focusCompletionProgress(0));
    expect(focusCompletionProgress(2), focusCompletionProgress(1));
  });
}
