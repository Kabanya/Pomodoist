import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/social_provider.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class AccountAuthActionsRepository {
  AccountAuthFailure classify(
    Object error, {
    required AccountAuthOperation operation,
  });
  Future<Result<bool>> signInSocial(
    PomodoistSocialProvider provider, {
    required String redirectTo,
  });
  Future<Result<String?>> requestNativeCaptcha(String locale);
}

class DefaultAccountAuthActionsRepository
    implements AccountAuthActionsRepository {
  const DefaultAccountAuthActionsRepository({
    required this.classifier,
    required this.socialSignIn,
    required this.nativeCaptcha,
  });

  final AccountAuthFailure Function(
    Object error, {
    required AccountAuthOperation operation,
  })
  classifier;
  final Future<bool> Function(
    PomodoistSocialProvider provider,
    String redirectTo,
  )
  socialSignIn;
  final Future<String?> Function(String locale) nativeCaptcha;

  @override
  AccountAuthFailure classify(
    Object error, {
    required AccountAuthOperation operation,
  }) => classifier(error, operation: operation);

  @override
  Future<Result<bool>> signInSocial(
    PomodoistSocialProvider provider, {
    required String redirectTo,
  }) => Result.capture(() => socialSignIn(provider, redirectTo));

  @override
  Future<Result<String?>> requestNativeCaptcha(String locale) =>
      Result.capture(() => nativeCaptcha(locale));
}
