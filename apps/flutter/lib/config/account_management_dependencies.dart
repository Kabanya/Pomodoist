import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/account/account_management_repository.dart';
import 'package:pomodoist/data/repositories/account/sdk_account_management_repository.dart';
import 'package:pomodoist/data/services/auth/account_profile_service.dart';
import 'package:pomodoist/data/services/account/account_management_service.dart';
import 'package:pomodoist/domain/use_cases/account/delete_account_use_case.dart';
import 'package:pomodoist/data/services/platform/external_url_service.dart';

final accountManagementRepositoryProvider =
    Provider<AccountManagementRepository?>((ref) {
      final account = ref.watch(accountClientProvider);
      final auth = ref.watch(accountAuthStateProvider).value;
      if (account == null || auth?.signedIn == false) return null;
      final userId = account.currentUserId;
      if (auth?.session?.userId != null && auth!.session!.userId != userId) {
        return null;
      }
      return SdkAccountManagementRepository(
        service: AccountManagementService(account),
        userId: userId,
        timeout: ref.watch(accountRequestTimeoutProvider),
        profile: AccountProfileService(Supabase.instance.client),
      );
    });

final deleteAccountUseCaseProvider =
    Provider.autoDispose<DeleteAccountUseCase?>((ref) {
      final repository = ref.watch(accountManagementRepositoryProvider);
      if (repository == null) return null;
      final database = ref.read(appDatabaseProvider);
      return DeleteAccountUseCase(
        repository: repository,
        resetLocalData: database.resetAccountData,
      );
    });

typedef TelegramReturnLauncher = Future<bool> Function(Uri uri);
final telegramReturnLauncherProvider = Provider<TelegramReturnLauncher>(
  (ref) => const ExternalUrlService().open,
);
