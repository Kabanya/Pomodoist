import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

PomoFollowTransport createTransport() => UnsupportedPomoFollowTransport();

class UnsupportedPomoFollowTransport implements PomoFollowTransport {
  @override
  Future<PomoFollowSource> probe(PomoEnvironment environment) async =>
      PomoFollowSource.none;
  @override
  Future<void> start(
    PomoEnvironment environment,
    void Function(PomoMonitorSample) onSample,
    void Function() onDisconnect,
  ) async {}
  @override
  Future<PomoMonitorSample?> sample() async => null;
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}
