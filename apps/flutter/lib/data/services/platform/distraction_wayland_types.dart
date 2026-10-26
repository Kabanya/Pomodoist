abstract class DistractionWaylandAdapter {
  Future<Map<String, Object?>?> capabilities();
  Future<void> command(String method, Map<String, Object?> arguments);
  Future<void> dispose();
}
