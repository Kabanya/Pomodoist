import 'package:pomodoist/domain/models/account/ai_quota.dart';

abstract interface class AiQuotaRepository {
  Future<AiQuota> load();
}
