import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

/// Only compositor output identity/geometry crosses this boundary.
class PomoMonitorSample {
  const PomoMonitorSample({
    this.name,
    this.x,
    this.y,
    this.width,
    this.height,
    this.cursorX,
    this.cursorY,
  });
  final String? name;
  final double? x, y, width, height, cursorX, cursorY;
}

abstract interface class PomoFollowTransport {
  Future<PomoFollowSource> probe(PomoEnvironment environment);
  Future<void> start(
    PomoEnvironment environment,
    void Function(PomoMonitorSample) onSample,
    void Function() onDisconnect,
  );
  Future<PomoMonitorSample?> sample();
  Future<void> stop();
  void dispose();
}

/// A bounded read-only query to a compositor command socket.
typedef PomoSocketRequest =
    Future<Object?> Function(String path, String request, int? swayType);
