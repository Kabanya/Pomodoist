import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/focus/widgets/focus_stage.dart';

void main() {
  test('timer grows with usable area and stays bounded in narrow windows', () {
    final narrow = focusTimerDiameter(220, compact: true);
    final wide = focusTimerDiameter(900, compact: true);
    expect(wide, greaterThan(narrow));
    expect(focusTimerDiameter(1000, compact: true), 300);
    expect(focusTimerDiameter(220, compact: true), lessThanOrEqualTo(220));
    expect(focusTimerDiameter(2400, compact: true), lessThan(800));
    expect(focusTimerDiameter(200, compact: false), 320);
    expect(focusTimerDiameter(2400, compact: false), 320);
  });
}
