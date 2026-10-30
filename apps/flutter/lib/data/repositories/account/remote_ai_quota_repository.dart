import 'package:pomodoist/data/repositories/account/ai_quota_repository.dart';
import 'package:pomodoist/domain/models/account/ai_quota.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

final class RemoteAiQuotaRepository implements AiQuotaRepository {
  const RemoteAiQuotaRepository({
    required SupabaseClient client,
    required String owner,
    required String? Function() currentUserId,
    required Duration timeout,
  }) : _client = client,
       _owner = owner,
       _currentUserId = currentUserId,
       _timeout = timeout;

  final SupabaseClient _client;
  final String _owner;
  final String? Function() _currentUserId;
  final Duration _timeout;

  @override
  Future<AiQuota> load() async {
    _checkOwner();
    final value = await _client
        .rpc(
          'get_usage_period',
          params: {'p_app_id': 'pomodoist', 'p_quota_key': 'llm_requests'},
        )
        .timeout(_timeout);
    _checkOwner();
    if (value is! Map) throw const FormatException('Invalid AI quota response');
    return AiQuota.fromJson(Map<String, dynamic>.from(value));
  }

  void _checkOwner() {
    if (_currentUserId() != _owner) {
      throw StateError('The account session has changed.');
    }
  }
}
