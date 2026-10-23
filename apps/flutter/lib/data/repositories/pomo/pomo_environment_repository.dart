import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

abstract interface class PomoEnvironmentRepository {
  PomoEnvironment get state;
  Stream<PomoEnvironment> get changes;
  Future<void> initialize();
  Future<void> gnomeExtensionStatus();
  Future<void> installGnomeExtension();
  Future<void> enableGnomeExtension();
  Future<void> startFollowing();
  Future<void> stopFollowing();
  void dispose();
}
