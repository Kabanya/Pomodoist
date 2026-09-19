import 'package:app_account/app_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

class CollaborationApi {
  CollaborationApi(this.invoke);
  factory CollaborationApi.account(AccountClient account) => CollaborationApi((
    body,
  ) async {
    late AccountFunctionResponse response;
    try {
      response = await account.invokeFunction(
        'pomodoist-collaboration',
        body: body,
      );
    } on FunctionException catch (error) {
      final data = error.details;
      throw CollaborationException(
        error.status == 404
            ? 'function_not_found'
            : data is Map
            ? data['code']?.toString() ?? 'request_failed'
            : 'request_failed',
        data is Map ? data['error']?.toString() : null,
      );
    }
    if (response.status == 404) {
      throw const CollaborationException('function_not_found');
    }
    final data = response.data;
    if (data is! Map) throw const CollaborationException('invalid_response');
    if (response.status >= 400 && data['error'] == null) {
      throw const CollaborationException('request_failed');
    }
    return Map<String, dynamic>.from(data);
  });
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body) invoke;

  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final result = await invoke({
      'action': action,
      ...arguments,
    }).timeout(const Duration(seconds: 30));
    if (result['error'] != null) {
      throw CollaborationException(
        result['code'] as String? ?? 'request_failed',
        result['error'].toString(),
      );
    }
    return result;
  }
}
