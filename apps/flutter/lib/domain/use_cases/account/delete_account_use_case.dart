import 'package:pomodoist/data/repositories/account/account_management_repository.dart';
import 'package:pomodoist/utils/result.dart';

final class DeleteAccountUseCase {
  const DeleteAccountUseCase({
    required AccountManagementRepository repository,
    required Future<void> Function() resetLocalData,
  }) : _repository = repository,
       _resetLocalData = resetLocalData;

  final AccountManagementRepository _repository;
  final Future<void> Function() _resetLocalData;

  Future<Result<bool>> call() => Result.capture(() async {
    (await _repository.deleteRemoteAccount()).getOrThrow();
    var cleanupFailed = false;
    try {
      await _resetLocalData();
    } catch (_) {
      cleanupFailed = true;
    }
    try {
      (await _repository.signOut()).getOrThrow();
    } catch (_) {
      cleanupFailed = true;
    }
    return cleanupFailed;
  });
}
