import 'package:drift/native.dart';
import 'package:pomodoist/core/db/app_database.dart';

AppDatabase createNavigationProfileDatabase() =>
    AppDatabase(NativeDatabase.memory());
