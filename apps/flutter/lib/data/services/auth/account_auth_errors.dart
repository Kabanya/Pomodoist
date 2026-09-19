import 'dart:async';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/captcha_security.dart';

AccountAuthFailure classifyAccountAuthFailure(
  Object error, {
  required AccountAuthOperation operation,
}) {
  if (error is AccountAuthFailure) return error;
  if (error is NativeCaptchaException) {
    return switch (error.code) {
      NativeCaptchaFailureCode.cancelled => const AccountAuthFailure(
        AccountAuthFailureKind.captchaCancelled,
        field: AccountAuthField.captcha,
        recovery: AccountAuthRecovery.retryCaptcha,
      ),
      NativeCaptchaFailureCode.expired => const AccountAuthFailure(
        AccountAuthFailureKind.captchaExpired,
        field: AccountAuthField.captcha,
        recovery: AccountAuthRecovery.retryCaptcha,
      ),
      NativeCaptchaFailureCode.openFailed => const AccountAuthFailure(
        AccountAuthFailureKind.captchaOpenFailed,
        field: AccountAuthField.captcha,
        recovery: AccountAuthRecovery.retryCaptcha,
      ),
      NativeCaptchaFailureCode.invalidCallback => const AccountAuthFailure(
        AccountAuthFailureKind.captchaFailed,
        field: AccountAuthField.captcha,
        recovery: AccountAuthRecovery.retryCaptcha,
      ),
      NativeCaptchaFailureCode.unavailable => const AccountAuthFailure(
        AccountAuthFailureKind.captchaUnavailable,
        field: AccountAuthField.captcha,
        recovery: AccountAuthRecovery.retryCaptcha,
      ),
    };
  }
  if (error is TimeoutException) {
    return const AccountAuthFailure(
      AccountAuthFailureKind.timeout,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    );
  }
  if (error is PlatformException && _isCancellationCode(error.code)) {
    return const AccountAuthFailure(
      AccountAuthFailureKind.cancelled,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.none,
    );
  }
  if (error is AuthRetryableFetchException) {
    return AccountAuthFailure(
      error.statusCode == null
          ? AccountAuthFailureKind.offline
          : AccountAuthFailureKind.serviceUnavailable,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    );
  }
  if (error is AuthSessionMissingException &&
      operation == AccountAuthOperation.passwordUpdate) {
    return const AccountAuthFailure(
      AccountAuthFailureKind.linkExpired,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.sendNewLink,
    );
  }
  if (error is AuthException) {
    if (error.code == null) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 401 && operation == AccountAuthOperation.passwordUpdate) {
        return const AccountAuthFailure(
          AccountAuthFailureKind.linkExpired,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.sendNewLink,
        );
      }
      if (status == 429) {
        return AccountAuthFailure(
          operation == AccountAuthOperation.magicLink ||
                  operation == AccountAuthOperation.confirmationEmail ||
                  operation == AccountAuthOperation.passwordReset ||
                  operation == AccountAuthOperation.signUp
              ? AccountAuthFailureKind.emailRateLimited
              : AccountAuthFailureKind.rateLimited,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.none,
        );
      }
      if (status != null && status >= 500) {
        return const AccountAuthFailure(
          AccountAuthFailureKind.serviceUnavailable,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.retry,
        );
      }
      if ((status == 400 || status == 401) &&
          operation == AccountAuthOperation.passwordSignIn) {
        return const AccountAuthFailure(
          AccountAuthFailureKind.invalidCredentials,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.editPassword,
        );
      }
    }
    return classifyAccountAuthCode(error.code, operation);
  }
  return accountAuthOperationFallback(operation);
}

bool _isCancellationCode(String value) {
  final normalized = value.toLowerCase().replaceAll('_', '');
  return normalized == 'cancelled' ||
      normalized == 'canceled' ||
      normalized == 'usercancelled' ||
      normalized == 'usercanceled';
}
