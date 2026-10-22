import 'package:pomodoist/domain/models/pomo/pomo_models.dart';

abstract interface class PomoHost {
  Future<void> show(PomoPreferences preferences);
  Future<void> hide();
  Future<void> resetPosition();
  Future<void> setMenu(bool expanded);
  Future<void> setCapsuleVisible(bool visible);
  Future<void> setScale(double scale);
  Future<void> openSettings();
  Future<void> closeSettings();
}
