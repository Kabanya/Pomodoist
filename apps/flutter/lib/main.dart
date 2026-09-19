import 'package:pomodoist/config/app_environment.dart';
import 'package:pomodoist/config/bootstrap.dart';

Future<void> main() => bootstrapPomodoist(AppEnvironment.production);
