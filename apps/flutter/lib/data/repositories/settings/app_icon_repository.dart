import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';

abstract interface class AppIconRepository {
  Future<AppIconChoice> read();
  Future<void> apply(AppIconChoice choice);
}
