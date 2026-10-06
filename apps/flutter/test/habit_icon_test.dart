import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/ui/habits/widgets/habit_icon.dart';

void main() {
  test('missing and future icon names render the existing repeat sign', () {
    expect(habitIconData(null), LucideIcons.repeat2);
    expect(habitIconData('futureIcon'), LucideIcons.repeat2);
    expect(habitIconData('bookOpen'), LucideIcons.bookOpen);
  });
}
