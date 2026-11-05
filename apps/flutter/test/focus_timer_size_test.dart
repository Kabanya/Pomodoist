import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/focus/widgets/focus_stage.dart';

void main() {
  test('the shared dial fits narrow content and caps at 320 px', () {
    expect(focusTimerDiameter(220), 220);
    expect(focusTimerDiameter(900), 320);
  });
}
