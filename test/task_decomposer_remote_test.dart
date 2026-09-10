import 'package:app_account/app_account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';

void main() {
  for (final signedIn in [true, false]) {
    test(
      'task analysis uses ${signedIn ? 'account access without StoreKit' : 'StoreKit proofs without an account'}',
      () async {
        final account = _Account(signedIn ? 'account-id' : null);
        var reads = 0;
        final store = BillingStore(
          transactionLoader: () async {
            reads++;
            if (signedIn) throw StateError('StoreKit unavailable');
            return const [
              BillingTransactionProof(
                productId: pomodoistLifetimeProductId,
                jws: 'verified-proof',
              ),
            ];
          },
        );
        final container = ProviderContainer(
          overrides: [
            accountClientProvider.overrideWithValue(account),
            billingStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(container.dispose);
        final tasks = await container
            .read(taskDecomposerProvider)
            .decompose(
              'Buy milk',
              now: DateTime.utc(2026, 9, 10),
              locale: 'en',
            );
        expect(tasks.single.quickAdd, 'Buy milk');
        expect(reads, signedIn ? 0 : 1);
        expect(
          account.body?['storeTransactions'],
          signedIn ? isEmpty : ['verified-proof'],
        );
      },
    );
  }
  test('Supabase decomposer sends local time and smart mode', () async {
    Map<String, Object?>? request;
    final now = DateTime.parse('2026-07-13T12:00:00+03:00');
    final decomposer = SupabaseTaskDecomposer(
      transport: (body) async {
        request = body;
        return {
          'ok': true,
          'tasks': [
            {
              'quickAdd': 'Подготовить отчет tomorrow 10:00',
              'description': 'Собрать цифры',
              'subtasks': [
                {'quickAdd': 'Экспортировать продажи'},
              ],
            },
          ],
        };
      },
    );

    final tasks = await decomposer.decompose(
      'подготовить отчет завтра утром',
      now: now,
      locale: 'ru-RU',
      smartMode: true,
    );

    final command = (request!['command']! as Map).cast<String, Object?>();
    expect(command, {
      'type': 'task.decomposeTranscript',
      'transcript': 'подготовить отчет завтра утром',
      'locale': 'ru-RU',
      'currentLocalTime': isA<String>(),
      'smart': true,
    });
    final sentLocalTime = command['currentLocalTime']! as String;
    expect(DateTime.parse(sentLocalTime), now);
    expect(sentLocalTime, matches(RegExp(r'[+-]\d{2}:\d{2}$')));
    expect(tasks.single.description, 'Собрать цифры');
    expect(tasks.single.subtasks.single.quickAdd, 'Экспортировать продажи');
  });

  test('Supabase decomposer rejects a malformed success response', () async {
    final decomposer = SupabaseTaskDecomposer(
      transport: (_) async => {'ok': true, 'tasks': const []},
    );

    expect(
      () => decomposer.decompose(
        'купить молоко',
        now: DateTime.utc(2026, 7, 13),
        locale: 'ru-RU',
      ),
      throwsA(isA<TaskDecompositionException>()),
    );
  });
}

class _Account implements AccountClient {
  _Account(this.currentUserId);
  @override
  final String? currentUserId;
  Map? body;
  @override
  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) async {
    expect(functionName, 'pomodoist-watch');
    this.body = body as Map;
    return const AccountFunctionResponse(
      status: 200,
      data: {
        'ok': true,
        'tasks': [
          {'quickAdd': 'Buy milk'},
        ],
      },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
