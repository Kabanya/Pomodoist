import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/auth/password_recovery.dart';
import 'package:pomodoist/config/auth/account_auth_actions.dart';
import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/email_auth.dart';
import 'package:pomodoist/domain/models/account/password_recovery.dart';
import 'package:pomodoist/domain/models/account/social_provider.dart';

export 'package:pomodoist/domain/models/account/social_provider.dart';

final class AccountProfileState {
  const AccountProfileState({required this.displayName, required this.email});

  final String? displayName;
  final String? email;
}

final class PasswordRecoveryUiState {
  const PasswordRecoveryUiState({
    required this.stage,
    required this.failure,
    required this.available,
    required this.updating,
    required this.takingLonger,
    required this.needsRoute,
  });

  final PasswordRecoveryStage stage;
  final AccountAuthFailure? failure;
  final bool available;
  final bool updating;
  final bool takingLonger;
  final bool needsRoute;
}

final class AuthUiState {
  const AuthUiState({
    required this.available,
    required this.configured,
    required this.signedIn,
    required this.loading,
    required this.bootstrapError,
    required this.profile,
    required this.profileLoading,
    required this.profileError,
    required this.turnstileSiteKey,
    required this.recovery,
  });

  final bool available;
  final bool configured;
  final bool signedIn;
  final bool loading;
  final Object? bootstrapError;
  final AccountProfileState? profile;
  final bool profileLoading;
  final Object? profileError;
  final String turnstileSiteKey;
  final PasswordRecoveryUiState recovery;

  bool get canSignIn => available && !signedIn;
  bool get captchaEnabled => turnstileSiteKey.isNotEmpty;
}

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthUiState>(
  AuthViewModel.new,
);

final guestDataStartupViewModelProvider =
    AsyncNotifierProvider.autoDispose<GuestDataStartupViewModel, void>(
      GuestDataStartupViewModel.new,
    );

final class GuestDataStartupViewModel extends AsyncNotifier<void> {
  @override
  Future<void> build() => ref.watch(guestDataStartupProvider.future);

  void retry() {
    ref.invalidate(guestDataStartupProvider);
    ref.invalidateSelf();
  }
}

final class AuthViewModel extends Notifier<AuthUiState> {
  @override
  AuthUiState build() {
    final availability = ref.watch(accountAvailabilityProvider);
    final signedIn = ref.watch(accountSignedInProvider);
    final overview = ref.watch(accountOverviewProvider);
    ref.watch(passwordRecoveryStateProvider);
    final recovery = ref.watch(passwordRecoveryProvider);
    final profile = ref.watch(accountProfileProvider);
    return AuthUiState(
      available: availability.available,
      configured: availability.configured,
      signedIn: signedIn,
      loading: availability.loading,
      bootstrapError: availability.error,
      profile: profile == null
          ? null
          : AccountProfileState(
              displayName: profile.displayName,
              email: profile.email,
            ),
      profileLoading: overview.isLoading,
      profileError: overview.error,
      turnstileSiteKey: ref.watch(
        runtimePublicConfigProvider.select((value) => value.turnstileSiteKey),
      ),
      recovery: PasswordRecoveryUiState(
        stage: recovery.stage,
        failure: recovery.failure,
        available: recovery.available,
        updating: recovery.updating,
        takingLonger: recovery.takingLonger,
        needsRoute: recovery.needsRoute,
      ),
    );
  }

  Future<void> retry() => ref.read(accountBootstrapProvider.notifier).retry();

  void refresh() => ref.invalidate(accountOverviewProvider);

  AccountAuthFailure classify(
    Object error, {
    required AccountAuthOperation operation,
  }) => ref
      .read(accountAuthActionsRepositoryProvider)
      .classify(error, operation: operation);

  Future<bool> signInSocial({
    required PomodoistSocialProvider provider,
    required String redirectTo,
  }) async {
    final result = await ref
        .read(accountAuthActionsRepositoryProvider)
        .signInSocial(provider, redirectTo: redirectTo);
    try {
      return result.getOrThrow();
    } on Object catch (error) {
      throw classify(
        error,
        operation: provider == PomodoistSocialProvider.apple
            ? AccountAuthOperation.apple
            : AccountAuthOperation.google,
      );
    }
  }

  Future<EmailAuthResult?> submitEmail({
    required EmailAuthAction action,
    required String email,
    String password = '',
    required String redirectTo,
    String? captchaToken,
  }) async {
    final operation = switch (action) {
      EmailAuthAction.signIn => AccountAuthOperation.passwordSignIn,
      EmailAuthAction.signUp => AccountAuthOperation.signUp,
      EmailAuthAction.magicLink => AccountAuthOperation.magicLink,
      EmailAuthAction.resendConfirmation =>
        AccountAuthOperation.confirmationEmail,
    };
    try {
      final result = await ref
          .read(accountAuthActionsRepositoryProvider)
          .submitEmail(
            action: action,
            email: email,
            password: password,
            redirectTo: redirectTo,
            captchaToken: captchaToken,
          );
      return result.getOrThrow();
    } on Object catch (error) {
      throw classify(error, operation: operation);
    }
  }

  Future<String?> requestNativeCaptcha(String locale) async {
    if (!state.captchaEnabled) return null;
    final result = await ref
        .read(accountAuthActionsRepositoryProvider)
        .requestNativeCaptcha(locale);
    try {
      return result.getOrThrow();
    } on Object catch (error) {
      throw classify(error, operation: AccountAuthOperation.captcha);
    }
  }

  Future<bool> requestPasswordReset(
    String email, {
    required String redirectTo,
    String? captchaToken,
  }) => ref
      .read(passwordRecoveryProvider)
      .requestEmail(
        email,
        redirectTo: passwordRecoveryRedirect(redirectTo),
        captchaToken: captchaToken,
      );

  void beginPasswordRecovery({AccountAuthFailure? failure}) =>
      ref.read(passwordRecoveryProvider).beginCallback(failure: failure);

  Future<bool> savePassword(String password, String confirmation) =>
      ref.read(passwordRecoveryProvider).savePassword(password, confirmation);

  void dismissPasswordRecovery() =>
      ref.read(passwordRecoveryProvider).dismiss();
}

String loginRedirectFor(String returnTo) =>
    accountAuthRedirect(pomodoistLoginRedirect, returnTo);
