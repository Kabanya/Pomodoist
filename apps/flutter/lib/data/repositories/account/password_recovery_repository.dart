import 'package:pomodoist/domain/models/account/account_auth_failure.dart';
import 'package:pomodoist/domain/models/account/password_recovery.dart';

/// Only the SDK's verified recovery event grants permission to edit a password.
/// URL parameters select a screen; they never grant recovery permission.
abstract interface class PasswordRecoveryRepository {
  PasswordRecoveryState get state;
  Stream<PasswordRecoveryState> watchState();
  void dispose();
  PasswordRecoveryStage get stage;

  AccountAuthFailure? get failure;

  bool get sending;

  bool get updating;

  bool get takingLonger;

  bool get available;

  bool get canSave;

  bool get needsRoute;

  void beginCallback({AccountAuthFailure? failure});

  Future<bool> requestEmail(
    String email, {
    required String redirectTo,
    String? captchaToken,
  });

  Future<bool> savePassword(String password, String confirmation);

  void clearFailure();

  void dismiss();
}
