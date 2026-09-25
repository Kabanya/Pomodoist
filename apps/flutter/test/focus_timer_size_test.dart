import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/focus/widgets/focus_stage.dart';

void main() {
  test('timer grows with usable area and stays bounded in narrow windows', () {
    final compact = focusTimerDiameter(const Size(360, 640));
    final desktop = focusTimerDiameter(const Size(1000, 900));
    expect(desktop, greaterThan(compact));
    expect(focusTimerDiameter(const Size(1000, 500)), lessThan(desktop));
    expect(focusTimerDiameter(const Size(220, 900)), lessThanOrEqualTo(220));
    expect(focusTimerDiameter(const Size(2400, 1600)), lessThan(800));
    expect(focusTimerDiameter(Size.zero), 0);
  });
}
