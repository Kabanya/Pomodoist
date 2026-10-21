import 'package:pomodoist/domain/models/focus/focus_models.dart';

abstract interface class PomoActivityRepository {
  /// Local work history after the latest completed break, across Focus runs.
  Stream<List<FocusIntervalItem>> watchSinceBreak();
}
