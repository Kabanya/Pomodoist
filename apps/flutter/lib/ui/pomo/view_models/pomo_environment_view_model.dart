import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_environment_repository.dart';
import 'package:pomodoist/domain/models/pomo/pomo_environment.dart';

final pomoEnvironmentRepositoryProvider = Provider<PomoEnvironmentRepository>(
  (ref) => throw StateError('Pomo environment dependencies were not installed'),
);

final pomoEnvironmentStateProvider = StreamProvider<PomoEnvironment>((
  ref,
) async* {
  final repository = ref.watch(pomoEnvironmentRepositoryProvider);
  // Subscribe before initialization so a synchronous probe cannot be missed.
  final updates = StreamController<PomoEnvironment>();
  final subscription = repository.changes.listen(
    updates.add,
    onError: updates.addError,
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(updates.close());
  });
  yield repository.state;
  unawaited(repository.initialize());
  yield* updates.stream;
});

final pomoAppVersionProvider = FutureProvider<String>(
  (ref) => throw StateError('Pomo version dependency was not installed'),
);
