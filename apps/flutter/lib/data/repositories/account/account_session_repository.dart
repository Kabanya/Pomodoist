import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/utils/result.dart';

abstract interface class AccountSessionRepository {
  AccountSession get currentSession;
  Stream<AccountSession> watchSession();
  Stream<PomodoistAccountProfile?> watchProfile();
  Future<Result<void>> refresh();
}
