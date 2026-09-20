import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/email_auth.dart';
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
  Future<Result<EmailAuthResult?>> submitEmail({
    required EmailAuthAction action,
    required String email,
    required String password,
    required String redirectTo,
    String? captchaToken,
  });
}

class DefaultAccountAuthActionsRepository
    implements AccountAuthActionsRepository {
  const DefaultAccountAuthActionsRepository({
    required this.classifier,
    required this.socialSignIn,
    required this.nativeCaptcha,
    required this.emailSubmit,
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
  final Future<EmailAuthResult?> Function({
    required EmailAuthAction action,
    required String email,
    required String password,
    required String redirectTo,
    String? captchaToken,
  })
  emailSubmit;

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

  @override
  Future<Result<EmailAuthResult?>> submitEmail({
    required EmailAuthAction action,
    required String email,
    required String password,
    required String redirectTo,
    String? captchaToken,
  }) => Result.capture(
    () => emailSubmit(
      action: action,
      email: email,
      password: password,
      redirectTo: redirectTo,
      captchaToken: captchaToken,
    ),
  );
}
