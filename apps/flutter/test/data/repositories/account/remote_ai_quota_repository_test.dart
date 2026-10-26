import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomodoist/data/repositories/account/remote_ai_quota_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final payload = {
    'used': 137,
    'limit': 250,
    'resetsAt': '2026-11-01T00:00:00Z',
  };
  SupabaseClient client(Future<http.Response> Function(http.Request) handler) {
    final value = SupabaseClient(
      'https://quota.example.test',
      'public-key',
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'reads authenticated server quota without client-selected owner or hardcoded limit',
    () async {
      final repository = RemoteAiQuotaRepository(
        client: client((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_usage_period');
          expect(jsonDecode(request.body), {
            'p_app_id': 'pomodoist',
            'p_quota_key': 'llm_requests',
          });
          return http.Response(
            jsonEncode(payload),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        owner: 'first',
        currentUserId: () => 'first',
        timeout: const Duration(seconds: 1),
      );
      final quota = await repository.load();
      expect(quota.used, 137);
      expect(quota.limit, 250);
      expect(quota.remaining, 113);
      expect(quota.resetsAt, DateTime.utc(2026, 11));
    },
  );
  test(
    'rejects a response after the account changes during its request',
    () async {
      var owner = 'first';
      final pending = Completer<http.Response>();
      final repository = RemoteAiQuotaRepository(
        client: client((_) => pending.future),
        owner: 'first',
        currentUserId: () => owner,
        timeout: const Duration(seconds: 1),
      );
      final result = repository.load();
      final assertion = expectLater(result, throwsStateError);
      owner = 'second';
      pending.complete(
        http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await assertion;
    },
  );
  test('rejects malformed server response', () async {
    final repository = RemoteAiQuotaRepository(
      client: client(
        (_) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      owner: 'first',
      currentUserId: () => 'first',
      timeout: const Duration(seconds: 1),
    );
    await expectLater(repository.load(), throwsFormatException);
  });
}
