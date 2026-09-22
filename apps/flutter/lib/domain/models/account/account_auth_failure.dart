import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/settings/app_language.dart';

enum AccountAuthOperation {
  bootstrap,
  passwordSignIn,
  signUp,
  magicLink,
  confirmationEmail,
  passwordReset,
  passwordUpdate,
  apple,
  google,
  callback,
  captcha,
}

enum AccountAuthFailureKind {
  emailRequired,
  emailInvalid,
  passwordRequired,
  passwordMismatch,
  passwordUnchanged,
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
  resendConfirmation,
  chooseAnotherProvider,
}

final class AccountAuthFailure implements Exception {
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

AccountAuthFailure classifyAccountAuthCode(
  String? code,
  AccountAuthOperation operation,
) {
  switch (code) {
    case 'invalid_credentials':
    case 'user_not_found':
      return const AccountAuthFailure(
        AccountAuthFailureKind.invalidCredentials,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.editPassword,
      );
    case 'email_not_confirmed':
      return AccountAuthFailure(
        AccountAuthFailureKind.emailUnconfirmed,
        field: AccountAuthField.email,
        recovery: operation == AccountAuthOperation.passwordSignIn
            ? AccountAuthRecovery.resendConfirmation
            : AccountAuthRecovery.none,
      );
    case 'provider_email_needs_verification':
      return const AccountAuthFailure(
        AccountAuthFailureKind.emailUnconfirmed,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.none,
      );
    case 'same_password':
      return const AccountAuthFailure(
        AccountAuthFailureKind.passwordUnchanged,
        field: AccountAuthField.password,
        recovery: AccountAuthRecovery.editPassword,
      );
    case 'session_not_found':
    case 'session_expired':
    case 'refresh_token_not_found':
    case 'bad_jwt':
      if (operation == AccountAuthOperation.passwordUpdate) {
        return const AccountAuthFailure(
          AccountAuthFailureKind.linkExpired,
          field: AccountAuthField.form,
          recovery: AccountAuthRecovery.sendNewLink,
        );
      }
      return accountAuthOperationFallback(operation);
    case 'weak_password':
      return const AccountAuthFailure(
        AccountAuthFailureKind.weakPassword,
        field: AccountAuthField.password,
        recovery: AccountAuthRecovery.editPassword,
      );
    case 'email_exists':
    case 'user_already_exists':
    case 'identity_already_exists':
      return const AccountAuthFailure(
        AccountAuthFailureKind.accountMayExist,
        field: AccountAuthField.email,
        recovery: AccountAuthRecovery.switchToSignIn,
      );
    case 'email_address_invalid':
    case 'validation_failed':
      if (operation == AccountAuthOperation.passwordUpdate) {
        return accountAuthOperationFallback(operation);
      }
      return const AccountAuthFailure(
        AccountAuthFailureKind.emailInvalid,
        field: AccountAuthField.email,
        recovery: AccountAuthRecovery.editEmail,
      );
    case 'over_email_send_rate_limit':
      return const AccountAuthFailure(
        AccountAuthFailureKind.emailRateLimited,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.none,
      );
    case 'email_send_failed':
    case 'email_address_not_authorized':
    case 'conflict':
      return const AccountAuthFailure(
        AccountAuthFailureKind.serviceUnavailable,
        field: AccountAuthField.form,
        recovery: AccountAuthRecovery.retry,
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
    case 'otp_disabled':
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
    case 'bad_code_verifier':
    case 'reauthentication_needed':
    case 'reauthentication_not_valid':
      return AccountAuthFailure(
        AccountAuthFailureKind.linkExpired,
        field: AccountAuthField.form,
        recovery:
            operation == AccountAuthOperation.magicLink ||
                operation == AccountAuthOperation.callback ||
                operation == AccountAuthOperation.passwordReset ||
                operation == AccountAuthOperation.passwordUpdate
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
  return accountAuthOperationFallback(operation);
}

String accountAuthRedirect(String loginRedirect, String returnTo) {
  final uri = Uri.parse(loginRedirect);
  if (uri.scheme == appFlavor.urlScheme) {
    // Supabase matches the redirect allowlist without the fragment, but with
    // the query. Keep navigation metadata out of the registered callback URL.
    final query = {...uri.queryParameters}..remove('returnTo');
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
      fragment: Uri(queryParameters: {'returnTo': returnTo}).query,
    ).toString();
  }
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'returnTo': returnTo})
      .toString();
}

/// Locale is presentation metadata; the registered callback and PKCE stay intact.
String localizedAccountAuthRedirect(String redirect, String? languageTag) {
  final language = AppLanguage.fromLanguageTag(languageTag);
  if (language == null) return redirect;
  final uri = Uri.parse(redirect);
  return uri
      .replace(
        fragment: Uri(
          queryParameters: {
            ...Uri(query: uri.fragment).queryParameters,
            'lang': language.languageTag!,
          },
        ).query,
      )
      .toString();
}

String? accountAuthCallbackReturnTo(Uri uri) {
  final values = [
    ...?uri.queryParametersAll['returnTo'],
    if (uri.hasFragment)
      ...?Uri(query: uri.fragment).queryParametersAll['returnTo'],
  ];
  return values.length == 1 ? values.single : null;
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
  final failure = classifyAccountAuthCode(
    rawCode,
    AccountAuthOperation.callback,
  );
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

AccountAuthFailure accountAuthOperationFallback(
  AccountAuthOperation operation,
) {
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

/// Sanitizes recovery navigation. The SDK still owns the original callback and
/// must verify its credentials before the recovery controller permits an update.
String? passwordRecoveryCallbackLocation(Uri uri) {
  final returnTo = accountAuthCallbackReturnTo(uri);
  final types = [
    ...?uri.queryParametersAll['type'],
    if (uri.hasFragment)
      ...?Uri(query: uri.fragment).queryParametersAll['type'],
  ];
  final recovery =
      returnTo == '/reset-password' ||
      (types.length == 1 && types.single == 'recovery');
  if (!recovery) return null;
  return Uri(
    path: '/reset-password',
    queryParameters: {
      'callback': '1',
      'authFailure': ?safeAccountAuthCallbackFailureValue(uri),
    },
  ).toString();
}

String passwordRecoveryRedirect(String loginRedirect) =>
    accountAuthRedirect(loginRedirect, '/reset-password');
