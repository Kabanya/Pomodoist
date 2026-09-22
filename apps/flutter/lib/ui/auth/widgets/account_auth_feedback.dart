import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/domain/models/account/account_auth_failure.dart';

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

AccountAuthFeedback presentAccountAuthFailure(
  AppLocalizations l10n,
  AccountAuthFailure failure, {
  required AccountAuthOperation operation,
  String? provider,
  bool providerSignInDisabled = false,
}) {
  final message = switch (failure.kind) {
    AccountAuthFailureKind.emailRequired => l10n.authEmailRequired,
    AccountAuthFailureKind.emailInvalid => l10n.authEmailInvalid,
    AccountAuthFailureKind.passwordRequired => l10n.authPasswordRequired,
    AccountAuthFailureKind.passwordMismatch => l10n.authPasswordMismatch,
    AccountAuthFailureKind.passwordUnchanged => l10n.authPasswordUnchanged,
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
    AccountAuthFailureKind.providerUnavailable =>
      providerSignInDisabled
          ? l10n.authProviderUnavailableHere(
              provider ?? l10n.authProviderFallback,
            )
          : l10n.authProviderUnavailable(
              provider ?? l10n.authProviderFallback,
            ),
    AccountAuthFailureKind.signUpDisabled => l10n.authSignUpDisabled,
    AccountAuthFailureKind.accountRestricted => l10n.authAccountRestricted,
    AccountAuthFailureKind.linkExpired =>
      operation == AccountAuthOperation.passwordUpdate ||
              operation == AccountAuthOperation.passwordReset
          ? l10n.authResetLinkExpired
          : l10n.authLinkExpired,
    AccountAuthFailureKind.cancelled => '',
    AccountAuthFailureKind.unexpected => switch (operation) {
      AccountAuthOperation.signUp => l10n.authUnexpectedSignUp,
      AccountAuthOperation.magicLink => l10n.authUnexpectedMagicLink,
      AccountAuthOperation.confirmationEmail => l10n.authConfirmationSendFailed,
      AccountAuthOperation.passwordReset => l10n.authUnexpectedReset,
      AccountAuthOperation.passwordUpdate => l10n.authUnexpectedPasswordUpdate,
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
    AccountAuthRecovery.resendConfirmation => l10n.authResendConfirmation,
    AccountAuthRecovery.chooseAnotherProvider => l10n.authSignInAction,
    AccountAuthRecovery.none ||
    AccountAuthRecovery.editEmail ||
    AccountAuthRecovery.editPassword => '',
  };
}
