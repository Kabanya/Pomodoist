import '../../../domain/models/domain_task.dart';

/// Abstract contract whose name does not end in `Repository`; ViewModels may
/// depend on it because classification uses the declaration, not the file name.
abstract interface class TaskDecomposer {
  Future<List<DomainTask>> decompose(DomainTask task);
}
