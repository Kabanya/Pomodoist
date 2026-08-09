import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/router.dart';
import 'package:pomodoist/features/settings/presentation/telegram_account_link_screen.dart';

void main() {
  test(
    'Telegram account link route requires web sign in and preserves token',
    () {
      final redirect = webAppRedirectFor(
        isWeb: true,
        signedIn: false,
        uri: Uri.parse('/telegram-account-link?token=abc_123'),
      );

      expect(
        redirect,
        '/login?returnTo=%2Ftelegram-account-link%3Ftoken%3Dabc_123',
      );
    },
  );

  testWidgets('confirms the selected email and returns to the production bot', (
    tester,
  ) async {
    final tokens = <String>[];
    final launched = <Uri>[];
    final account = _Account();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountClientProvider.overrideWithValue(account),
          telegramAccountLinkCompleterProvider.overrideWithValue((
            _,
            token,
          ) async {
            tokens.add(token);
          }),
          telegramReturnLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(
          home: TelegramAccountLinkScreen(
            token: 'valid_link_token_1234567890123456789012345',
            botName: 'pomodoist_bot',
          ),
        ),
      ),
    );

    expect(find.text('person@example.com'), findsOneWidget);
    await tester.tap(find.byKey(const Key('telegram-link-confirm')));
    await tester.pumpAndSettle();

    expect(tokens, ['valid_link_token_1234567890123456789012345']);
    expect(find.byKey(const Key('telegram-link-success')), findsOneWidget);

    await tester.tap(find.byKey(const Key('telegram-link-return')));
    await tester.pump();
    expect(
      launched.single,
      Uri.parse('https://t.me/pomodoist_bot?startapp=linked'),
    );
  });

  testWidgets('shows a stable error without linking another account', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountClientProvider.overrideWithValue(_Account()),
          telegramAccountLinkCompleterProvider.overrideWithValue((_, _) async {
            throw StateError('link_conflict');
          }),
        ],
        child: const MaterialApp(
          home: TelegramAccountLinkScreen(
            token: 'valid_link_token_1234567890123456789012345',
            botName: 'pomodoist_bot',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('telegram-link-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('telegram-link-error')), findsOneWidget);
    expect(find.byKey(const Key('telegram-link-confirm')), findsOneWidget);
  });
}

class _Account implements AccountClient {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentEmail => 'person@example.com';

  @override
  AccountSession? get currentSession => const AccountSession(
    userId: 'user-1',
    email: 'person@example.com',
    accessToken: 'access-token',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
