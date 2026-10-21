import 'package:pomodoist/domain/models/pomo/pomo_models.dart';

abstract interface class PomoPreferencesRepository {
  PomoPreferences get state;
  Stream<PomoPreferences> get changes;
  Future<void> load();
  Future<void> update(PomoPreferences Function(PomoPreferences) edit);
}
