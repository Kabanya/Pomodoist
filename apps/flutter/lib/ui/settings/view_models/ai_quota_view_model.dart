import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/ai_quota_dependencies.dart';
import 'package:pomodoist/domain/models/account/ai_quota.dart';

final aiQuotaViewModelProvider = FutureProvider.autoDispose<AiQuota?>(
  (ref) => ref.watch(aiQuotaRepositoryProvider)?.load(),
);
