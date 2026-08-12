import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/account_providers.dart';

typedef TelegramAccountLinkCompleter =
    Future<void> Function(AccountClient account, String token);
typedef TelegramReturnLauncher = Future<bool> Function(Uri uri);

final telegramAccountLinkCompleterProvider =
    Provider<TelegramAccountLinkCompleter>((ref) {
      return (account, token) async {
        final response = await account.invokeFunction(
          'pomodoist-telegram',
          body: {'action': 'complete_link', 'token': token},
        );
        final data = response.data;
        if (response.status < 200 ||
            response.status >= 300 ||
            data is! Map ||
            data['ok'] != true) {
          throw StateError(
            data is Map ? '${data['code'] ?? 'link_failed'}' : 'link_failed',
          );
        }
      };
    });

final telegramReturnLauncherProvider = Provider<TelegramReturnLauncher>((ref) {
  return (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
});

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
  bool _submitting = false;
  bool _complete = false;
  Object? _error;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountClientProvider);
    final email = account?.currentEmail ?? account?.currentSession?.email;
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
                  child: _complete
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
                            if (_error != null) ...[
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
                            FilledButton(
                              key: const Key('telegram-link-confirm'),
                              onPressed:
                                  account == null ||
                                      email == null ||
                                      _submitting ||
                                      widget.token.isEmpty
                                  ? null
                                  : () => _confirm(account),
                              child: _submitting
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
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

  Future<void> _confirm(AccountClient account) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(telegramAccountLinkCompleterProvider)(
        account,
        widget.token,
      );
      if (mounted) setState(() => _complete = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _returnToTelegram() {
    return ref.read(telegramReturnLauncherProvider)(
      Uri.https('t.me', '/${widget.botName}', {'startapp': 'linked'}),
    );
  }
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
          Icons.check_circle,
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
        FilledButton.icon(
          key: const Key('telegram-link-return'),
          onPressed: onReturn,
          icon: const Icon(Icons.telegram),
          label: Text('Return to @$botName'),
        ),
      ],
    );
  }
}
