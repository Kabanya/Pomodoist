import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_management_dependencies.dart';
import 'package:pomodoist/domain/use_cases/account/delete_account_use_case.dart';

final accountDeleteViewModelProvider =
    AsyncNotifierProvider.autoDispose<AccountDeleteViewModel, bool?>(
      AccountDeleteViewModel.new,
    );

class AccountDeleteViewModel extends AsyncNotifier<bool?> {
  DeleteAccountUseCase? _deleteAccount;
  @override
  bool? build() {
    _deleteAccount = ref.read(deleteAccountUseCaseProvider);
    return null;
  }

  Future<bool?> delete() async {
    if (state.isLoading) return null;
    final keepAlive = ref.keepAlive();
    state = const AsyncLoading();
    try {
      final result = await AsyncValue.guard(() async {
        final deleteAccount = _deleteAccount;
        if (deleteAccount == null) throw StateError('Account unavailable');
        return (await deleteAccount()).getOrThrow();
      });
      if (ref.mounted) state = result;
      return result.value;
    } finally {
      keepAlive.close();
    }
  }
}
