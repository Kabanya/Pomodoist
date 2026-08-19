import 'dart:async';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import 'captcha_security.dart';

enum AccountAuthOperation {
  bootstrap,
  passwordSignIn,
  signUp,
  magicLink,
  apple,
  google,
  callback,
  captcha,
}

enum AccountAuthFailureKind {
  emailRequired,
  emailInvalid,
  passwordRequired,
  invalidCredentials,
  emailUnconfirmed,
  weakPassword,
  accountMayExist,
  rateLimited,
  emailRateLimited,
  offline,
  timeout,
  serviceUnavailable,
  captchaRequired,
  captchaExpired,
  captchaFailed,
  captchaCancelled,
  captchaUnavailable,
  captchaOpenFailed,
  providerUnavailable,
  signUpDisabled,
  accountRestricted,
  linkExpired,
  cancelled,
  unexpected,
}

enum AccountAuthField { email, password, captcha, form }

enum AccountAuthRecovery {
  none,
  editEmail,
  editPassword,
  retry,
  retryCaptcha,
  switchToSignIn,
  sendNewLink,
  chooseAnotherProvider,
}

final class AccountAuthFailure {
  const AccountAuthFailure(
    this.kind, {
    required this.field,
    required this.recovery,
  });

  final AccountAuthFailureKind kind;
  final AccountAuthField field;
  final AccountAuthRecovery recovery;

  bool get isCancelled => kind == AccountAuthFailureKind.cancelled;
}

final class AccountAuthFeedback {
  const AccountAuthFeedback({
    required this.message,
    required this.field,
    required this.recovery,
  });

  final String message;
  final AccountAuthField field;
  final AccountAuthRecovery recovery;
}

AccountAuthFailure? validateAccountEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) {
    return const AccountAuthFailure(
      AccountAuthFailureKind.emailRequired,
      field: AccountAuthField.email,
      recovery: AccountAuthRecovery.editEmail,
    );
  }
  final at = email.indexOf('@');
  final domain = at < 0 ? '' : email.substring(at + 1);
  final valid =
      email.length <= 254 &&
      at > 0 &&
      at == email.lastIndexOf('@') &&
      domain.contains('.') &&
      !domain.startsWith('.') &&
      !domain.endsWith('.') &&
      !RegExp(r'\s').hasMatch(email);
  if (valid) return null;
  return const AccountAuthFailure(
    AccountAuthFailureKind.emailInvalid,
    field: AccountAuthField.email,
    recovery: AccountAuthRecovery.editEmail,
  );
}

AccountAuthFailure? validateAccountPassword(String value) {
  if (value.isNotEmpty) return null;
  return const AccountAuthFailure(
    AccountAuthFailureKind.passwordRequired,
    field: AccountAuthField.password,
    recovery: AccountAuthRecovery.editPassword,
  );
}

AccountAuthFailure classifyAccountAuthFailure(
  Object error, {
  required AccountAuthOperation operation,
}) {
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
  if (error is AuthException) {
    if (error.code == null) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 429) {
        return AccountAuthFailure(
          operation == AccountAuthOperation.magicLink ||
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
      if (status == 400 && operation == AccountAuthOperation.passwordSignIn) {
        return const AccountAuthFailure(
          AccountAuthFailureKind.invalidCredentials,
          field: AccountAuthField.password,
          recovery: AccountAuthRecovery.editPassword,
        );
      }
    }
    return _classifyAuthCode(error.code, operation);
  }
  return _operationFallback(operation);
}

AccountAuthFailure _classifyAuthCode(
  String? code,
  AccountAuthOperation operation,
) {
  switch (code) {
    case 'invalid_credentials':
    case 'user_not_found':
      return const AccountAuthFailure(
        AccountAuthFailureKind.invalidCredentials,
        field: AccountAuthField.password,
        recovery: AccountAuthRecovery.editPassword,
      );
    case 'email_not_confirmed':
    case 'provider_email_needs_verification':
      return const AccountAuthFailure(
        AccountAuthFailureKind.emailUnconfirmed,
        field: AccountAuthField.email,
        recovery: AccountAuthRecovery.none,
      );
    case 'weak_password':
      return const AccountAuthFailure(
        AccountAuthFailureKind.weakPassword,
        field: AccountAuthField.password,
        recovery: AccountAuthRecovery.editPassword,
      );
    case 'email_exists':
    case 'user_already_exists':
    case 'identity_already_exists':
    case 'conflict':
      return const AccountAuthFailure(
        AccountAuthFailureKind.accountMayExist,
        field: AccountAuthField.email,
        recovery: AccountAuthRecovery.switchToSignIn,
      );
    case 'validation_failed':
      return const AccountAuthFailure(
        AccountAuthFailureKind.emailInvalid,
        field: AccountAuthField.email,
        recovery: AccountAuthRecovery.editEmail,
      );
    case 'over_email_send_rate_limit':
    case 'email_send_failed':
      return const AccountAuthFailure(
        AccountAuthFailureKind.emailRateLimited,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.none,
      );
    case 'over_request_rate_limit':
      return const AccountAuthFailure(
        AccountAuthFailureKind.rateLimited,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.none,
      );
    case 'captcha_failed':
      return const AccountAuthFailure(
        AccountAuthFailureKind.captchaFailed,
        field: AccountAuthField.captcha,
        recovery: AccountAuthRecovery.retryCaptcha,
      );
    case 'request_timeout':
    case 'hook_timeout':
    case 'hook_timeout_after_retry':
      return const AccountAuthFailure(
        AccountAuthFailureKind.timeout,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.retry,
      );
    case 'signup_disabled':
    case 'email_provider_disabled':
      return const AccountAuthFailure(
        AccountAuthFailureKind.signUpDisabled,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.chooseAnotherProvider,
      );
    case 'provider_disabled':
    case 'oauth_provider_not_supported':
      return const AccountAuthFailure(
        AccountAuthFailureKind.providerUnavailable,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.chooseAnotherProvider,
      );
    case 'user_banned':
      return const AccountAuthFailure(
        AccountAuthFailureKind.accountRestricted,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.none,
      );
    case 'otp_expired':
    case 'flow_state_expired':
    case 'flow_state_not_found':
    case 'bad_oauth_state':
    case 'bad_oauth_callback':
      return AccountAuthFailure(
        AccountAuthFailureKind.linkExpired,
        field: AccountAuthField.form,
        recovery:
            operation == AccountAuthOperation.magicLink ||
                operation == AccountAuthOperation.callback
            ? AccountAuthRecovery.sendNewLink
            : AccountAuthRecovery.retry,
      );
    case 'access_denied':
      return const AccountAuthFailure(
        AccountAuthFailureKind.cancelled,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.none,
      );
  }
  return _operationFallback(operation);
}

String? safeAccountAuthCallbackFailureValue(Uri uri) {
  final parameterSources = [
    uri.queryParametersAll,
    if (uri.hasFragment) Uri(query: uri.fragment).queryParametersAll,
  ];
  String? rawCode;
  for (final key in const ['error_code', 'error']) {
    final values = [for (final source in parameterSources) ...?source[key]];
    if (values.length == 1 && values.single.isNotEmpty) {
      rawCode = values.single;
      break;
    }
  }
  final hasCallbackError =
      rawCode != null ||
      parameterSources.any((source) => source.containsKey('error_description'));
  if (!hasCallbackError) return null;
  final failure = _classifyAuthCode(rawCode, AccountAuthOperation.callback);
  return switch (failure.kind) {
    AccountAuthFailureKind.emailUnconfirmed ||
    AccountAuthFailureKind.rateLimited ||
    AccountAuthFailureKind.emailRateLimited ||
    AccountAuthFailureKind.offline ||
    AccountAuthFailureKind.timeout ||
    AccountAuthFailureKind.serviceUnavailable ||
    AccountAuthFailureKind.providerUnavailable ||
    AccountAuthFailureKind.accountRestricted ||
    AccountAuthFailureKind.linkExpired ||
    AccountAuthFailureKind.cancelled => failure.kind.name,
    _ => AccountAuthFailureKind.unexpected.name,
  };
}

AccountAuthFailure? accountAuthCallbackFailureFromValue(String? value) {
  AccountAuthFailureKind? kind;
  for (final candidate in AccountAuthFailureKind.values) {
    if (candidate.name == value) {
      kind = candidate;
      break;
    }
  }
  if (kind == null) return null;
  return switch (kind) {
    AccountAuthFailureKind.emailUnconfirmed => const AccountAuthFailure(
      AccountAuthFailureKind.emailUnconfirmed,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.none,
    ),
    AccountAuthFailureKind.rateLimited => const AccountAuthFailure(
      AccountAuthFailureKind.rateLimited,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.none,
    ),
    AccountAuthFailureKind.emailRateLimited => const AccountAuthFailure(
      AccountAuthFailureKind.emailRateLimited,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.none,
    ),
    AccountAuthFailureKind.offline => const AccountAuthFailure(
      AccountAuthFailureKind.offline,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    ),
    AccountAuthFailureKind.timeout => const AccountAuthFailure(
      AccountAuthFailureKind.timeout,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    ),
    AccountAuthFailureKind.serviceUnavailable => const AccountAuthFailure(
      AccountAuthFailureKind.serviceUnavailable,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    ),
    AccountAuthFailureKind.providerUnavailable => const AccountAuthFailure(
      AccountAuthFailureKind.providerUnavailable,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.chooseAnotherProvider,
    ),
    AccountAuthFailureKind.accountRestricted => const AccountAuthFailure(
      AccountAuthFailureKind.accountRestricted,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.none,
    ),
    AccountAuthFailureKind.linkExpired => const AccountAuthFailure(
      AccountAuthFailureKind.linkExpired,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.sendNewLink,
    ),
    AccountAuthFailureKind.cancelled => const AccountAuthFailure(
      AccountAuthFailureKind.cancelled,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.none,
    ),
    AccountAuthFailureKind.unexpected => const AccountAuthFailure(
      AccountAuthFailureKind.unexpected,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    ),
    _ => null,
  };
}

AccountAuthFailure _operationFallback(AccountAuthOperation operation) {
  if (operation == AccountAuthOperation.bootstrap) {
    return const AccountAuthFailure(
      AccountAuthFailureKind.serviceUnavailable,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    );
  }
  if (operation == AccountAuthOperation.apple ||
      operation == AccountAuthOperation.google) {
    return const AccountAuthFailure(
      AccountAuthFailureKind.providerUnavailable,
      field: AccountAuthField.form,
      recovery: AccountAuthRecovery.retry,
    );
  }
  if (operation == AccountAuthOperation.captcha) {
    return const AccountAuthFailure(
      AccountAuthFailureKind.captchaUnavailable,
      field: AccountAuthField.captcha,
      recovery: AccountAuthRecovery.retryCaptcha,
    );
  }
  return const AccountAuthFailure(
    AccountAuthFailureKind.unexpected,
    field: AccountAuthField.form,
    recovery: AccountAuthRecovery.retry,
  );
}

AccountAuthFeedback presentAccountAuthFailure(
  AppLocalizations l10n,
  AccountAuthFailure failure, {
  required AccountAuthOperation operation,
  String? provider,
}) {
  final message = switch (failure.kind) {
    AccountAuthFailureKind.emailRequired => l10n.authEmailRequired,
    AccountAuthFailureKind.emailInvalid => l10n.authEmailInvalid,
    AccountAuthFailureKind.passwordRequired => l10n.authPasswordRequired,
    AccountAuthFailureKind.invalidCredentials => l10n.authInvalidCredentials,
    AccountAuthFailureKind.emailUnconfirmed => l10n.authEmailUnconfirmed,
    AccountAuthFailureKind.weakPassword => l10n.authWeakPassword,
    AccountAuthFailureKind.accountMayExist => l10n.authAccountMayExist,
    AccountAuthFailureKind.rateLimited => l10n.authRateLimited,
    AccountAuthFailureKind.emailRateLimited => l10n.authEmailRateLimited,
    AccountAuthFailureKind.offline => l10n.authOffline,
    AccountAuthFailureKind.timeout => l10n.authTimeout,
    AccountAuthFailureKind.serviceUnavailable => l10n.authServiceUnavailable,
    AccountAuthFailureKind.captchaRequired => l10n.authCaptchaRequired,
    AccountAuthFailureKind.captchaExpired => l10n.authCaptchaExpired,
    AccountAuthFailureKind.captchaFailed => l10n.authCaptchaFailed,
    AccountAuthFailureKind.captchaCancelled => l10n.authCaptchaCancelled,
    AccountAuthFailureKind.captchaUnavailable => l10n.authCaptchaUnavailable,
    AccountAuthFailureKind.captchaOpenFailed => l10n.authCaptchaOpenFailed,
    AccountAuthFailureKind.providerUnavailable => l10n.authProviderUnavailable(
      provider ?? l10n.authProviderFallback,
    ),
    AccountAuthFailureKind.signUpDisabled => l10n.authSignUpDisabled,
    AccountAuthFailureKind.accountRestricted => l10n.authAccountRestricted,
    AccountAuthFailureKind.linkExpired => l10n.authLinkExpired,
    AccountAuthFailureKind.cancelled => '',
    AccountAuthFailureKind.unexpected => switch (operation) {
      AccountAuthOperation.signUp => l10n.authUnexpectedSignUp,
      AccountAuthOperation.magicLink => l10n.authUnexpectedMagicLink,
      _ => l10n.authUnexpectedSignIn,
    },
  };
  return AccountAuthFeedback(
    message: message,
    field: failure.field,
    recovery: failure.recovery,
  );
}

String accountAuthRecoveryLabel(
  AppLocalizations l10n,
  AccountAuthRecovery recovery,
) {
  return switch (recovery) {
    AccountAuthRecovery.retry => l10n.commonRetry,
    AccountAuthRecovery.retryCaptcha => l10n.authRetryVerification,
    AccountAuthRecovery.switchToSignIn => l10n.registerSignInAction,
    AccountAuthRecovery.sendNewLink => l10n.authSendLink,
    AccountAuthRecovery.chooseAnotherProvider => l10n.authSignInAction,
    AccountAuthRecovery.none ||
    AccountAuthRecovery.editEmail ||
    AccountAuthRecovery.editPassword => '',
  };
}

bool _isCancellationCode(String value) {
  final normalized = value.toLowerCase().replaceAll('_', '');
  return normalized == 'cancelled' ||
      normalized == 'canceled' ||
      normalized == 'usercancelled' ||
      normalized == 'usercanceled';
}
