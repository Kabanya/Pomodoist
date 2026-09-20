import 'package:app_account/app_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'package:pomodoist/data/services/billing/billing_store.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

/// Remote transport and StoreKit authorization fallback for task analysis.
final class AccountTaskDecompositionTransport {
  const AccountTaskDecompositionTransport({
    required AccountClient? account,
    required BillingStore billingStore,
    required bool localStoreKit,
    required String endpoint,
  }) : _account = account,
       _billingStore = billingStore,
       _localStoreKit = localStoreKit,
       _endpoint = endpoint;

  final AccountClient? _account;
  final BillingStore _billingStore;
  final bool _localStoreKit;
  final String _endpoint;

  Future<Object?> call(Map<String, Object?> body) async {
    final account = _account;
    if (account == null) {
      throw const TaskDecompositionException('Voice analysis is unavailable.');
    }
    final storeTransactions = account.currentUserId != null
        ? const <String>[]
        : await _billingStore.pomodoistTransactionJws();
    try {
      final response = await account.invokeFunction(
        _endpoint,
        body: {
          ...body,
          'storeTransactions': storeTransactions,
          if (_localStoreKit) 'localStoreKit': true,
        },
      );
      if (response.status == 404) throw FunctionException(status: 404);
      return response.data;
    } on FunctionException catch (error) {
      if (error.status != 404) rethrow;
      throw TaskDecompositionException(
        'Voice analysis requires a backend upgrade: deploy $_endpoint and retry analysis.',
      );
    }
  }
}
