import 'package:pomodoist/data/services/local/database/app_database.dart';

abstract interface class RowContractRepository {
  TaskRow? latest();
}
