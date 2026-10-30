import 'package:pomodoist/domain/models/settings/status_item_style.dart';

abstract interface class StatusItemStyleRepository {
  Stream<StatusItemStyle> get changes;
  Future<StatusItemStyle> read();
  Future<StatusItemStyle> select(StatusItemStyle style);
}
