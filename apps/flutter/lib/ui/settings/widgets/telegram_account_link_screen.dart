import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/settings/view_models/telegram_account_link_view_model.dart';

class TelegramAccountLinkScreen extends ConsumerStatefulWidget {
  const TelegramAccountLinkScreen({
    required this.token,
    required this.botName,
    super.key,
  });

  final String token;
  final String botName;

  @override
  ConsumerState<TelegramAccountLinkScreen> createState() =>
      _TelegramAccountLinkScreenState();
}

class _TelegramAccountLinkScreenState
    extends ConsumerState<TelegramAccountLinkScreen> {
  late TelegramAccountLinkState _state;
  TelegramAccountLinkViewModel get _viewModel =>
      ref.read(telegramAccountLinkViewModelProvider(widget.token).notifier);

  @override
  Widget build(BuildContext context) {
    _state = ref.watch(telegramAccountLinkViewModelProvider(widget.token));
    final email = _state.email;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _state.complete
                      ? _Success(
                          botName: widget.botName,
                          onReturn: _returnToTelegram,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(Icons.telegram, size: 52),
                            const SizedBox(height: 16),
                            Text(
                              'Connect Telegram to Pomodoist',
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Telegram tasks and completed Focus intervals '
                              'will be merged into this account.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              email ?? 'Signed-in account',
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            if (_state.error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                'The account could not be linked. '
                                'Check that the link is current and no '
                                'conflicting Focus is active.',
                                key: const Key('telegram-link-error'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 20),
                            ShadButton(
                              key: const Key('telegram-link-confirm'),
                              enabled: _state.available && !_state.submitting,
                              onPressed: _state.available && !_state.submitting
                                  ? _viewModel.confirm
                                  : null,
                              child: _state.submitting
                                  ? SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    )
                                  : const Text('Connect this account'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _returnToTelegram() =>
      _viewModel.returnToTelegram(widget.botName);
}

class _Success extends StatelessWidget {
  const _Success({required this.botName, required this.onReturn});

  final String botName;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('telegram-link-success'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          LucideIcons.circleCheck,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Account connected',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'Your Telegram Inbox is now syncing with Pomodoist.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        ShadButton(
          key: const Key('telegram-link-return'),
          onPressed: onReturn,
          leading: const Icon(Icons.telegram),
          child: Text('Return to @$botName'),
        ),
      ],
    );
  }
}
