import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_management_dependencies.dart';
import 'package:pomodoist/data/repositories/account/account_management_repository.dart';

final class TelegramAccountLinkState {
  const TelegramAccountLinkState({
    this.email,
    this.available = false,
    this.submitting = false,
    this.complete = false,
    this.error,
  });
  final String? email;
  final bool available;
  final bool submitting;
  final bool complete;
  final Object? error;
}

final telegramAccountLinkViewModelProvider = NotifierProvider.autoDispose
    .family<TelegramAccountLinkViewModel, TelegramAccountLinkState, String>(
      TelegramAccountLinkViewModel.new,
    );

class TelegramAccountLinkViewModel extends Notifier<TelegramAccountLinkState> {
  TelegramAccountLinkViewModel(this.token);
  final String token;
  AccountManagementRepository? _repository;
  var _generation = 0;
  @override
  TelegramAccountLinkState build() {
    _repository = ref.watch(accountManagementRepositoryProvider);
    ++_generation;
    ref.onDispose(() => _generation++);
    return TelegramAccountLinkState(
      email: _repository?.email,
      available:
          _repository?.isCurrent == true &&
          _repository?.email != null &&
          token.isNotEmpty,
    );
  }

  Future<void> confirm() async {
    if (state.submitting || !state.available) return;
    final generation = _generation;
    state = TelegramAccountLinkState(
      email: state.email,
      available: true,
      submitting: true,
    );
    try {
      (await _repository!.connectTelegram(token)).getOrThrow();
      if (!ref.mounted || generation != _generation) return;
      state = TelegramAccountLinkState(
        email: state.email,
        available: true,
        complete: true,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = TelegramAccountLinkState(
        email: state.email,
        available: true,
        error: error,
      );
    }
  }

  Future<void> returnToTelegram(String botName) async {
    await ref.read(telegramReturnLauncherProvider)(
      Uri.https('t.me', '/$botName', {'startapp': 'linked'}),
    );
  }
}
