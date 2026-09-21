import 'dart:async';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';

import 'strict_fake.dart';

typedef EnqueueCall = ({
  String type,
  Map<String, Object?> payload,
  String? clientId,
  DateTime? availableAt,
});

typedef EnqueueBatchCall = ({
  List<SyncQueueCommand> commands,
  DateTime? occurredAt,
});

/// Configurable [OutboxService] double.
///
/// Every method has a working default, so a test only has to set the fields it
/// cares about. Calls are appended to the matching recording list, and a write
/// whose `<method>Error` field is non-null throws it synchronously, the way a
/// failing drift write does.
///
/// [watchPending] replays [pending] to each new subscriber and then forwards
/// every [emit], so a test can push a batch the way the drift-backed service
/// does.
class FakeOutboxService extends StrictFake implements OutboxService {
  /// Batch [watchPending] replays to a new subscriber.
  List<SyncCommandRow> pending = const [];

  Object? enqueueError;
  Object? enqueueBatchError;

  final enqueueCalls = <EnqueueCall>[];
  final enqueueBatchCalls = <EnqueueBatchCall>[];
  final watchPendingCalls = <void>[];

  final _controller = StreamController<List<SyncCommandRow>>.broadcast();

  @override
  Future<void> enqueue({
    required String type,
    required Map<String, Object?> payload,
    String? clientId,
    DateTime? availableAt,
  }) {
    enqueueCalls.add((
      type: type,
      payload: payload,
      clientId: clientId,
      availableAt: availableAt,
    ));
    final error = enqueueError;
    if (error != null) throw error;
    return Future<void>.value();
  }

  @override
  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  }) {
    enqueueBatchCalls.add((commands: commands, occurredAt: occurredAt));
    final error = enqueueBatchError;
    if (error != null) throw error;
    return Future<void>.value();
  }

  @override
  Stream<List<SyncCommandRow>> watchPending() {
    watchPendingCalls.add(null);
    return _replay();
  }

  /// Publishes [commands] to [watchPending] listeners and as the new [pending].
  void emit(List<SyncCommandRow> commands) {
    pending = commands;
    _controller.add(commands);
  }

  /// Closes the broadcast stream, so late listeners only get the replay.
  Future<void> dispose() => _controller.close();

  Stream<List<SyncCommandRow>> _replay() async* {
    yield pending;
    yield* _controller.stream;
  }
}
