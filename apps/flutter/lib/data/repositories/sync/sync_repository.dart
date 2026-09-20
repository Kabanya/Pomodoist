import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class SyncRepository {
  Future<Result<Set<String>>> syncNow({
    required AccountSession session,
    required DateTime? retentionCutoff,
  });
}
