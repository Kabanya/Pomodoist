import '../../services/local/task_store.dart';
import 'task_repository.dart';

class DriftTaskRepository implements TaskRepository {
  DriftTaskRepository(this._store);

  final LocalTaskStore _store;

  @override
  Future<void> complete(String id) => _store.writeCompletion(id);
}
