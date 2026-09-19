import 'support/test_app.dart';
import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/account_management_dependencies.dart';
import 'package:pomodoist/data/repositories/account/account_management_repository.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/routing/router.dart';
import 'package:pomodoist/ui/settings/widgets/telegram_account_link_screen.dart';

void main() {
  setUpAll(loadTestAppResources);
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
          accountManagementRepositoryProvider.overrideWithValue(
            _ManagementRepository(
              connect: (token) async {
                tokens.add(token);
                return const Result.ok(null);
              },
            ),
          ),
          telegramReturnLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(
          builder: testAppBuilder,
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
          accountManagementRepositoryProvider.overrideWithValue(
            _ManagementRepository(
              connect: (_) async =>
                  Result.error(StateError('link_conflict'), StackTrace.current),
            ),
          ),
        ],
        child: const MaterialApp(
          builder: testAppBuilder,
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

class _ManagementRepository implements AccountManagementRepository {
  const _ManagementRepository({required this.connect});

  final Future<Result<void>> Function(String token) connect;

  @override
  String? get userId => 'user-1';

  @override
  String? get email => 'person@example.com';

  @override
  bool get isCurrent => true;

  @override
  Future<Result<void>> connectTelegram(String token) => connect(token);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
