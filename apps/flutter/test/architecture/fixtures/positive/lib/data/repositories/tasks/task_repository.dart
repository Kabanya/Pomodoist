abstract interface class TaskRepository {
  Future<void> complete(String id);
}
