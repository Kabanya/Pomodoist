import 'account_auth_failure.dart';

enum PasswordRecoveryStage { idle, checking, ready, saving, updated, invalid }

typedef PasswordRecoveryState = ({
  PasswordRecoveryStage stage,
  AccountAuthFailure? failure,
  bool sending,
  bool updating,
  bool takingLonger,
  bool available,
  bool canSave,
  bool needsRoute,
});
