import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/tasks/widgets/calendar_screen.dart';

void main() {
  test(
    'drop coordinates snap to quarter hours at different display scales',
    () {
      expect(calendarDropMinutes(10.5 * 80, 80), 630);
      expect(calendarDropMinutes(10.5 * 120, 120), 630);
      expect(calendarDropMinutes(21, 80), 15);
      expect(calendarDropMinutes(39, 80), 30);
    },
  );

  test(
    'drops near and beyond grid bounds cannot create an invalid day time',
    () {
      expect(calendarDropMinutes(-45, 80), 0);
      expect(calendarDropMinutes(0, 80), 0);
      expect(calendarDropMinutes(24 * 80, 80), 1425);
      expect(calendarDropMinutes(5000, 80), 1425);
      expect(() => calendarDropMinutes(double.nan, 80), throwsArgumentError);
      expect(() => calendarDropMinutes(10, 0), throwsArgumentError);
    },
  );
}
